#
# /go-nix-simple/Makefile
#

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

# --- Help Target ---
.PHONY: help
help: ## Display this help message
	@echo "Available targets:"
	@echo ""
	@echo "Build Targets:"
	@echo "  all              - Build all Nix and Docker images"
	@echo "  all-nix          - Build all Nix images"
	@echo "  all-docker       - Build all Docker images"
	@echo "  all-validate     - Build and validate all images"
	@echo ""
	@echo "Bazel Targets:"
	@echo "  bazel-setup      - Install Bazel Gazelle"
	@echo "  bazel-update     - Update Bazel dependencies"
	@echo "  bazel-clean      - Clean Bazel build artifacts"
	@echo "  bazel-build-all  - Build all Bazel image variants"
	@echo "  bazel-build-all-remote - Build all variants with remote execution"
	@echo "  bazel-build-distroless - Build distroless image variant"
	@echo "  bazel-build-scratch - Build scratch image variant"
	@echo "  bazel_build_remote - Build binary with remote execution"
	@echo "  bazel_build_oci_distroless - Build OCI distroless image"
	@echo "  bazel_build_oci_scratch - Build OCI scratch image"
	@echo "  bazel-test-race  - Run Go race tests locally"
	@echo "  bazel-test-race-remote - Run Go race tests with remote execution"
	@echo ""
	@echo "Validation Targets:"
	@echo "  validate-all     - Validate all images"
	@echo "  validate-all-nix - Validate all Nix images"
	@echo "  validate-all-docker - Validate all Docker images"
	@echo ""
	@echo "Push Targets:"
	@echo "  push-all         - Push all images"
	@echo "  push-all-nix     - Push all Nix images"
	@echo "  push-all-docker  - Push all Docker images"
	@echo ""
	@echo "Utility Targets:"
	@echo "  prepare-output-dir - Create output directory for builds"
	@echo "  generate-containerfiles - Generate Docker containerfiles"
	@echo "  build-validator  - Build the image validation tool"
	@echo "  run-validator    - Run the image validation tool"
	@echo "  load-nix-result  - Load Nix build result into Docker"
	@echo ""
	@echo "For more detailed information about specific targets, please refer to the Makefile."

# --- Build Information ---
VERSION := $(shell cat VERSION)
COMMIT := $(shell git describe --always)
DATE := $(shell date -u +"%Y-%m-%d-%H:%M")
LDFLAGS_STR := "-X main.commit=${COMMIT} -X main.date=${DATE} -X main.version=${VERSION}"

# --- Helper Variables ---
TIMESTAMP := date +"%Y-%m-%d %H:%M:%S.%3N"
MYPATH = $(shell pwd)
REPO_PREFIX := randomizedcoder

# --- Output Directory for Metrics ---
BUILD_RUN_TIMESTAMP := $(shell date +"%Y%m%d_%H%M%S")
BUILD_OUTPUT_DIR := ./output/$(BUILD_RUN_TIMESTAMP)

VALIDATION_OUTPUT_DIR := $(BUILD_OUTPUT_DIR)/validation

# --- Generator Tool ---
GENERATOR_DIR := cmd/generate-containerfiles
GENERATOR_BIN := $(GENERATOR_DIR)/generate-containerfiles
CONTAINERFILE_DIR := build/containers/go_nix_simple_refactor

# --- Validator Tool ---
VALIDATOR_DIR := cmd/validate-image
VALIDATOR_BIN := $(VALIDATOR_DIR)/validate-image

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
DOCKER_BUILD_PREFIX := build_docker
DOCKER_IMAGE_PREFIX := docker-go-nix-simple
DOCKER_BASES := distroless scratch
DOCKER_CACHES := docker athens http none
DOCKER_PACKERS := noupx upx

# --- Generate Lists of Targets ---
NIX_IMAGE_TARGETS := $(foreach base,$(NIX_BASES), \
                       $(foreach builder,$(NIX_BUILDERS), \
                         $(foreach packer,$(NIX_PACKERS), \
                           build-$(NIX_IMAGE_PREFIX)-$(base)-$(builder)-$(packer))))

