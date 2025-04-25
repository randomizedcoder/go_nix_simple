#
# /go-nix-simple/Makefile
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
MYPATH = $(shell pwd)
REPO_PREFIX := randomizedcoder

# --- Output Directory for Metrics ---
BUILD_RUN_TIMESTAMP := $(shell date +"%Y%m%d_%H%M%S")
BUILD_OUTPUT_DIR := ./output/$(BUILD_RUN_TIMESTAMP)

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
                              $(DOCKER_TARGET_PREFIX)-$(base)-$(cache)-$(packer))))

# No filters yet
INVALID_DOCKER_COMBOS :=
# INVALID_DOCKER_COMBOS := $(filter %-athens-upx, $(DOCKER_IMAGE_TARGETS)) \
#                          $(filter %-http-upx, $(DOCKER_IMAGE_TARGETS)) \
#                          $(filter %-none-upx, $(DOCKER_IMAGE_TARGETS)) \
#                          $(filter %-scratch-athens-upx, $(DOCKER_IMAGE_TARGETS))

#VALID_DOCKER_IMAGE_TARGETS := $(filter-out $(INVALID_DOCKER_COMBOS), $(DOCKER_IMAGE_TARGETS))

# --- Generate Lists of Validation Targets ---
VALIDATE_NIX_TARGETS := $(NIX_IMAGE_TARGETS:build-%=validate-%)
VALIDATE_DOCKER_TARGETS := $(VALID_DOCKER_IMAGE_TARGETS:build-%=validate-%)
ALL_VALIDATE_TARGETS := $(VALIDATE_NIX_TARGETS) $(VALIDATE_DOCKER_TARGETS)


# --- Phony Targets ---
.PHONY: all all-nix all-docker \
	prepare-output-dir generate-containerfiles \
	build-validator \
	validate-all validate-all-nix validate-all-docker \
	load-nix-result \
	summary \
	$(NIX_IMAGE_TARGETS) \
	$(VALID_DOCKER_IMAGE_TARGETS) \
	$(ALL_VALIDATE_TARGETS) \
	deploy_athens down_athens run_athens ls dive run curl prepare clear_go_mod_cache go_clean \
	flake_metadata flake_show \
	install_bazel gazelle_init gazelle_run bazel_build bazel_run \
	bazel_build_a_tarball bazel_go

# --- Aggregate Targets ---
all: prepare-output-dir all-nix all-docker summary
all-nix: prepare-output-dir $(NIX_IMAGE_TARGETS)
all-docker: prepare-output-dir $(VALID_DOCKER_IMAGE_TARGETS)

validate-all: $(ALL_VALIDATE_TARGETS)
validate-all-nix: $(VALIDATE_NIX_TARGETS)
validate-all-docker: $(VALIDATE_DOCKER_TARGETS)

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
# Validator Build Target   # <-- NEW SECTION
build-validator:
	@echo "[$($(TIMESTAMP))] Building validator tool..."
	@$(MAKE) -C $(VALIDATOR_DIR) build
	@echo "[$($(TIMESTAMP))] Finished building validator tool."

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

$(VALID_DOCKER_IMAGE_TARGETS): $(DOCKER_TARGET_PREFIX)-% : prepare-output-dir generate-containerfiles
	./scripts/build_docker_image.sh \
		"$(strip $(word 1,$(subst -, ,$(patsubst $(DOCKER_TARGET_PREFIX)-%,%,$@))))" \
		"$(strip $(word 2,$(subst -, ,$(patsubst $(DOCKER_TARGET_PREFIX)-%,%,$@))))" \
		"$(strip $(word 3,$(subst -, ,$(patsubst $(DOCKER_TARGET_PREFIX)-%,%,$@))))" \
		"$(strip $(VERSION))" \
		"$(strip $(COMMIT))" \
		"$(strip $(DATE))" \
		"$(strip $(REPO_PREFIX))" \
		"$(strip $(DOCKER_IMAGE_PREFIX))" \
		"$(strip $(CONTAINERFILE_DIR))" \
		"$(strip $(MYPATH))" \
		"$(strip $(BUILD_OUTPUT_DIR))"

#--------------------------
# Validation Targets

# Generic rule for validating Nix images
$(VALIDATE_NIX_TARGETS): validate-$(NIX_IMAGE_PREFIX)-% : build-$(NIX_IMAGE_PREFIX)-% build-validator
	@echo "[$($(TIMESTAMP))] Validating Nix image $(subst validate-,, $@)..."
	$(eval IMAGE_TAG_TO_VALIDATE := $(strip $(REPO_PREFIX)/$(subst image-nix-,nix-go-nix-simple-,$(NIX_IMAGE_PREFIX)-$(*)):$(VERSION)))
	$(VALIDATOR_BIN) -images="$(IMAGE_TAG_TO_VALIDATE)" -timeout=30s

# Generic rule for validating Docker images
validate-$(DOCKER_TARGET_PREFIX)-% : $(DOCKER_TARGET_PREFIX)-% build-validator
	@echo "[$($(TIMESTAMP))] Validating Docker image $(subst validate-,, $@)..."
	# *** Adjust tag calculation to use $@ and patsubst ***
	$(eval STEM := $(patsubst validate-$(DOCKER_TARGET_PREFIX)-%,%,$@))
	$(eval IMAGE_TAG_TO_VALIDATE := $(strip $(REPO_PREFIX)/$(subst $(DOCKER_TARGET_PREFIX)-,$(DOCKER_IMAGE_PREFIX)-,$(DOCKER_TARGET_PREFIX)-$(STEM)):$(VERSION)))
	$(VALIDATOR_BIN) -images="$(IMAGE_TAG_TO_VALIDATE)" -timeout=30s

#--------------------------
# Summary Target

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

gazelle_update:
	bazel run //:gazelle -- update-repos -from_file=go.mod

gazelle_run:
	bazel run //:gazelle

bazel_build:
	bazel build //cmd/go_nix_simple:go_nix_simple

bazel_run:
	bazel run //cmd/go_nix_simple:go_nix_simple

bazel_build_a_tarball:
	bazel build //cmd/go_nix_simple:image_bazel_distroless_noupx_tarball

bazel_go:
	bazel build //cmd/go_nix_simple:image_bazel_distroless_noupx

# end
