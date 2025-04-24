#
# /go-nix-simple/Makefile.mk (Refactored)
#

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

# --- Build Information ---
VERSION := $(shell cat VERSION)
COMMIT := $(shell git describe --always)
DATE := $(shell date -u +"%Y-%m-%d-%H:%M")
LDFLAGS_STR := "-X main.commit=${COMMIT} -X main.date=${DATE} -X main.version=${VERSION}"

# --- Helper Variables ---
TIMESTAMP := date +"%Y-%m-%d %H:%M:%S.%3N"
MYPATH = $(shell pwd) # Context for Docker builds
REPO_PREFIX := randomizedcoder # Docker repo prefix

# --- Output Directory for Metrics ---
# Create a unique directory for this build run's metrics
BUILD_RUN_TIMESTAMP := $(shell date +"%Y%m%d_%H%M%S")
BUILD_OUTPUT_DIR := ./output/$(BUILD_RUN_TIMESTAMP)

# --- Generator Tool ---
GENERATOR_DIR := cmd/generate-containerfiles
GENERATOR_BIN := $(GENERATOR_DIR)/generate-containerfiles
CONTAINERFILE_DIR := build/containers/go_nix_simple_refactor

# --- Build Command Macro (Used for Nix builds now) ---
define time_command
@_start_time_ns=$$(date +%s%N); \
echo "[$($(TIMESTAMP))] Starting $(1)..."; \
$(2); \
_end_time_ns=$$(date +%s%N); \
_duration_ms=$$(( (_end_time_ns - _start_time_ns) / 1000000 )); \
echo "[$($(TIMESTAMP))] Finished $(1). Duration: $$_duration_ms ms."
endef

# --- Nix Flake Outputs (Base names for easier reference) ---
NIX_IMAGE_PREFIX := image-nix
NIX_BINARY_PREFIX := binary-nix
NIX_BUILDERS := buildgomodule gomod2nix
NIX_BASES := distroless scratch
NIX_PACKERS := noupx upx

# --- Docker Build Variants (Base names for easier reference) ---
DOCKER_IMAGE_PREFIX := docker-go-nix-simple # Used in image tags
DOCKER_BASES := distroless scratch
DOCKER_CACHES := default athens http none
DOCKER_PACKERS := noupx upx

# --- Generate Lists of Targets ---
# Nix Image Build Targets (e.g., build-nix-image-distroless-buildgomodule-noupx)
NIX_IMAGE_TARGETS := $(foreach base,$(NIX_BASES), \
                       $(foreach builder,$(NIX_BUILDERS), \
                         $(foreach packer,$(NIX_PACKERS), \
                           build-$(NIX_IMAGE_PREFIX)-$(base)-$(builder)-$(packer))))

# Docker Image Build Targets (e.g., build-docker-image-distroless-default-noupx)
DOCKER_IMAGE_TARGETS := $(foreach base,$(DOCKER_BASES), \
                          $(foreach cache,$(DOCKER_CACHES), \
                            $(foreach packer,$(DOCKER_PACKERS), \
                              build-docker-image-$(base)-$(cache)-$(packer))))

# Filter out invalid Docker combinations (e.g., non-default cache with upx) - Adjust as needed
INVALID_DOCKER_COMBOS := $(filter %-athens-upx, $(DOCKER_IMAGE_TARGETS)) \
                         $(filter %-http-upx, $(DOCKER_IMAGE_TARGETS)) \
                         $(filter %-none-upx, $(DOCKER_IMAGE_TARGETS)) \
                         $(filter %-scratch-athens-upx, $(DOCKER_IMAGE_TARGETS)) # Example: Maybe UPX+Scratch+Athens is invalid
VALID_DOCKER_IMAGE_TARGETS := $(filter-out $(INVALID_DOCKER_COMBOS), $(DOCKER_IMAGE_TARGETS))


# --- Phony Targets ---
.PHONY: all all-nix all-docker \
	prepare-output-dir generate-containerfiles \
	load-nix-result \
	summary \
	$(NIX_IMAGE_TARGETS) \
	$(VALID_DOCKER_IMAGE_TARGETS) \
	deploy_athens down_athens run_athens ls dive run curl prepare clear_go_mod_cache go_clean \
	flake_metadata flake_show \
	install_bazel gazelle_init gazelle_run bazel_build bazel_run

# --- Aggregate Targets ---
# Ensure output dir is prepared before running builds
all: prepare-output-dir all-nix all-docker summary
all-nix: prepare-output-dir $(NIX_IMAGE_TARGETS) # Add load targets if desired, e.g. $(NIX_IMAGE_TARGETS:%=load-%)
all-docker: prepare-output-dir $(VALID_DOCKER_IMAGE_TARGETS)

# --- Prepare Output Directory ---
prepare-output-dir:
	@mkdir -p $(BUILD_OUTPUT_DIR)
	@echo "Build output directory: $(BUILD_OUTPUT_DIR)"

#--------------------------
# Containerfile Generation
# Depends on output dir being ready (though not strictly necessary for this target)
generate-containerfiles: prepare-output-dir
	@echo "[$($(TIMESTAMP))] Building Containerfile generator..."
	@$(MAKE) -C $(GENERATOR_DIR) build
	@echo "[$($(TIMESTAMP))] Running Containerfile generator..."
	$(call time_command, $@, $(GENERATOR_BIN) --output $(CONTAINERFILE_DIR))