DOCKER_IMAGE_TARGETS := $(foreach base,$(DOCKER_BASES), \
                          $(foreach cache,$(DOCKER_CACHES), \
                            $(foreach packer,$(DOCKER_PACKERS), \
                              $(DOCKER_BUILD_PREFIX)-$(base)-$(cache)-$(packer))))

# No filters yet
INVALID_DOCKER_COMBOS := $(filter %-foo-bar, $(DOCKER_IMAGE_TARGETS))
# INVALID_DOCKER_COMBOS := $(filter %-athens-upx, $(DOCKER_IMAGE_TARGETS)) \
#                          $(filter %-http-upx, $(DOCKER_IMAGE_TARGETS)) \
#                          $(filter %-none-upx, $(DOCKER_IMAGE_TARGETS)) \
#                          $(filter %-scratch-athens-upx, $(DOCKER_IMAGE_TARGETS))

VALID_DOCKER_IMAGE_TARGETS := $(filter-out $(INVALID_DOCKER_COMBOS), $(DOCKER_IMAGE_TARGETS))

VALIDATE_NIX_TARGETS := $(NIX_IMAGE_TARGETS:build-%=validate-%)
VALIDATE_DOCKER_TARGETS := $(VALID_DOCKER_IMAGE_TARGETS:$(DOCKER_BUILD_PREFIX)-%=validate_docker-%)
ALL_VALIDATE_TARGETS := $(VALIDATE_NIX_TARGETS) $(VALIDATE_DOCKER_TARGETS)

PUSH_NIX_TARGETS := $(NIX_IMAGE_TARGETS:build-%=push-%)
PUSH_DOCKER_TARGETS := $(VALID_DOCKER_IMAGE_TARGETS:$(DOCKER_BUILD_PREFIX)-%=push_docker-%)
ALL_PUSH_TARGETS := $(PUSH_NIX_TARGETS) $(PUSH_DOCKER_TARGETS)

#--------------------------
# Bazel Configuration
#--------------------------
BAZEL_REPO := docker.io/randomizedcoder
BAZEL_VERSION := latest
BAZEL_PLATFORMS := //platforms:linux_amd64
#BAZEL_PLATFORMS := //platforms:linux_amd64 //platforms:linux_arm64

# Generate all combinations
BAZEL_TARGETS := $(foreach img,$(BAZEL_IMAGES),$(foreach plat,$(BAZEL_PLATFORMS),image_bazel_$(img)_$(plat)))

# --- Phony Targets ---
.PHONY: all all-nix all-docker all-bazel \
	prepare-output-dir generate-containerfiles \
	build-validator \
	validate-all validate-all-nix validate-all-docker \
	load-nix-result \
	summary \
	$(NIX_IMAGE_TARGETS) \
	$(VALID_DOCKER_IMAGE_TARGETS) \
	$(BAZEL_TARGETS) \
	$(ALL_VALIDATE_TARGETS) \
	$(ALL_PUSH_TARGETS) \
	deploy_athens down_athens run_athens ls dive run curl prepare clear_go_mod_cache go_clean \
	flake_metadata flake_show \
	install_bazel gazelle_init gazelle_run bazel_build bazel_run \
	bazel_build_a_tarball bazel_go \
	bazel-setup bazel-update bazel-clean \
	bazel-build-all bazel-test-race bazel-test-race-remote

# --- Aggregate Targets ---
all: prepare-output-dir all-nix all-docker summary
all-validate: prepare-output-dir all-nix all-docker validate-all summary validation-summary
all-nix: prepare-output-dir $(NIX_IMAGE_TARGETS)
all-docker: prepare-output-dir generate-containerfiles $(VALID_DOCKER_IMAGE_TARGETS)

#------------------------
# Bazel Setup & Maintenance
#------------------------
.PHONY: bazel-setup bazel-update bazel-clean

bazel-setup:
	go install github.com/bazelbuild/bazel-gazelle/cmd/gazelle@latest

bazel-update:
	bazel run //:gazelle -- update-repos -from_file=go.mod
	bazel run //:gazelle

