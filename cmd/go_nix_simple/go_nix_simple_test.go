package main

import (
	"flag"
	"os"
	"testing"
)

func TestVersionFlag(t *testing.T) {
	// Save original args and restore them after the test
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	// Set test args
	os.Args = []string{"go_nix_simple", "-v"}

	// Reset flag state
	flag.CommandLine = flag.NewFlagSet(os.Args[0], flag.ExitOnError)

	// Set version info for testing
	commit = "test-commit"
	date = "2024-01-01"
	version = "1.0.0"

	// Test version flag handling
	if !handleVersionFlag() {
		t.Error("handleVersionFlag should return true when -v flag is set")
	}
}
