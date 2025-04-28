package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/image"
	"github.com/docker/docker/client"
	"github.com/docker/go-connections/nat"

	"github.com/prometheus/common/expfmt"
	"github.com/prometheus/common/model"
)

// https://pkg.go.dev/github.com/docker/docker/api
// https://pkg.go.dev/github.com/prometheus/common/expfmt

const (
	defaultTimeout         = 30 * time.Second
	defaultLogTarget       = "Hello 2 from"
	defaultMetricTarget    = `counters_main{function="loop",type="count",variable="tick"}`
	defaultMetricThreshold = 2.0
	defaultParallelism     = 1

	defaultVersion    = "1.0.0"
	defaultRepoPrefix = "randomizedcoder"

	nixImagePrefix    = "nix-go-nix-simple"
	dockerImagePrefix = "docker-go-nix-simple"
)

type ValidationResult struct {
	ImageTag     string
	LogCheck     CheckResult
	MetricCheck  CheckResult
	OverallError error
	Duration     time.Duration
	LogBuffer    strings.Builder
}

type CheckResult struct {
	Success bool
	Error   error
}

func (vr ValidationResult) OverallSuccess() bool {
	return vr.LogCheck.Success && vr.MetricCheck.Success && vr.OverallError == nil
}

var (
	mainLogger = log.New(os.Stdout, "", log.LstdFlags|log.Lmicroseconds|log.LUTC)

	nixBases    = []string{"distroless", "scratch"}
	nixBuilders = []string{"buildgomodule", "gomod2nix"}
	nixPackers  = []string{"noupx", "upx"}

	dockerBases   = []string{"distroless", "scratch"}
	dockerCaches  = []string{"docker", "athens", "http", "none"}
	dockerPackers = []string{"noupx", "upx"}
)