#--------------------------
# Nix Build Targets

# Generic rule for building Nix images
# Depends on output dir being ready
# TODO: Modify this rule to capture metrics and write to BUILD_OUTPUT_DIR
$(NIX_IMAGE_TARGETS): build-$(NIX_IMAGE_PREFIX)-% : prepare-output-dir
	$(eval FLAKE_OUTPUT_KEY := $(NIX_IMAGE_PREFIX)-$(*))
	$(call time_command, $@, nix build .#$(FLAKE_OUTPUT_KEY))
	# Add steps here later: record time, load image, inspect, write metric file

# Generic rule for loading Nix results (depends on build)
# Usage: make load-nix-image-distroless-buildgomodule-noupx
load-nix-%: build-nix-% load-nix-result

# Helper target to load the last built result
load-nix-result: result
	$(call time_command, $@, docker load < result)

#--------------------------
# Docker Build Targets

# Generic rule for building Docker images (calls script)
# Depends on output dir being ready
$(VALID_DOCKER_IMAGE_TARGETS): build-docker-image-% : prepare-output-dir generate-containerfiles
	./scripts/build_docker_image.sh \
		"$(strip $(word 1,$(subst -, ,$(patsubst build-docker-image-%,%,$@))))" \
		"$(strip $(word 2,$(subst -, ,$(patsubst build-docker-image-%,%,$@))))" \
		"$(strip $(word 3,$(subst -, ,$(patsubst build-docker-image-%,%,$@))))" \
		"$(strip $(VERSION))" \
		"$(strip $(COMMIT))" \
		"$(strip $(DATE))" \
		"$(strip $(REPO_PREFIX))" \
		"$(strip $(DOCKER_IMAGE_PREFIX))" \
		"$(strip $(CONTAINERFILE_DIR))" \
		"$(strip $(MYPATH))" \
		"$(strip $(BUILD_OUTPUT_DIR))"

#--------------------------
# Summary Target

# Define all expected final image tags
# TODO: Update this list if Nix image tags change after loading
ALL_NIX_IMAGE_TAGS := $(foreach target,$(NIX_IMAGE_TARGETS),$(REPO_PREFIX)/$(subst build-,,$(target)):$(VERSION))
ALL_DOCKER_IMAGE_TAGS := $(foreach target,$(VALID_DOCKER_IMAGE_TARGETS),$(REPO_PREFIX)/$(subst build-docker-image-,$(DOCKER_IMAGE_PREFIX)-,$(target)):$(VERSION))
ALL_IMAGE_TAGS := $(ALL_NIX_IMAGE_TAGS) $(ALL_DOCKER_IMAGE_TAGS)

summary:
	./scripts/generate_summary.sh

#--------------------------
# Other Utility Targets (Keep relevant ones)

ls:
	@echo "--- Nix Images (Loaded) ---"
	@docker image ls '$(REPO_PREFIX)/nix-go-nix-simple*' || true
	@echo "--- Docker Images ---"
	@docker image ls '$(REPO_PREFIX)/docker-go-nix-simple*' || true

#--------------------------
# docker compose athens

deploy_athens:
	@echo "================================"
	@echo "Make deploy_athens"
	docker compose \
		--file build/containers/athens/docker-compose-athens.yml \
		up -d --remove-orphans

down_athens:
	@echo "================================"
	@echo "Make down_athens"
	docker compose \
		--file build/containers/athens/docker-compose-athens.yml \
		down

athens_traffic:
	sudo tcpdump -ni any port 8888

#--------------------------
# nix build athens docker container

nix_build_athens:
	nix build .#athens-nix-image
	docker load < result

run_athens:
	docker run -d -p 8888:8888 randomizedcoder/athens-nix:latest

#--------------------------
# inspect (Update these if needed)

# dive:
# 	dive <some_new_image_tag>

# dive-distroless:
# 	dive <some_new_distroless_tag>

# run:
# 	docker run -d -p 9108:9108 <some_new_image_tag>

# run-distroless:
# 	docker run -d -p 9108:9108 <some_new_distroless_tag>

curl:
	curl http://localhost:9108/metrics

prepare:
	nix-shell -p nix-prefetch-docker --run "nix-prefetch-docker --image-name gcr.io/distroless/static-debian12 --image-tag latest"

#--------------------------
# clear go mod cache

clear_go_mod_cache:
	sudo rm -rf /home/das/go/pkg/mod/

go_clean:
	go clean -modcache

#--------------------------
# flake commands

flake_metadata:
	nix flake metadata

flake_show:
	nix flake show

#------------------------
# bazel
install_bazel:
	go install github.com/bazelbuild/bazel-gazelle/cmd/gazelle@latest

gazelle_init:
	bazel run //:gazelle -- update-repos -from_file=go.mod

gazelle_run:
	bazel run //:gazelle

bazel_build:
	bazel build //cmd/go_nix_simple:go_nix_simple

bazel_run:
	bazel run //cmd/go_nix_simple:go_nix_simple

# end
