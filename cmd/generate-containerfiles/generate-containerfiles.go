package main

import (
	"bytes"
	"flag" // Import flag package
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"text/template"
)

// Variables set by ldflags
var (
	commit  string
	date    string
	version string
)

type Config struct {
	BaseImage      string
	CachingMode    string
	UseUPX         bool
	GoVersion      string
	AthensProxyURL string
	HttpProxyURL   string
	GoBuildCommand string
	// Add fields for ARGs if needed in template
	MYPATH  string
	COMMIT  string
	DATE    string
	VERSION string
	// etc.
}

func main() {
	// --- Flags ---
	tmplPath := flag.String("template", "build/containers/go_nix_simple_refactor/Containerfile.tmpl", "Path to the Containerfile template")
	outputPath := flag.String("output", "build/containers/go_nix_simple_refactor", "Directory to save generated Containerfiles")
	athensURL := flag.String("athens-url", "http://hp4.home:8888", "Athens proxy URL")
	httpProxyURL := flag.String("http-proxy-url", "http://hp4.home:3128", "HTTP proxy URL")
	goVersion := flag.String("go-version", "1.24.2", "Go version for builder image")
	// Add flags for MYPATH, COMMIT, DATE, VERSION if they need to be passed to the template
	// Example:
	// mypathArg := flag.String("mypath", ".", "Value for MYPATH ARG")

	flag.Parse()

	log.Printf("Generator version: %s, commit: %s, built: %s", version, commit, date)

	// --- Template Parsing ---
	tmpl, err := template.ParseFiles(*tmplPath)
	if err != nil {
		log.Fatalf("Error parsing template %s: %v", *tmplPath, err)
	}

	// --- Define Options for Combinations ---
	baseImages := []string{"gcr.io/distroless/static-debian12", "scratch"}
	cachingModes := []string{"default", "athens", "http", "none"}
	useUPXOptions := []bool{false, true} // Options for UPX usage

	var configs []Config
	for _, base := range baseImages {
		for _, cache := range cachingModes {
			for _, upx := range useUPXOptions {

				// --- Skip invalid or undesired combinations ---
				// Example: UPX might not make sense with certain cache modes,
				// or you might only want UPX for distroless. Adjust as needed.
				if upx && base == "scratch" {
					// Example: Let's say we only want UPX for distroless for now
					// log.Printf("Skipping combination: Base=%s, Cache=%s, UPX=%t", base, cache, upx)
					// continue
				}
				if cache != "default" && upx {
					// Example: Let's say UPX only applies to the 'default' cache build for simplicity
					// log.Printf("Skipping combination: Base=%s, Cache=%s, UPX=%t", base, cache, upx)
					// continue
				}
				// Add any other skipping logic here if necessary

				// --- Create Config for this combination ---
				cfg := Config{
					BaseImage:      base,
					CachingMode:    cache,
					UseUPX:         upx,
					GoVersion:      *goVersion,
					AthensProxyURL: *athensURL, // Set URLs regardless, template/build command logic uses them conditionally
					HttpProxyURL:   *httpProxyURL,
					// Add ARGs if needed: VERSION: version, COMMIT: commit, DATE: date, MYPATH: *mypathArg ...
				}
				configs = append(configs, cfg)
			}
		}
	}
	log.Printf("Generated %d configuration combinations.", len(configs))

	// --- Generation Loop ---
	for i := range configs { // Use index to modify cfg in place
		cfg := &configs[i] // Get pointer to modify original config

		// --- Determine Go Build Command ---
		var buildCmdBuilder strings.Builder
		buildCmdBuilder.WriteString("RUN ") // Start the RUN command
		switch cfg.CachingMode {
		case "default":
			buildCmdBuilder.WriteString("--mount=type=cache,target=/go/pkg/mod \\\n    --mount=type=cache,target=/root/.cache/go-build \\\n    ")
		case "athens":
			buildCmdBuilder.WriteString(fmt.Sprintf("GOPROXY=%s,https://proxy.golang.org,direct \\\n    ", cfg.AthensProxyURL))
		case "http":
			buildCmdBuilder.WriteString(fmt.Sprintf("HTTP_PROXY=%s \\\n    HTTPS_PROXY=%s \\\n    ", cfg.HttpProxyURL, cfg.HttpProxyURL))
		case "none":
			// No extra flags needed for the RUN line itself
		}
		// Append the common part of the go build command
		buildCmdBuilder.WriteString("CGO_ENABLED=0 go build \\\n")
		buildCmdBuilder.WriteString("    -trimpath \\\n")
		buildCmdBuilder.WriteString("    -tags=netgo,osusergo \\\n")
		buildCmdBuilder.WriteString("    -ldflags=\"-s -w\" \\\n")
		buildCmdBuilder.WriteString("    -o /go/bin/go_nix_simple \\\n")
		buildCmdBuilder.WriteString("    ./cmd/go_nix_simple/go_nix_simple.go")
		cfg.GoBuildCommand = buildCmdBuilder.String()
		// --- End Go Build Command Determination ---

		// --- Generate Filename ---
		// ***** ADD THESE LINES BACK *****
		baseName := "distroless"
		if cfg.BaseImage == "scratch" {
			baseName = "scratch"
		}
		packerName := "noupx"
		if cfg.UseUPX {
			packerName = "upx"
		}
		// ********************************
		filename := fmt.Sprintf("Containerfile.%s.%s.%s", baseName, cfg.CachingMode, packerName)
		fullPath := filepath.Join(*outputPath, filename) // Use flag value

		// --- Execute Template ---
		var buf bytes.Buffer
		err = tmpl.Execute(&buf, cfg) // Pass pointer to config
		if err != nil {
			log.Printf("Error executing template for %s: %v", filename, err)
			continue // Skip to next config on template error
		}

		// --- Write File ---
		err = os.WriteFile(fullPath, buf.Bytes(), 0644)
		if err != nil {
			log.Printf("Error writing file %s: %v", fullPath, err)
			continue // Skip to next config on write error
		}
		log.Printf("Generated: %s", fullPath)
	}
}