func main() {

	log.SetOutput(io.Discard)

	imageTagsRaw := flag.String("images", "all", "Comma-separated list of Docker image tags to validate (required)")
	parallelism := flag.Int("parallel", defaultParallelism, "Number of concurrent validation tests to run")
	timeout := flag.Duration("timeout", defaultTimeout, "Timeout for each individual image validation")
	logTarget := flag.String("log-target", defaultLogTarget, "Log line prefix to wait for")
	metricTarget := flag.String("metric-target", defaultMetricTarget, "Prometheus metric name (with labels) to check")
	metricThreshold := flag.Float64("metric-threshold", defaultMetricThreshold, "Minimum value for the target metric")
	version := flag.String("version", defaultVersion, "Version tag for images (used with -images=all)")
	repoPrefix := flag.String("repo-prefix", defaultRepoPrefix, "Repository prefix (e.g., dockerhub username) for images (used with -images=all)")

	flag.Parse()

	var imageTags []string

	if *imageTagsRaw == "" {
		log.Fatal("Error: -images flag is required (provide comma-separated list or 'all')")
	} else if strings.ToLower(*imageTagsRaw) == "all" {
		log.Printf("Generating all known image tags for version %s with prefix %s...", *version, *repoPrefix)
		imageTags = generateAllImageTags(*repoPrefix, *version)
		if len(imageTags) == 0 {
			log.Fatal("Error: Failed to generate any image tags for 'all'")
		}
		log.Printf("Generated %d image tags.", len(imageTags))
	} else {

		tagsFromFlag := strings.Split(*imageTagsRaw, ",")

		for _, tag := range tagsFromFlag {
			trimmedTag := strings.TrimSpace(tag)
			if trimmedTag != "" {
				imageTags = append(imageTags, trimmedTag)
			}
		}
		if len(imageTags) == 0 {
			log.Fatal("Error: No valid image tags provided in the list")
		}
	}

	mainLogger.Printf("Starting validation for %d image(s) with parallelism %d and timeout %v", len(imageTags), *parallelism, *timeout)

	ctx := context.Background()
	validationStartTime := time.Now()

	// --- Setup Worker Pool ---
	jobs := make(chan string, len(imageTags))
	results := make(chan ValidationResult, len(imageTags))
	var wg sync.WaitGroup

	numWorkers := *parallelism
	if numWorkers <= 0 {
		numWorkers = 1
	}
	if numWorkers > len(imageTags) {
		numWorkers = len(imageTags)
	}

	log.Printf("Starting %d worker(s)", numWorkers)
	for w := 1; w <= numWorkers; w++ {
		wg.Add(1)
		go worker(ctx, w, jobs, results, &wg, *timeout, *logTarget, *metricTarget, *metricThreshold, mainLogger)
	}

	// --- Send Jobs ---
	for _, tag := range imageTags {
		trimmedTag := strings.TrimSpace(tag)
		if trimmedTag != "" {
			jobs <- trimmedTag
		}
	}
	close(jobs)

	// --- Wait for Workers and Collect Results ---
	wg.Wait()
	close(results)
	totalValidationDuration := time.Since(validationStartTime) // Calculate total duration

	// --- Store results for summary ---
	var processedResults []ValidationResult
	allSuccessOverall := true

	for res := range results {
		processedResults = append(processedResults, res)
		if !res.OverallSuccess() {
			allSuccessOverall = false
		}
	}

	// --- Report Results ---
	mainLogger.Println("--- Validation Summary ---")

	// Sort results alphabetically (optional)
	// sort.Slice(processedResults, func(i, j int) bool {
	// 	return processedResults[i].ImageTag < processedResults[j].ImageTag
	// })

	// --- Print Table Header ---
	// Adjust column widths as needed
	mainLogger.Printf("%-80s %-8s %-8s %-18s %s", "Image Tag", "Log", "Metric", "Duration", "Overall Error")
	mainLogger.Println(strings.Repeat("-", 120)) // Separator line

	totalChecks := 0
	passedChecks := 0
	var failedLogsOutput strings.Builder

	// --- Print Table Rows ---
	for _, res := range processedResults {
		totalChecks += 2 // Log + Metric

		logStatus := "FAIL"
		if res.LogCheck.Success {
			logStatus = "PASS"
			passedChecks++
		}

		metricStatus := "FAIL"
		if res.MetricCheck.Success {
			metricStatus = "PASS"
			passedChecks++
		}

		overallErrorStr := ""
		if res.OverallError != nil {
			overallErrorStr = res.OverallError.Error()
			// Optionally truncate long errors
			// if len(overallErrorStr) > 50 {
			//  overallErrorStr = overallErrorStr[:47] + "..."
			// }
		}

		// Print formatted row
		mainLogger.Printf("%-80s %-8s %-8s %-18s %s",
			res.ImageTag,
			logStatus,
			metricStatus,
			res.Duration.Round(time.Millisecond).String(), // Format duration
			overallErrorStr,
		)

		// Store logs if this image failed overall
		if !res.OverallSuccess() {
			failedLogsOutput.WriteString(fmt.Sprintf("\n--- Logs for FAILED image: %s ---\n", res.ImageTag))
			failedLogsOutput.WriteString(res.LogBuffer.String())
			failedLogsOutput.WriteString("--- End Logs ---\n")
		}
	}

	// --- Print Footer ---
	mainLogger.Println(strings.Repeat("-", 120)) // Separator line
	failedChecks := totalChecks - passedChecks
	mainLogger.Printf("Total Images: %d | Total Checks: %d | Passed Checks: %d | Failed Checks: %d",
		len(processedResults), totalChecks, passedChecks, failedChecks)
	mainLogger.Printf("Total Validation Duration: %v", totalValidationDuration.Round(time.Second)) // Print total duration
	mainLogger.Println("--------------------------")

	// Print logs for failed tests if any occurred
	if failedLogsOutput.Len() > 0 {
		mainLogger.Printf("\n--- Details for Failed Validations ---")
		os.Stdout.WriteString(failedLogsOutput.String())
	}

	// Exit based on overall success
	if !allSuccessOverall {
		mainLogger.Println("\nOne or more image validations failed.")
		os.Exit(1)
	}
	mainLogger.Println("\nAll image validations passed.")
}

