package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
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
)

type ValidationResult struct {
	ImageTag string
	Success  bool
	Error    error
	Duration time.Duration
}

func main() {

	imageTagsRaw := flag.String("images", "", "Comma-separated list of Docker image tags to validate (required)")
	parallelism := flag.Int("parallel", defaultParallelism, "Number of concurrent validation tests to run")
	timeout := flag.Duration("timeout", defaultTimeout, "Timeout for each individual image validation")
	logTarget := flag.String("log-target", defaultLogTarget, "Log line prefix to wait for")
	metricTarget := flag.String("metric-target", defaultMetricTarget, "Prometheus metric name (with labels) to check")
	metricThreshold := flag.Float64("metric-threshold", defaultMetricThreshold, "Minimum value for the target metric")

	flag.Parse()

	if *imageTagsRaw == "" {
		log.Fatal("Error: -images flag is required")
	}
	imageTags := strings.Split(*imageTagsRaw, ",")
	if len(imageTags) == 0 {
		log.Fatal("Error: No image tags provided")
	}

	log.Printf("Starting validation for %d image(s) with parallelism %d and timeout %v", len(imageTags), *parallelism, *timeout)

	ctx := context.Background()

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
		go worker(ctx, w, jobs, results, &wg, *timeout, *logTarget, *metricTarget, *metricThreshold)
	}

	// --- Send Jobs ---
	for _, tag := range imageTags {
		trimmedTag := strings.TrimSpace(tag)
		if trimmedTag != "" {
			jobs <- trimmedTag
		}
	}
	close(jobs) // Signal that no more jobs will be sent

	// --- Wait for Workers and Collect Results ---
	wg.Wait()      // Wait for all workers to finish processing
	close(results) // Close results channel once all workers are done

	// --- Report Results ---
	log.Println("--- Validation Summary ---")
	allSuccess := true
	for res := range results {
		status := "SUCCESS"
		errMsg := ""
		if !res.Success {
			status = "FAILED"
			allSuccess = false
			if res.Error != nil {
				errMsg = fmt.Sprintf(" Error: %v", res.Error)
			}
		}
		log.Printf("[%s] %s (Duration: %v)%s", status, res.ImageTag, res.Duration, errMsg)
	}
	log.Println("--------------------------")

	if !allSuccess {
		log.Println("One or more validations failed.")
		os.Exit(1)
	}
	log.Println("All validations passed.")
}

// worker executes validation jobs received from the jobs channel.
func worker(ctxIn context.Context,
	id int, jobs <-chan string,
	results chan<- ValidationResult,
	wg *sync.WaitGroup,
	timeout time.Duration,
	logTarget, metricTarget string,
	metricThreshold float64) {

	defer wg.Done()
	log.Printf("Worker %d started", id)
	for imageTag := range jobs {
		log.Printf("Worker %d: Validating image %s", id, imageTag)
		startTime := time.Now()
		ctx, cancel := context.WithTimeout(ctxIn, timeout)
		success, err := validateImage(ctx, imageTag, logTarget, metricTarget, metricThreshold)
		cancel() // Release context resources promptly
		duration := time.Since(startTime)

		results <- ValidationResult{
			ImageTag: imageTag,
			Success:  success,
			Error:    err,
			Duration: duration,
		}
		log.Printf("Worker %d: Finished validating %s (Success: %t, Duration: %v)", id, imageTag, success, duration)
	}
	log.Printf("Worker %d finished", id)
}

