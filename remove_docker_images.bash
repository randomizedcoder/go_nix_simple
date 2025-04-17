#!/usr/bin/env bash

# Script to remove Docker images matching a regular expression
# Supports a -f or --force flag to force removal

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
# Prevent errors in a pipeline from being masked.
set -euo pipefail

# --- Configuration ---
DEFAULT_REGEX="go-nix-simple"
FORCE_REMOVE="" # Will be set to "--force" if flag is present
REGEX=""

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE_REMOVE="--force"
      shift # past argument
      ;;
    *)
      # Assume the first non-flag argument is the regex
      if [[ -z "$REGEX" ]]; then
        REGEX="$1"
      else
        echo "Error: Unknown argument or multiple regex patterns provided: $1" >&2
        exit 1
      fi
      shift # past argument
      ;;
  esac
done

# Use default regex if none was provided via arguments
if [[ -z "$REGEX" ]]; then
  REGEX="$DEFAULT_REGEX"
fi

# --- Main Logic ---
echo "Searching for Docker images matching regex: '${REGEX}'"
if [[ -n "$FORCE_REMOVE" ]]; then
  echo "Force removal flag is set."
fi

# Find image Repo:Tag and ID matching the regex and read into an array
SEPARATOR="#|#"
readarray -t FOUND_IMAGES < <(docker images --format "{{.Repository}}:{{.Tag}}${SEPARATOR}{{.ID}}" | grep -E -- "${REGEX}" || true) # Allow grep to not find anything without exiting

# Check if the array is empty
if [ ${#FOUND_IMAGES[@]} -eq 0 ]; then
  echo "No images found matching the regex."
  exit 0
fi

echo "Found the following images to remove:"
# Prepare arrays for IDs and display strings
declare -a IMAGE_IDS_TO_REMOVE
declare -a DISPLAY_STRINGS

# Process the found images
for image_info in "${FOUND_IMAGES[@]}"; do
    # Split the string by the separator, quoting the separator variable
    repo_tag="${image_info%%"${SEPARATOR}"*}"
    image_id="${image_info##*"${SEPARATOR}"}"

    # Add ID to the removal list
    IMAGE_IDS_TO_REMOVE+=("$image_id")
    # Add formatted string to the display list
    DISPLAY_STRINGS+=("  ${repo_tag}  (ID: ${image_id})")
done

# Print each display string on a new line safely using printf
printf "%s\n" "${DISPLAY_STRINGS[@]}"

# Ask for confirmation before removing
read -r -p "Are you sure you want to remove these images? (y/N): " confirm
if ! [[ "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
    echo "Aborting."
    exit 1
fi

echo "Attempting to remove images..."

# Get unique IDs
mapfile -t UNIQUE_IDS < <(printf "%s\n" "${IMAGE_IDS_TO_REMOVE[@]}" | sort -u)

# Check if there are any unique IDs left after filtering
if [ ${#UNIQUE_IDS[@]} -gt 0 ]; then
    # Conditionally add the force flag
    # Note: We expand FORCE_REMOVE which will be empty or "--force"
    # shellcheck disable=SC2086 # We want word splitting for $FORCE_REMOVE
    docker rmi $FORCE_REMOVE -- "${UNIQUE_IDS[@]}"
else
    echo "No unique image IDs found to remove (perhaps they were duplicates)."
fi

echo "Cleanup attempt finished."