func generateAllImageTags(repoPrefix, version string) []string {
	var allTags []string

	for _, base := range nixBases {
		for _, builder := range nixBuilders {
			for _, packer := range nixPackers {
				tag := fmt.Sprintf("%s/%s-%s-%s-%s:%s",
					repoPrefix, nixImagePrefix, base, builder, packer, version)
				allTags = append(allTags, tag)
			}
		}
	}

	for _, base := range dockerBases {
		for _, cache := range dockerCaches {
			for _, packer := range dockerPackers {
				// // --- Apply filtering logic  ---
				// if cache != "docker" && packer == "upx" {
				// 	log.Printf("Skipping Docker tag generation for: base=%s, cache=%s, packer=%s (UPX only with 'docker' cache)", base, cache, packer)
				// 	continue
				// }

				tag := fmt.Sprintf("%s/%s-%s-%s-%s:%s",
					repoPrefix, dockerImagePrefix, base, cache, packer, version)
				allTags = append(allTags, tag)
			}
		}
	}

	return allTags
}

// worker executes validation jobs received from the jobs channel.
func worker(ctxIn context.Context,
	id int, jobs <-chan string,
	results chan<- ValidationResult,
	wg *sync.WaitGroup,
	timeout time.Duration,
	logTarget, metricTarget string,
	metricThreshold float64,
	workerLogger *log.Logger) {

	defer wg.Done()

	workerLogger.Printf("Worker %d started", id)

	for imageTag := range jobs {

		log.Printf("Worker %d: Validating image %s", id, imageTag)
		startTime := time.Now()

		ctx, cancel := context.WithTimeout(ctxIn, timeout)

		var logBuf strings.Builder
		jobLogger := log.New(io.MultiWriter(&logBuf, io.Discard), fmt.Sprintf("W%d [%s]: ", id, imageTag[:min(15, len(imageTag))]), log.Ltime|log.Lmicroseconds)

		res := validateImage(ctx, imageTag, logTarget, metricTarget, metricThreshold, jobLogger, &logBuf)
		res.Duration = time.Since(startTime)
		res.LogBuffer = logBuf

		cancel()

		results <- res

		workerLogger.Printf("Worker %d: Finished validating %s (Overall Success: %t, Duration: %v)", id, imageTag, res.OverallSuccess(), res.Duration)
	}
	workerLogger.Printf("Worker %d finished", id)
}