bazel-clean:
	bazel clean --expunge

#------------------------
# Bazel Build Targets
#------------------------
.PHONY: bazel-build-all bazel-build-distroless bazel-build-scratch bazel-test-race bazel-test-race-remote

# Build all variants
bazel-build-all: bazel-build-distroless bazel-build-scratch

# Go race test targets
bazel-test-race:
	bazel test --@rules_go//go/config:race //cmd/go_nix_simple:go_nix_simple_race_test

bazel-test-race-remote:
	bazel test --config=hp4 --@rules_go//go/config:race //cmd/go_nix_simple:go_nix_simple_race_test

# Remote build target for all variants
bazel-build-all-remote:
	for platform in $(BAZEL_PLATFORMS); do \
		bazel build --config=hp4 \
			--platforms=$$platform \
			--verbose_failures \
			--execution_log_json_file=bazel-execution.json \
			--show_timestamps \
			//cmd/go_nix_simple:image_bazel_distroless_tarball \
			//cmd/go_nix_simple:image_bazel_scratch_tarball \
			--define REPO_PREFIX=$(BAZEL_REPO) \
			--define VERSION=$(BAZEL_VERSION); \
	done

# Distroless image variants
bazel-build-distroless:
	for platform in $(BAZEL_PLATFORMS); do \
		bazel build --platforms=$$platform \
			//cmd/go_nix_simple:image_bazel_distroless_tarball \
			--define REPO_PREFIX=$(BAZEL_REPO) \
			--define VERSION=$(BAZEL_VERSION); \
	done

# Scratch image variants
bazel-build-scratch:
	for platform in $(BAZEL_PLATFORMS); do \
		bazel build --platforms=$$platform \
			//cmd/go_nix_simple:image_bazel_scratch_tarball \
			--define REPO_PREFIX=$(BAZEL_REPO) \
			--define VERSION=$(BAZEL_VERSION); \
	done

# --- Add Aggregate Push Targets ---
push-all: $(ALL_PUSH_TARGETS)
	@echo "[$($(TIMESTAMP))] Finished pushing all images."

push-all-nix: $(PUSH_NIX_TARGETS)
	@echo "[$($(TIMESTAMP))] Finished pushing all Nix images."

push-all-docker: $(PUSH_DOCKER_TARGETS)
	@echo "[$($(TIMESTAMP))] Finished pushing all Docker images."

validate-all: $(ALL_VALIDATE_TARGETS)
validate-all-nix: $(VALIDATE_NIX_TARGETS)
validate-all-docker: $(VALIDATE_DOCKER_TARGETS)

# e.g. make validate-all -j1


# --- Prepare Output Directory ---
prepare-output-dir:
	@mkdir -p $(BUILD_OUTPUT_DIR)
	@echo "Build output directory: $(BUILD_OUTPUT_DIR)"

#--------------------------
# Containerfile Generation
generate-containerfiles:
	@echo "[$($(TIMESTAMP))] Building Containerfile generator..."
	@$(MAKE) -C $(GENERATOR_DIR) build
	@echo "[$($(TIMESTAMP))] Running Containerfile generator..."
	$(call time_command, $@, $(GENERATOR_BIN) --output $(CONTAINERFILE_DIR))

#--------------------------
# Validator Build Target
build-validator:
	@echo "[$($(TIMESTAMP))] Building validator tool..."
	@$(MAKE) -C $(VALIDATOR_DIR) build
	@echo "[$($(TIMESTAMP))] Finished building validator tool."

run-valdiator:
	./cmd/validate-image/validate-image --parallel 8

#--------------------------
# Nix Build Targets

$(NIX_IMAGE_TARGETS): build-$(NIX_IMAGE_PREFIX)-% : prepare-output-dir
	./scripts/build_nix_image.sh \
		"$(strip $@)" \
		"$(strip $(NIX_IMAGE_PREFIX)-$(*))" \
		"$(strip $(REPO_PREFIX)/$(subst image-nix-,nix-go-nix-simple-,$(NIX_IMAGE_PREFIX)-$(*)):$(VERSION))" \
		"$(strip $(BUILD_OUTPUT_DIR))"


