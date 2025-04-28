# --- Print Summary ---
echo "========================================================================"
echo "Aggregated Validation Summary - From Directory: ${LATEST_VALIDATION_DIR}"
echo "========================================================================"

# Print PASSED section if any passed
if [[ ${passed_count} -gt 0 ]]; then
    echo "PASSED (${passed_count}):"
    # Sort alphabetically before printing (optional but nice)
    mapfile -t sorted_passed < <(printf '%s\n' "${passed_targets[@]}" | sort)
    printf "  %s\n" "${sorted_passed[@]}" # Print sorted list
fi

# Print FAILED section if any failed
if [[ ${failed_count} -gt 0 ]]; then
    # Add a blank line if PASSED section was also printed
    [[ ${passed_count} -gt 0 ]] && echo ""
    echo "FAILED (${failed_count}):"
    # Sort alphabetically before printing (optional but nice)
    mapfile -t sorted_failed < <(printf '%s\n' "${failed_targets[@]}" | sort)
    for target in "${sorted_failed[@]}"; do
        # Safely handle potential missing reasons (though unlikely with current logic)
        reason="${failed_reasons[${target}]:-Unknown Error}"
        printf "  %s (Reason: %s)\n" "${target}" "${reason}"
    done
fi

# Print Footer
echo "------------------------------------------------------------------------"
echo "Total Validations: ${total_count} | Passed: ${passed_count} | Failed: ${failed_count}"
echo "========================================================================"

# Exit with non-zero status if any tests failed
if [[ ${failed_count} -gt 0 ]]; then
    exit 1
fi

exit 0