// validateImage performs the actual validation steps for a single image.
func validateImage(
	ctx context.Context,
	imageTag, logTarget, metricTarget string,
	metricThreshold float64,
	jobLogger *log.Logger,
	logBuf *strings.Builder) ValidationResult {

	// Initialize result struct
	result := ValidationResult{
		ImageTag: imageTag,
		// Checks default to failure until proven successful
		LogCheck:    CheckResult{Success: false},
		MetricCheck: CheckResult{Success: false},
	}

	// --- 1. Create Docker Client ---
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		result.OverallError = fmt.Errorf("failed to create docker client: %w", err)
		jobLogger.Printf("ERROR: %v", result.OverallError)
		return result
	}
	defer cli.Close()

	// --- 2. Pull Image ---
	jobLogger.Printf("Pulling image (best effort)...")
	pullCtx, pullCancel := context.WithTimeout(ctx, 2*time.Minute)
	pullReader, err := cli.ImagePull(pullCtx, imageTag, image.PullOptions{})
	if err == nil {
		_, copyErr := io.Copy(logBuf, pullReader)
		pullReader.Close()
		if copyErr != nil {
			jobLogger.Printf("Warning: Error reading image pull output: %v", copyErr)
		}
	}
	pullCancel()
	if err != nil {
		jobLogger.Printf("Warning: Failed to pull image (will try to run anyway): %v", err)
	}

	// --- 3. Create and Start Container ---
	containerPortStr := "9108/tcp"
	//hostPortStr := "9108"
	exposedPortsSet := nat.PortSet{nat.Port(containerPortStr): {}}
	portBindingsMap := nat.PortMap{
		nat.Port(containerPortStr): []nat.PortBinding{
			{
				HostIP:   "0.0.0.0",
				HostPort: "",
			},
		},
	}

	resp, err := cli.ContainerCreate(
		ctx,
		&container.Config{
			Image:        imageTag,
			ExposedPorts: exposedPortsSet,
		},
		&container.HostConfig{
			PortBindings: portBindingsMap,
			AutoRemove:   true,
		}, nil, nil, "")
	if err != nil {
		result.OverallError = fmt.Errorf("failed to create container: %w", err)
		return result // Return early
	}
	containerID := resp.ID
	log.Printf("Created container %s", containerID[:12])

	defer func() {
		log.Printf("Stopping container %s...", containerID[:12])
		stopCtx, stopCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer stopCancel()
		if err := cli.ContainerStop(stopCtx, containerID, container.StopOptions{}); err != nil {
			log.Printf("Warning: Failed to stop container %s: %v", containerID[:12], err)
		} else {
			log.Printf("Stopped container %s", containerID[:12])
		}
	}()

	if err := cli.ContainerStart(ctx, containerID, container.StartOptions{}); err != nil {
		result.OverallError = fmt.Errorf("failed to start container: %w", err)
		return result
	}
	log.Printf("Started container %s", containerID[:12])

	// --- 3.5 Inspect Container to Get Assigned Port ---
	var assignedHostPort string // Variable to store the dynamic port
	inspectResp, err := cli.ContainerInspect(ctx, containerID)
	if err != nil {
		result.OverallError = fmt.Errorf("failed to inspect container %s: %w", containerID[:12], err)
		return result
	}

	// Find the port mapping
	if portMap, ok := inspectResp.NetworkSettings.Ports[nat.Port(containerPortStr)]; ok && len(portMap) > 0 {
		assignedHostPort = portMap[0].HostPort // Get the first assigned host port
		log.Printf("Container %s assigned host port %s for container port %s", containerID[:12], assignedHostPort, containerPortStr)
	} else {
		result.OverallError = fmt.Errorf("could not find assigned host port for %s in container %s", containerPortStr, containerID[:12])
		return result
	}
	if assignedHostPort == "" {
		result.OverallError = fmt.Errorf("assigned host port for %s is empty in container %s", containerPortStr, containerID[:12])
		return result
	}

	// --- 4. Check Logs ---
	logCheckCtx, logCheckCancel := context.WithCancel(ctx)
	defer logCheckCancel()
	logFoundChan := make(chan error, 1)
	go func() {
		defer func() { jobLogger.Printf("Log check routine finished.") }()
		logReader, err := cli.ContainerLogs(logCheckCtx, containerID, container.LogsOptions{ShowStdout: true, ShowStderr: true, Follow: true, Timestamps: false})
		if err != nil {
			jobLogger.Printf("Error getting container logs: %v", err)
			logFoundChan <- err
			return
		}
		defer logReader.Close()

		logTee := io.TeeReader(logReader, logBuf)
		scanner := bufio.NewScanner(logTee)
		jobLogger.Printf("Watching logs for '%s'...", logTarget)
		for scanner.Scan() {
			line := scanner.Text()

			if strings.Contains(line, logTarget) {
				jobLogger.Printf("Found target log line: %s", line)
				logFoundChan <- nil
				return
			}
		}
		scanErr := scanner.Err()
		if scanErr != nil && !errors.Is(scanErr, context.Canceled) {
			jobLogger.Printf("Error reading container logs: %v", scanErr)
			logFoundChan <- scanErr
		} else {
			logFoundChan <- fmt.Errorf("target log line not found before log stream ended")
		}
	}()

	select {
	case logErr := <-logFoundChan:
		if logErr == nil {
			result.LogCheck.Success = true
			jobLogger.Printf("Log check successful.")
		} else {
			result.LogCheck.Error = logErr
			jobLogger.Printf("Log check failed: %v", logErr)
		}
	case <-ctx.Done():
		result.LogCheck.Error = fmt.Errorf("timeout waiting for log line '%s': %w", logTarget, ctx.Err())
		jobLogger.Printf("Log check failed: %v", result.LogCheck.Error)
		// default: // non-blocking
	}

	if !result.LogCheck.Success {
		jobLogger.Printf("Skipping metric check because log check failed.")
		return result
	}

	// --- 5. Check Metrics ---
	time.Sleep(1 * time.Second)
	metricURL := fmt.Sprintf("http://localhost:%s/metrics", assignedHostPort)
	jobLogger.Printf("Checking metrics at %s for '%s' >= %.1f", metricURL, metricTarget, metricThreshold)

	req, err := http.NewRequestWithContext(ctx, "GET", metricURL, nil)
	if err != nil {
		result.MetricCheck.Error = fmt.Errorf("failed to create metrics request: %w", err)
		jobLogger.Printf("Metric check failed: %v", result.MetricCheck.Error)
		return result
	}
	respHttp, err := http.DefaultClient.Do(req)
	if err != nil {
		result.MetricCheck.Error = fmt.Errorf("failed to get metrics: %w", err)
		jobLogger.Printf("Metric check failed: %v", result.MetricCheck.Error)
		return result
	}
	defer respHttp.Body.Close()
	if respHttp.StatusCode != http.StatusOK {
		result.MetricCheck.Error = fmt.Errorf("metrics endpoint returned status %d", respHttp.StatusCode)
		jobLogger.Printf("Metric check failed: %v", result.MetricCheck.Error)
		return result
	}
	var parser expfmt.TextParser
	metricFamilies, err := parser.TextToMetricFamilies(respHttp.Body)
	if err != nil {
		result.MetricCheck.Error = fmt.Errorf("failed to parse metrics: %w", err)
		jobLogger.Printf("Metric check failed: %v", result.MetricCheck.Error)
		return result
	}

	// ... (metric finding logic remains the same) ...
	metricName := metricTarget
	labels := model.LabelSet{}
	if idx := strings.Index(metricTarget, "{"); idx != -1 && strings.HasSuffix(metricTarget, "}") {
		metricName = metricTarget[:idx]
		labelStr := metricTarget[idx+1 : len(metricTarget)-1]
		pairs := strings.Split(labelStr, ",")
		for _, pair := range pairs {
			parts := strings.SplitN(pair, "=", 2)
			if len(parts) == 2 {
				key := strings.TrimSpace(parts[0])
				val, err := strconv.Unquote(strings.TrimSpace(parts[1]))
				if err != nil {
					result.MetricCheck.Error = fmt.Errorf("failed to parse label value in '%s': %w", pair, err)
					return result
				}
				labels[model.LabelName(key)] = model.LabelValue(val)
			}
		}
	}
	mf, found := metricFamilies[metricName]
	if !found {
		result.MetricCheck.Error = fmt.Errorf("metric '%s' not found", metricName)
		return result
	}
	var metricValue float64 = -1
	for _, m := range mf.GetMetric() {
		match := true
		if len(labels) != len(m.GetLabel()) {
			match = false
		} else {
			for ln, lv := range labels {
				foundLabel := false
				for _, lp := range m.GetLabel() {
					if lp.GetName() == string(ln) && lp.GetValue() == string(lv) {
						foundLabel = true
						break
					}
				}
				if !foundLabel {
					match = false
					break
				}
			}
		}
		if match {
			if m.GetCounter() != nil {
				metricValue = m.GetCounter().GetValue()
			} else if m.GetGauge() != nil {
				metricValue = m.GetGauge().GetValue()
			}
			break
		}
	}
	if metricValue < 0 {
		result.MetricCheck.Error = fmt.Errorf("metric '%s' with specified labels not found", metricTarget)
		return result
	}
	if metricValue < metricThreshold {
		result.MetricCheck.Error = fmt.Errorf("metric '%s' value %.1f is below threshold %.1f", metricTarget, metricValue, metricThreshold)
		return result
	}

	// If we reach here, metric check passed
	result.MetricCheck.Success = true
	log.Printf("Metric check successful ('%s' value %.1f >= %.1f).", metricTarget, metricValue, metricThreshold)

	// --- 6. Return Detailed Result ---
	return result
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
