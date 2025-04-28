#!/usr/bin/env bash

# scripts/build_nix_image.sh
# Builds a specific Nix flake image output, loads it into Docker,
# inspects it, and saves build metrics to a file.

# Exit on error, treat unset variables as errors, disable globbing, pipefail
set -euo pipefail

# --- Arguments ---
if [[ "$#" -ne 4 ]]; then
  echo "Usage: $0 <target_name> <flake_output_key> <expected_docker_tag_versioned> <output_dir>" >&2
  exit 1
fi

TARGET_NAME="$1"
FLAKE_OUTPUT_KEY="$2"
EXPECTED_DOCKER_TAG_VERSIONED="$3" # e.g., repo/img:1.0.0
OUTPUT_DIR="$4"

# --- Variables ---
TIMESTAMP_CMD='date +"%Y-%m-%d %H:%M:%S.%3N"'
METRIC_FILE="${OUTPUT_DIR}/${TARGET_NAME}.csv"
NIX_BUILD_RESULT_LINK="./result"
# Derive the :latest tag from the versioned tag
EXPECTED_DOCKER_TAG_LATEST="${EXPECTED_DOCKER_TAG_VERSIONED%:*}:latest"

# --- Validation ---
if [[ ! -d "${OUTPUT_DIR}" ]]; then
  echo "[$(eval "$TIMESTAMP_CMD")] ERROR: Output directory not found at ${OUTPUT_DIR}" >&2
  exit 1
fi

# --- Build Phase ---
echo "[$(eval "$TIMESTAMP_CMD")] Starting ${TARGET_NAME} (Nix Build)..."
start_time_ns=$(date +%s%N)

if ! nix build ".#${FLAKE_OUTPUT_KEY}" --out-link "${NIX_BUILD_RESULT_LINK}"; then
  echo "[$(eval "$TIMESTAMP_CMD")] ERROR: Nix build failed for ${FLAKE_OUTPUT_KEY}" >&2
  exit 1
fi

nix_build_end_time_ns=$(date +%s%N)
nix_build_duration_ms=$(( (nix_build_end_time_ns - start_time_ns) / 1000000 ))
echo "[$(eval "$TIMESTAMP_CMD")] Finished Nix build for ${TARGET_NAME}. Duration: ${nix_build_duration_ms} ms."

# --- Docker Load Phase ---
echo "[$(eval "$TIMESTAMP_CMD")] Loading Nix result into Docker..."
if ! docker load < "${NIX_BUILD_RESULT_LINK}"; then
    echo "[$(eval "$TIMESTAMP_CMD")] ERROR: docker load failed for ${TARGET_NAME}" >&2
    rm -f "${NIX_BUILD_RESULT_LINK}"
    exit 1
fi
echo "[$(eval "$TIMESTAMP_CMD")] Finished loading Nix result (Image tagged as :latest)."

# --- Docker Tag Phase ---
# Explicitly tag the loaded image (:latest) with the specific version tag
echo "[$(eval "$TIMESTAMP_CMD")] Tagging ${EXPECTED_DOCKER_TAG_LATEST} as ${EXPECTED_DOCKER_TAG_VERSIONED}..."
if ! docker tag "${EXPECTED_DOCKER_TAG_LATEST}" "${EXPECTED_DOCKER_TAG_VERSIONED}"; then
    echo "[$(eval "$TIMESTAMP_CMD")] ERROR: docker tag failed for ${TARGET_NAME}" >&2
    rm -f "${NIX_BUILD_RESULT_LINK}"
    exit 1
fi
echo "[$(eval "$TIMESTAMP_CMD")] Finished tagging image."


# --- Collect Metrics ---
# Now inspect using the versioned tag, which should exist
echo "[$(eval "$TIMESTAMP_CMD")] Collecting metrics for ${EXPECTED_DOCKER_TAG_VERSIONED}..."
image_size_bytes_raw=$(docker image inspect --format='{{.Size}}' "${EXPECTED_DOCKER_TAG_VERSIONED}" 2>/dev/null)
layer_count_raw=$(docker image inspect --format='{{len .RootFS.Layers}}' "${EXPECTED_DOCKER_TAG_VERSIONED}" 2>/dev/null)

image_size_bytes=${image_size_bytes_raw:-0}
layer_count=${layer_count_raw:-0}

if [[ "${image_size_bytes}" == 0 || "${layer_count}" == 0 ]]; then
    echo "[$(eval "$TIMESTAMP_CMD")] WARNING: Could not inspect image ${EXPECTED_DOCKER_TAG_VERSIONED}. Size/Layers set to 0." >&2
fi

# --- Write Metrics File ---
echo "${TARGET_NAME},${nix_build_duration_ms},${image_size_bytes},${layer_count}" > "${METRIC_FILE}"
echo "[$(eval "$TIMESTAMP_CMD")] Metrics saved to ${METRIC_FILE}"

# --- Cleanup ---
rm -f "${NIX_BUILD_RESULT_LINK}"

exit 0