// validateImage performs the actual validation steps for a single image.
func validateImage(ctx context.Context, imageTag, logTarget, metricTarget string, metricThreshold float64) (bool, error) {

	// --- 1. Create Docker Client ---
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return false, fmt.Errorf("failed to create docker client: %w", err)
	}
	defer cli.Close()

	// --- 2. Pull Image (Optional but good practice) ---
	// Ensures the image exists locally before trying to run
	log.Printf("Pulling image %s (best effort)...", imageTag)
	pullCtx, pullCancel := context.WithTimeout(ctx, 2*time.Minute) // Separate timeout for pull
	_, err = cli.ImagePull(pullCtx, imageTag, image.PullOptions{})
	pullCancel()
	if err != nil {
		log.Printf("Warning: Failed to pull image %s (will try to run anyway): %v", imageTag, err)
		// Don't necessarily fail here, maybe it exists locally
	}

	// --- 3. Create and Start Container ---
	// TODO: Consider using host network mode for easier port access, or handle port mapping.
	// For now, assuming host port is same as container port (requires mapping or host mode)
	containerPortStr := "9108/tcp"
	hostPortStr := "9108"

	// Use nat.PortSet for ExposedPorts
	exposedPortsSet := nat.PortSet{nat.Port(containerPortStr): {}}

	// Use nat.PortBinding for PortBindings
	portBindingsMap := nat.PortMap{
		nat.Port(containerPortStr): []nat.PortBinding{
			{
				HostIP:   "0.0.0.0",
				HostPort: hostPortStr,
			},
		},
	}

	resp, err := cli.ContainerCreate(ctx, &container.Config{
		Image:        imageTag,
		ExposedPorts: exposedPortsSet, // Use nat.PortSet
	}, &container.HostConfig{
		PortBindings: portBindingsMap, // Use nat.PortMap and nat.PortBinding
		AutoRemove:   true,
		// NetworkMode: "host",
	}, nil, nil, "")
	if err != nil {
		return false, fmt.Errorf("failed to create container: %w", err)
	}
	containerID := resp.ID
	log.Printf("Created container %s", containerID[:12])

	// Defer container stop and removal (AutoRemove should handle removal)
	defer func() {
		log.Printf("Stopping container %s...", containerID[:12])
		// Use a separate background context for cleanup in case the main context timed out
		stopCtx, stopCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer stopCancel()
		// Use ContainerStop with nil timeout for default behavior
		if err := cli.ContainerStop(stopCtx, containerID, container.StopOptions{}); err != nil {
			// Log error but don't fail validation just because stop failed
			log.Printf("Warning: Failed to stop container %s: %v", containerID[:12], err)
		} else {
			log.Printf("Stopped container %s", containerID[:12])
		}
		// AutoRemove should handle removal, but ContainerRemove can be added as fallback if needed
	}()

	if err := cli.ContainerStart(ctx, containerID, container.StartOptions{}); err != nil {
		return false, fmt.Errorf("failed to start container: %w", err)
	}
	log.Printf("Started container %s", containerID[:12])

	// --- 4. Check Logs ---
	logCheckCtx, logCheckCancel := context.WithCancel(ctx) // Separate cancel for log routine
	defer logCheckCancel()
	logFound := make(chan bool, 1)
	go func() {
		defer func() { log.Printf("Log check routine finished for %s", containerID[:12]) }()
		logReader, err := cli.ContainerLogs(logCheckCtx, containerID, container.LogsOptions{ShowStdout: true, ShowStderr: true, Follow: true, Timestamps: false})
		if err != nil {
			log.Printf("Error getting container logs: %v", err)
			logFound <- false // Signal failure
			return
		}
		defer logReader.Close()

		scanner := bufio.NewScanner(logReader)
		log.Printf("Watching logs for '%s'...", logTarget)
		for scanner.Scan() {
			line := scanner.Text()
			// Simple prefix check, adjust if full line match or regex is needed
			if strings.Contains(line, logTarget) {
				log.Printf("Found target log line: %s", line)
				logFound <- true // Signal success
				return
			}
			// Optional: Print logs for debugging
			// log.Printf("Container Log: %s", line)
		}
		if err := scanner.Err(); err != nil && !errors.Is(err, context.Canceled) {
			log.Printf("Error reading container logs: %v", err)
		}
		// If loop finishes without finding the target (e.g., context cancelled)
		logFound <- false
	}()

	// Wait for log check result or timeout
	select {
	case found := <-logFound:
		if !found {
			return false, fmt.Errorf("target log line '%s' not found", logTarget)
		}
		log.Printf("Log check successful.")
	case <-ctx.Done():
		return false, fmt.Errorf("timeout waiting for log line '%s': %w", logTarget, ctx.Err())
	}

	// --- 5. Check Metrics ---
	// Add a small delay to ensure metrics are likely updated after the log line appears
	time.Sleep(1 * time.Second)

	metricURL := fmt.Sprintf("http://localhost:%s/metrics", hostPortStr)
	log.Printf("Checking metrics at %s for '%s' >= %.1f", metricURL, metricTarget, metricThreshold)

	req, err := http.NewRequestWithContext(ctx, "GET", metricURL, nil)
	if err != nil {
		return false, fmt.Errorf("failed to create metrics request: %w", err)
	}

	respHttp, err := http.DefaultClient.Do(req)
	if err != nil {
		return false, fmt.Errorf("failed to get metrics: %w", err)
	}
	defer respHttp.Body.Close()

	if respHttp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("metrics endpoint returned status %d", respHttp.StatusCode)
	}

	// Parse Prometheus exposition format
	// https://pkg.go.dev/github.com/prometheus/common/expfmt
	var parser expfmt.TextParser
	metricFamilies, err := parser.TextToMetricFamilies(respHttp.Body)
	if err != nil {
		return false, fmt.Errorf("failed to parse metrics: %w", err)
	}

	// Find the target metric
	// This parsing is basic, might need refinement based on exact metricTarget format
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
				// Need to unquote the label value
				val, err := strconv.Unquote(strings.TrimSpace(parts[1]))
				if err != nil {
					return false, fmt.Errorf("failed to parse label value in '%s': %w", pair, err)
				}
				labels[model.LabelName(key)] = model.LabelValue(val)
			}
		}
	}

	mf, found := metricFamilies[metricName]
	if !found {
		return false, fmt.Errorf("metric '%s' not found", metricName)
	}

	// Find the specific metric instance matching the labels
	var metricValue float64 = -1 // Default to invalid value
	for _, m := range mf.GetMetric() {
		match := true
		if len(labels) != len(m.GetLabel()) {
			match = false // Quick check: different number of labels
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
			// Found the metric, get its value (assuming it's a Counter or Gauge)
			if m.GetCounter() != nil {
				metricValue = m.GetCounter().GetValue()
			} else if m.GetGauge() != nil {
				metricValue = m.GetGauge().GetValue()
			} // Add Untyped if needed
			break
		}
	}

	if metricValue < 0 {
		return false, fmt.Errorf("metric '%s' with specified labels not found", metricTarget)
	}

	// Check threshold
	if metricValue < metricThreshold {
		return false, fmt.Errorf("metric '%s' value %.1f is below threshold %.1f", metricTarget, metricValue, metricThreshold)
	}

	log.Printf("Metric check successful ('%s' value %.1f >= %.1f).", metricTarget, metricValue, metricThreshold)

	// --- 6. Success ---
	return true, nil
}
