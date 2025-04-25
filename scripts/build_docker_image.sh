#!/usr/bin/env bash

# scripts/build_docker_image.sh
# Builds a specific Docker image variant for go-nix-simple

# Exit on error, treat unset variables as errors, disable globbing, pipefail
set -euo pipefail

# # --- Debug Arguments ---
# echo "DEBUG: Received $# arguments:" >&2
# arg_index=1
# for arg in "$@"; do
#   echo "DEBUG: Arg ${arg_index}: '${arg}'" >&2
#   ((arg_index++))
# done

# --- Arguments ---
if [[ "$#" -ne 11 ]]; then
  echo "Usage: $0 <base> <cache> <packer> <version> <commit> <date> <repo_prefix> <docker_image_prefix> <containerfile_dir> <context_path>"
  exit 1
fi

# Assign arguments to variables
BASE_RAW="$1"
CACHE_RAW="$2"
PACKER_RAW="$3"
VERSION_RAW="$4"
COMMIT_RAW="$5"
DATE_RAW="$6"
REPO_PREFIX_RAW="$7"
DOCKER_IMAGE_PREFIX_RAW="$8"
CONTAINERFILE_DIR_RAW="$9"
CONTEXT_PATH_RAW="${10}"
OUTPUT_DIR_RAW="${11}"

# --- Trim Whitespace ---
# Use xargs to remove leading/trailing whitespace from relevant variables
BASE=$(echo "${BASE_RAW}" | xargs)
CACHE=$(echo "${CACHE_RAW}" | xargs)
PACKER=$(echo "${PACKER_RAW}" | xargs)
VERSION=$(echo "${VERSION_RAW}" | xargs)
COMMIT=$(echo "${COMMIT_RAW}" | xargs)
DATE=$(echo "${DATE_RAW}" | xargs)
REPO_PREFIX=$(echo "${REPO_PREFIX_RAW}" | xargs)
DOCKER_IMAGE_PREFIX=$(echo "${DOCKER_IMAGE_PREFIX_RAW}" | xargs)
CONTAINERFILE_DIR=$(echo "${CONTAINERFILE_DIR_RAW}" | xargs)
CONTEXT_PATH=$(echo "${CONTEXT_PATH_RAW}" | xargs)
OUTPUT_DIR=$(echo "${OUTPUT_DIR_RAW}" | xargs)

# --- Variables ---
TARGET_NAME="build-image-docker-${BASE}-${CACHE}-${PACKER}"
CONTAINERFILE="${CONTAINERFILE_DIR}/Containerfile.${BASE}.${CACHE}.${PACKER}"
IMAGE_TAG="${REPO_PREFIX}/${DOCKER_IMAGE_PREFIX}-${BASE}-${CACHE}-${PACKER}:${VERSION}"
LATEST_TAG="${REPO_PREFIX}/${DOCKER_IMAGE_PREFIX}-${BASE}-${CACHE}-${PACKER}:latest"
TIMESTAMP_CMD='date +"%Y-%m-%d %H:%M:%S.%3N"'
METRIC_FILE="${OUTPUT_DIR}/${TARGET_NAME}.csv"

# --- Validation ---
if [[ ! -f "${CONTAINERFILE}" ]]; then
  echo "[$(eval "$TIMESTAMP_CMD")] ERROR: Containerfile not found at ${CONTAINERFILE}" >&2
  exit 1
fi
if [[ ! -d "${OUTPUT_DIR}" ]]; then
  echo "[$(eval "$TIMESTAMP_CMD")] ERROR: Output directory not found at ${OUTPUT_DIR}" >&2
  exit 1
fi

# --- Construct Docker Command Array ---
# Using an array is safer for handling arguments with spaces or special chars
declare -a docker_build_cmd
docker_build_cmd=(
  "docker" "build"
  "--network=host"
  "--build-arg" "MYPATH=${CONTEXT_PATH}"
  "--build-arg" "COMMIT=${COMMIT}"
  "--build-arg" "DATE=${DATE}"
  "--build-arg" "VERSION=${VERSION}"
  "--file" "${CONTAINERFILE}"
  "--tag" "${IMAGE_TAG}"
  "--tag" "${LATEST_TAG}"
  "${CONTEXT_PATH}"
)

# --- Build ---
echo "[$(eval "$TIMESTAMP_CMD")] Starting ${TARGET_NAME}..."
# Print the command before executing (using printf for better quoting visibility)
printf "Executing command: "
printf "%q " "${docker_build_cmd[@]}"
printf "\n"

start_time_ns=$(date +%s%N)

# Execute the command from the array, capture potential errors
if ! "${docker_build_cmd[@]}"; then
  echo "[$(eval "$TIMESTAMP_CMD")] ERROR: Docker build failed for ${TARGET_NAME}" >&2
  exit 1 # Exit if build fails
fi

# --- Timing ---
end_time_ns=$(date +%s%N)
duration_ms=$(( (end_time_ns - start_time_ns) / 1000000 ))
echo "[$(eval "$TIMESTAMP_CMD")] Finished ${TARGET_NAME}. Duration: ${duration_ms} ms."

# --- Collect Metrics ---
echo "[$(eval "$TIMESTAMP_CMD")] Collecting metrics for ${IMAGE_TAG}..."
# Use temporary variables to store inspect results, handle potential errors
image_size_bytes_raw=$(docker image inspect --format='{{.Size}}' "${IMAGE_TAG}" 2>/dev/null)
layer_count_raw=$(docker image inspect --format='{{len .RootFS.Layers}}' "${IMAGE_TAG}" 2>/dev/null)

# Assign default value 0 if inspect failed or returned empty
image_size_bytes=${image_size_bytes_raw:-0}
layer_count=${layer_count_raw:-0}

if [[ "${image_size_bytes}" == 0 || "${layer_count}" == 0 ]]; then
    echo "[$(eval "$TIMESTAMP_CMD")] WARNING: Could not inspect image ${IMAGE_TAG}. Size/Layers set to 0." >&2
fi

# --- Write Metrics File ---
# Format: target_name,duration_ms,size_bytes,layer_count
echo "${TARGET_NAME},${duration_ms},${image_size_bytes},${layer_count}" > "${METRIC_FILE}"
echo "[$(eval "$TIMESTAMP_CMD")] Metrics saved to ${METRIC_FILE}"

exit 0 # Explicitly exit successfully
