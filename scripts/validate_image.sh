#!/usr/bin/env bash

# scripts/validate_image.sh
# Runs the validation tool against a specified Docker image tag
# and writes a result file to the validation output directory.

# Exit on error, treat unset variables as errors, disable globbing, pipefail
set -euo pipefail

# --- Debug Arguments ---
echo "DEBUG: Received $# arguments:" >&2
arg_index=1
for arg in "$@"; do
  echo "DEBUG: Arg ${arg_index}: '${arg}'" >&2
  ((arg_index++))
done

# --- Arguments ---
# Expect 5 arguments now
if [[ "$#" -ne 5 ]]; then
  echo "Usage: $0 <make_target_name> <validator_path> <image_tag_to_validate> <timeout_seconds> <validation_output_dir>" >&2
  exit 1
fi

# Assign raw arguments
MAKE_TARGET_NAME_RAW="$1"
VALIDATOR_PATH_RAW="$2"
IMAGE_TAG_TO_VALIDATE_RAW="$3"
TIMEOUT_SECONDS_RAW="$4"
VALIDATION_OUTPUT_DIR_RAW="$5" # New argument

# Trim whitespace using xargs
MAKE_TARGET_NAME=$(echo "${MAKE_TARGET_NAME_RAW}" | xargs)
VALIDATOR_PATH=$(echo "${VALIDATOR_PATH_RAW}" | xargs)
IMAGE_TAG_TO_VALIDATE=$(echo "${IMAGE_TAG_TO_VALIDATE_RAW}" | xargs)
TIMEOUT_SECONDS=$(echo "${TIMEOUT_SECONDS_RAW}" | xargs)
VALIDATION_OUTPUT_DIR=$(echo "${VALIDATION_OUTPUT_DIR_RAW}" | xargs) # New argument

# --- Variables ---
TIMESTAMP_CMD='date +"%Y-%m-%d %H:%M:%S.%3N"'
# Define result file path using the Make target name
RESULT_FILE="${VALIDATION_OUTPUT_DIR}/${MAKE_TARGET_NAME}.result"

# --- Validation ---
if [[ ! -x "${VALIDATOR_PATH}" ]]; then
  echo "[$(eval "$TIMESTAMP_CMD")] ERROR: Validator executable not found or not executable at ${VALIDATOR_PATH}" >&2
  exit 1
fi
if ! [[ "${TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]]; then
    echo "[$(eval "$TIMESTAMP_CMD")] ERROR: Timeout value '${TIMEOUT_SECONDS}' is not a valid number." >&2
    exit 1
fi
if [[ ! -d "${VALIDATION_OUTPUT_DIR}" ]]; then
    echo "[$(eval "$TIMESTAMP_CMD")] ERROR: Validation output directory '${VALIDATION_OUTPUT_DIR}' does not exist." >&2
    exit 1
fi

# --- Execute Validator ---
echo "[$(eval "$TIMESTAMP_CMD")] Validating image ${IMAGE_TAG_TO_VALIDATE} (from target ${MAKE_TARGET_NAME})..."

declare -a validator_cmd
validator_cmd=(
  "${VALIDATOR_PATH}"
  "-images=${IMAGE_TAG_TO_VALIDATE}"
  "-timeout=${TIMEOUT_SECONDS}s"
)

printf "Executing command: "
printf "%q " "${validator_cmd[@]}"
printf "\n"

# Execute the validator, capture status and error
validation_error=""
if ! "${validator_cmd[@]}"; then
  # Capture a generic error message if the validator exits non-zero
  # The validator's own logs will have the specific details.
  validation_error="Validator exited with non-zero status"
  echo "[$(eval "$TIMESTAMP_CMD")] ERROR: Validation failed for ${IMAGE_TAG_TO_VALIDATE}" >&2
fi

# --- Write Result File ---
if [[ -z "${validation_error}" ]]; then
  echo "PASSED" > "${RESULT_FILE}"
  echo "[$(eval "$TIMESTAMP_CMD")] Validation successful for ${IMAGE_TAG_TO_VALIDATE}. Result saved to ${RESULT_FILE}"
  exit 0
else
  echo "FAILED: ${validation_error}" > "${RESULT_FILE}"
  echo "[$(eval "$TIMESTAMP_CMD")] Validation failed for ${IMAGE_TAG_TO_VALIDATE}. Result saved to ${RESULT_FILE}"
  exit 1 # Exit with error code 1 if validation failed
fi
