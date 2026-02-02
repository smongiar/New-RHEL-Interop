#!/bin/bash
# Generate test report from Maven Failsafe results

set -e

REPORT_DIR="${1:-/var/opt/tnb-tests/tests/springboot/examples/target/failsafe-reports}"
OUTPUT_FILE="${2:-/var/opt/tnb-tests/test-summary-report.txt}"

echo "=================================================="
echo "TNB Test Results Summary Report"
echo "Generated: $(date)"
echo "=================================================="
echo ""

# Check if report directory exists
if [ ! -d "$REPORT_DIR" ]; then
    echo "ERROR: Report directory not found: $REPORT_DIR"
    exit 1
fi

# Initialize counters
TOTAL_TESTS=0
SUCCESSFUL_TESTS=0
FAILED_TESTS=0
ERROR_TESTS=0
SKIPPED_TESTS=0

# Create temporary files for test lists
SUCCESSFUL_LIST=$(mktemp)
FAILED_LIST=$(mktemp)
ERROR_LIST=$(mktemp)
SKIPPED_LIST=$(mktemp)
CREDENTIAL_ERROR_LIST=$(mktemp)

# Process XML files
for xml_file in "$REPORT_DIR"/TEST-*.xml; do
    if [ ! -f "$xml_file" ]; then
        continue
    fi

    # Extract test counts from XML
    if command -v xmllint &> /dev/null; then
        # Use xmllint if available
        tests=$(xmllint --xpath "string(//testsuite/@tests)" "$xml_file" 2>/dev/null || echo "0")
        failures=$(xmllint --xpath "string(//testsuite/@failures)" "$xml_file" 2>/dev/null || echo "0")
        errors=$(xmllint --xpath "string(//testsuite/@errors)" "$xml_file" 2>/dev/null || echo "0")
        skipped=$(xmllint --xpath "string(//testsuite/@skipped)" "$xml_file" 2>/dev/null || echo "0")
        classname=$(xmllint --xpath "string(//testsuite/@name)" "$xml_file" 2>/dev/null || basename "$xml_file" .xml | sed 's/^TEST-//')
    else
        # Fallback to grep/sed
        tests=$(grep -oP 'tests="\K[0-9]+' "$xml_file" | head -1 || echo "0")
        failures=$(grep -oP 'failures="\K[0-9]+' "$xml_file" | head -1 || echo "0")
        errors=$(grep -oP 'errors="\K[0-9]+' "$xml_file" | head -1 || echo "0")
        skipped=$(grep -oP 'skipped="\K[0-9]+' "$xml_file" | head -1 || echo "0")
        classname=$(grep -oP 'name="\K[^"]+' "$xml_file" | head -1 || basename "$xml_file" .xml | sed 's/^TEST-//')
    fi

    # Convert to integers (handle empty strings)
    tests=${tests:-0}
    failures=${failures:-0}
    errors=${errors:-0}
    skipped=${skipped:-0}

    # Calculate successful tests for this class
    successful=$((tests - failures - errors - skipped))

    # Update totals
    TOTAL_TESTS=$((TOTAL_TESTS + tests))
    FAILED_TESTS=$((FAILED_TESTS + failures))
    ERROR_TESTS=$((ERROR_TESTS + errors))
    SKIPPED_TESTS=$((SKIPPED_TESTS + skipped))
    SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + successful))

    # Categorize test class
    if [ "$failures" -gt 0 ] || [ "$errors" -gt 0 ]; then
        if [ "$errors" -gt 0 ]; then
            echo "$classname (errors: $errors, failures: $failures)" >> "$ERROR_LIST"
        else
            echo "$classname (failures: $failures)" >> "$FAILED_LIST"
        fi

        # Check for credential errors
        if grep -q "Couldnt get credentials from ids" "$xml_file" 2>/dev/null; then
            echo "$classname" >> "$CREDENTIAL_ERROR_LIST"
        fi
    elif [ "$skipped" -gt 0 ]; then
        echo "$classname (skipped: $skipped)" >> "$SKIPPED_LIST"
    elif [ "$successful" -gt 0 ]; then
        echo "$classname (passed: $successful)" >> "$SUCCESSFUL_LIST"
    fi
done

# Generate report
{
    echo "=================================================="
    echo "TNB Test Results Summary Report"
    echo "Generated: $(date)"
    echo "=================================================="
    echo ""
    echo "OVERVIEW"
    echo "--------"
    echo "Total Tests:      $TOTAL_TESTS"
    echo "Successful:       $SUCCESSFUL_TESTS"
    echo "Failed:           $FAILED_TESTS"
    echo "Errors:           $ERROR_TESTS"
    echo "Skipped:          $SKIPPED_TESTS"
    echo ""

    if [ "$SUCCESSFUL_TESTS" -gt 0 ]; then
        echo "=================================================="
        echo "SUCCESSFUL TEST CLASSES ($SUCCESSFUL_TESTS tests)"
        echo "=================================================="
        cat "$SUCCESSFUL_LIST" | sort
        echo ""
    fi

    if [ "$FAILED_TESTS" -gt 0 ]; then
        echo "=================================================="
        echo "FAILED TEST CLASSES ($FAILED_TESTS tests)"
        echo "=================================================="
        cat "$FAILED_LIST" | sort
        echo ""
    fi

    if [ "$ERROR_TESTS" -gt 0 ]; then
        echo "=================================================="
        echo "ERROR TEST CLASSES ($ERROR_TESTS tests)"
        echo "=================================================="
        cat "$ERROR_LIST" | sort
        echo ""
    fi

    if [ "$SKIPPED_TESTS" -gt 0 ]; then
        echo "=================================================="
        echo "SKIPPED TEST CLASSES ($SKIPPED_TESTS tests)"
        echo "=================================================="
        cat "$SKIPPED_LIST" | sort
        echo ""
    fi

    # Special section for credential errors
    if [ -s "$CREDENTIAL_ERROR_LIST" ]; then
        echo "=================================================="
        echo "TESTS FAILING WITH CREDENTIAL ERRORS"
        echo "=================================================="
        echo "These tests failed with: 'java.lang.RuntimeException: Couldnt get credentials from ids:'"
        echo ""
        cat "$CREDENTIAL_ERROR_LIST" | sort | uniq
        echo ""
        echo "Consider excluding these tests if credentials are not available:"
        echo ""
        cat "$CREDENTIAL_ERROR_LIST" | sort | uniq | while read -r class; do
            echo "  -Dtest='!${class}'"
        done
        echo ""
    fi

    echo "=================================================="
    echo "Full test reports available at: $REPORT_DIR"
    echo "=================================================="
} | tee "$OUTPUT_FILE"

# Cleanup
rm -f "$SUCCESSFUL_LIST" "$FAILED_LIST" "$ERROR_LIST" "$SKIPPED_LIST" "$CREDENTIAL_ERROR_LIST"

echo ""
echo "Report saved to: $OUTPUT_FILE"
