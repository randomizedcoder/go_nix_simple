#!/usr/bin/env bash

# scripts/generate_summary.sh
# Finds the latest build output directory under ./output, reads build metric
# CSV files from it, and prints a summary table.

# Exit on error, treat unset variables as errors, disable globbing, pipefail
set -euo pipefail

BASE_OUTPUT_DIR="./output"

if [[ ! -d "${BASE_OUTPUT_DIR}" ]]; then
  echo "ERROR: Base output directory '${BASE_OUTPUT_DIR}' not found." >&2
  exit 1
fi

# Find directories matching the timestamp pattern, sort descending, get the first one
# Assumes directory names are like YYYYMMDD_HHMMSS
LATEST_OUTPUT_DIR=$(find "${BASE_OUTPUT_DIR}" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex '.*/[0-9]{8}_[0-9]{6}' -print | sort -r | head -n 1)

if [[ -z "${LATEST_OUTPUT_DIR}" ]]; then
  echo "ERROR: No valid output directory found under ${BASE_OUTPUT_DIR}" >&2
  exit 1
fi

echo "DEBUG: Phase 1 - Found latest output directory: '${LATEST_OUTPUT_DIR}'" >&2
# --- End Phase 1 ---


# --- Phase 2: Find Metric Files in Latest Directory ---
echo "DEBUG: Phase 2 - Searching for 'build-*.csv' files in '${LATEST_OUTPUT_DIR}'" >&2

# Use mapfile to read null-delimited output from find into the array
declare -a metric_files
mapfile -d $'\0' metric_files < <(find "${LATEST_OUTPUT_DIR}" -maxdepth 1 -name 'build-*.csv' -print0 | sort -z)

# mapfile might add an empty element if the input ends with a delimiter, remove it.
# Check if the array has elements AND the last element is empty.
if [[ ${#metric_files[@]} -gt 0 && -z "${metric_files[-1]}" ]]; then
    unset 'metric_files[-1]' # Remove the last empty element
fi

# Debugging: Print found files
if [[ ${#metric_files[@]} -eq 0 ]]; then
  echo "DEBUG: Phase 2 - No 'build-*.csv' files found." >&2
else
  echo "DEBUG: Phase 2 - Found ${#metric_files[@]} metric file(s):" >&2
  # This line should now be safe even with set -u
  printf "  '%s'\n" "${metric_files[@]}" >&2
fi
# --- End Phase 2 ---


# --- Phase 3: Pretty Print Summary ---
echo "========================================================================================"
echo "Build Summary - From Directory: ${LATEST_OUTPUT_DIR}"
echo "========================================================================================"
echo "Target                                                      | Time (ms) | Size (MB) | Layers"
echo "------------------------------------------------------------|-----------|-----------|--------"

if [[ ${#metric_files[@]} -eq 0 ]]; then
  echo "No build data files (*.csv) found in ${LATEST_OUTPUT_DIR}"
else
  # Process the found files using awk
  # Pass the filenames safely using null delimiters with xargs
  printf '%s\0' "${metric_files[@]}" | xargs -0 awk -F',' '{printf "%-60s| %9d | %9.2f | %6d\n", $1, $2, $3/1024/1024, $4}'
fi

echo "========================================================================================"
# --- End Phase 3 ---

exit 0

# end