load-nix-result: result
	$(call time_command, $@, docker load < result)

#--------------------------
# Docker Build Targets

$(VALID_DOCKER_IMAGE_TARGETS): $(DOCKER_BUILD_PREFIX)-% : prepare-output-dir
	./scripts/build_docker_image.sh \
		"$(strip $(word 1,$(subst -, ,$(patsubst $(DOCKER_BUILD_PREFIX)-%,%,$@))))" \
		"$(strip $(word 2,$(subst -, ,$(patsubst $(DOCKER_BUILD_PREFIX)-%,%,$@))))" \
		"$(strip $(word 3,$(subst -, ,$(patsubst $(DOCKER_BUILD_PREFIX)-%,%,$@))))" \
		"$(strip $(VERSION))" \
		"$(strip $(COMMIT))" \
		"$(strip $(DATE))" \
		"$(strip $(REPO_PREFIX))" \
		"$(strip $(DOCKER_IMAGE_PREFIX))" \
		"$(strip $(CONTAINERFILE_DIR))" \
		"$(strip $(MYPATH))" \
		"$(strip $(BUILD_OUTPUT_DIR))"

#--------------------------
# Push Targets

# Generic rule for pushing Nix images
$(PUSH_NIX_TARGETS): push-$(NIX_IMAGE_PREFIX)-% : build-$(NIX_IMAGE_PREFIX)-%
	@echo "[$($(TIMESTAMP))] Pushing Nix image $(subst push-,build-, $@)..."
	$(eval IMAGE_TAG_TO_PUSH := $(strip $(REPO_PREFIX)/$(subst image-nix-,nix-go-nix-simple-,$(NIX_IMAGE_PREFIX)-$(*)):$(VERSION)))
	docker push "$(IMAGE_TAG_TO_PUSH)"
	# Optionally push :latest tag too
	docker push "$(strip $(REPO_PREFIX)/$(subst image-nix-,nix-go-nix-simple-,$(NIX_IMAGE_PREFIX)-$(*)):latest)"

# Generic rule for pushing Docker images
$(PUSH_DOCKER_TARGETS) : push_docker-% : $(DOCKER_BUILD_PREFIX)-%
	@echo "[$($(TIMESTAMP))] Pushing Docker image $(subst push_docker-,build_docker-, $@)..."
	# Use $(*) for the stem
	$(eval STEM := $(*))
	$(eval IMAGE_TAG_TO_PUSH := $(strip $(REPO_PREFIX)/$(subst $(DOCKER_BUILD_PREFIX)-,$(DOCKER_IMAGE_PREFIX)-,$(DOCKER_BUILD_PREFIX)-$(STEM)):$(VERSION)))
	docker push "$(IMAGE_TAG_TO_PUSH)"
	# Optionally push :latest tag too
	docker push "$(strip $(REPO_PREFIX)/$(subst $(DOCKER_BUILD_PREFIX)-,$(DOCKER_IMAGE_PREFIX)-,$(DOCKER_BUILD_PREFIX)-$(STEM)):latest)"

#--------------------------
# Validation Targets

# Generic rule for validating Nix images (Calls script)
$(VALIDATE_NIX_TARGETS): validate-$(NIX_IMAGE_PREFIX)-% : build-$(NIX_IMAGE_PREFIX)-% build-validator
	@mkdir -p $(VALIDATION_OUTPUT_DIR) # Create validation dir
	$(eval IMAGE_TAG_TO_VALIDATE := $(strip $(REPO_PREFIX)/$(subst image-nix-,nix-go-nix-simple-,$(NIX_IMAGE_PREFIX)-$(*)):$(VERSION)))
	./scripts/validate_image.sh "$@" "$(VALIDATOR_BIN)" "$(IMAGE_TAG_TO_VALIDATE)" "30" "$(VALIDATION_OUTPUT_DIR)"

