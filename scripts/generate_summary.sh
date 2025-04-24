#!/usr/bin/env bash

# scripts/generate_summary.sh
# Finds the latest build output directory under ./output, reads build metric
# CSV files from it, prints a summary table, and saves it to summary.txt
# within that directory.

# Exit on error, treat unset variables as errors, disable globbing, pipefail
set -euo pipefail

# --- Argument ---
# No arguments needed, script finds the latest directory
# if [[ "$#" -ne 1 ]]; then
#   echo "Usage: $0 <build_output_directory>" >&2
#   exit 1
# fi
# BUILD_OUTPUT_DIR="$1" # Removed argument handling

# --- Phase 1: Find Newest Output Directory ---
BASE_OUTPUT_DIR="./output"

if [[ ! -d "${BASE_OUTPUT_DIR}" ]]; then
  echo "ERROR: Base output directory '${BASE_OUTPUT_DIR}' not found." >&2
  exit 1
fi

# Find directories matching the timestamp pattern, sort descending, get the first one
LATEST_OUTPUT_DIR=$(find "${BASE_OUTPUT_DIR}" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex '.*/[0-9]{8}_[0-9]{6}' -print | sort -r | head -n 1)

if [[ -z "${LATEST_OUTPUT_DIR}" ]]; then
  echo "ERROR: No valid output directory found under ${BASE_OUTPUT_DIR}" >&2
  exit 1
fi

echo "DEBUG: Phase 1 - Found latest output directory: '${LATEST_OUTPUT_DIR}'" >&2
SUMMARY_FILE="${LATEST_OUTPUT_DIR}/summary.txt" # Define summary output file path
# --- End Phase 1 ---


# --- Phase 2: Find Metric Files in Latest Directory ---
echo "DEBUG: Phase 2 - Searching for 'build-*.csv' files in '${LATEST_OUTPUT_DIR}'" >&2

# Use mapfile to read null-delimited output from find into the array
declare -a metric_files
mapfile -d $'\0' metric_files < <(find "${LATEST_OUTPUT_DIR}" -maxdepth 1 -name 'build-*.csv' -print0 | sort -z)

# mapfile might add an empty element if the input ends with a delimiter, remove it.
if [[ ${#metric_files[@]} -gt 0 && -z "${metric_files[-1]}" ]]; then
    unset 'metric_files[-1]' # Remove the last empty element
fi

# Debugging: Print found files
if [[ ${#metric_files[@]} -eq 0 ]]; then
  echo "DEBUG: Phase 2 - No 'build-*.csv' files found." >&2
else
  echo "DEBUG: Phase 2 - Found ${#metric_files[@]} metric file(s):" >&2
  printf "  '%s'\n" "${metric_files[@]}" >&2
fi
# --- End Phase 2 ---


# --- Phase 3: Generate Summary Content ---
# Use a temporary variable to store the summary content
summary_content=""
header_line_1="========================================================================================"
header_line_2="Build Summary - From Directory: ${LATEST_OUTPUT_DIR}"
header_line_3="Target                                                      | Time (ms) | Size (MB) | Layers"
header_line_4="------------------------------------------------------------|-----------|-----------|--------"

summary_content+="${header_line_1}\n"
summary_content+="${header_line_2}\n"
summary_content+="${header_line_1}\n" # Repeat separator
summary_content+="${header_line_3}\n"
summary_content+="${header_line_4}\n"

if [[ ${#metric_files[@]} -eq 0 ]]; then
  summary_content+="No build data files (*.csv) found in ${LATEST_OUTPUT_DIR}\n"
else
  # Process the found files using awk and append to the variable
  summary_content+=$(printf '%s\0' "${metric_files[@]}" | xargs -0 awk -F',' '{printf "%-60s| %9d | %9.2f | %6d\n", $1, $2, $3/1024/1024, $4}')
  # Add an explicit newline AFTER the awk output, BEFORE the footer separator
  summary_content+="\n"
fi

summary_content+="${header_line_1}\n" # Footer separator
# --- End Phase 3 ---


# --- Phase 4: Output Summary ---
# Print to console
echo -e "${summary_content}"

# Write to file
echo -e "${summary_content}" > "${SUMMARY_FILE}"
echo "INFO: Summary saved to ${SUMMARY_FILE}"
# --- End Phase 4 ---

exit 0