# Generic rule for validating Docker images (Calls script)
$(VALIDATE_DOCKER_TARGETS) : validate_docker-% : $(DOCKER_BUILD_PREFIX)-% build-validator
	@mkdir -p $(VALIDATION_OUTPUT_DIR) # Create validation dir
	@echo "[$($(TIMESTAMP))] Validating Docker image $(subst validate_docker-,build_docker-, $@)..."
	# Use $(*) for the stem
	$(eval STEM := $(*))
	$(eval IMAGE_TAG_TO_VALIDATE := $(strip $(REPO_PREFIX)/$(subst $(DOCKER_BUILD_PREFIX)-,$(DOCKER_IMAGE_PREFIX)-,$(DOCKER_BUILD_PREFIX)-$(STEM)):$(VERSION)))
	./scripts/validate_image.sh "$@" "$(VALIDATOR_BIN)" "$(IMAGE_TAG_TO_VALIDATE)" "30" "$(VALIDATION_OUTPUT_DIR)"

#--------------------------
# Summary Target

ALL_NIX_IMAGE_TAGS := $(foreach target,$(NIX_IMAGE_TARGETS),$(REPO_PREFIX)/$(subst build-,,$(target)):$(VERSION))
ALL_DOCKER_IMAGE_TAGS := $(foreach target,$(VALID_DOCKER_IMAGE_TARGETS),$(REPO_PREFIX)/$(subst $(DOCKER_BUILD_PREFIX)-,$(DOCKER_IMAGE_PREFIX)-,$(target)):$(VERSION))
ALL_IMAGE_TAGS := $(ALL_NIX_IMAGE_TAGS) $(ALL_DOCKER_IMAGE_TAGS)

summary:
	./scripts/generate_summary.sh

validation-summary:
	./scripts/generate_validation_summary.sh

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
# docker compose squid

squid: create_squid deploy_squid

create_squid:
	docker build -t my-custom-squid:latest \
		-f ./build/containers/squid/Containerfile \
		./build/containers/squid/

deploy_squid:
	@echo "================================"
	@echo "Make deploy_squid"
	docker compose \
		--file build/containers/squid/docker-compose-squid.yml \
		up -d --remove-orphans

down_squid:
	@echo "================================"
	@echo "Make down_squid"
	docker compose \
		--file build/containers/squid/docker-compose-squid.yml \
		down

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

flake_update:
	nix flake update

flake_develop:
	nix develop

#------------------------
# bazel
install_bazel:
	go install github.com/bazelbuild/bazel-gazelle/cmd/gazelle@latest

gazelle_update:
	bazel run //:gazelle -- update-repos -from_file=go.mod

gazelle_run:
	bazel run //:gazelle

bazel_build:
	bazel build --verbose_failures //cmd/go_nix_simple:go_nix_simple_binary_noupx

bazel_build_oci_distroless:
	bazel build //cmd/go_nix_simple:image_bazel_distroless

bazel_build_oci_scratch:
	bazel build //cmd/go_nix_simple:image_bazel_scratch


# bazel_build:
# 	bazel build //cmd/go_nix_simple:go_nix_simple

bazel_run:
	bazel run //cmd/go_nix_simple:go_nix_simple

bazel_build_a_tarball:
	bazel build //cmd/go_nix_simple:image_bazel_distroless_noupx_tarball

bazel_go:
	bazel build //cmd/go_nix_simple:go_nix_simple_binary_noupx
	#bazel build //cmd/go_nix_simple:image_bazel_distroless_noupx

bazel_build_remote:
	bazel build --config=hp4 //cmd/go_nix_simple:go_nix_simple_binary_noupx

bazel_build_distroless:
	bazel build //cmd/go_nix_simple:image_bazel_distroless_noupx_tarball \
		--define REPO_PREFIX=docker.io/randomizedcoder \
		--define VERSION=latest

bazel_build_scratch:
	bazel build //cmd/go_nix_simple:image_bazel_scratch_upx_tarball \
		--define REPO_PREFIX=docker.io/randomizedcoder \
		--define VERSION=latest

bazel_clean:
	bazel clean --expunge

# end
