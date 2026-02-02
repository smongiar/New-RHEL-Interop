#!/bin/bash
# List all tests failing with credential errors

set -e

REPORT_DIR="${1:-/var/opt/tnb-tests/tests/springboot/examples/target/failsafe-reports}"
OUTPUT_FILE="${2:-/var/opt/tnb-tests/credential-failures.txt}"

echo "Searching for credential-related test failures..."
echo ""

# Find all test failures with credential errors
{
    echo "=================================================="
    echo "Tests Failing with Credential Errors"
    echo "Generated: $(date)"
    echo "=================================================="
    echo ""
    echo "Search pattern: 'java.lang.RuntimeException: Couldnt get credentials from ids:'"
    echo ""
    echo "=================================================="
    echo "AFFECTED TEST CLASSES"
    echo "=================================================="
    echo ""

    for xml_file in "$REPORT_DIR"/TEST-*.xml; do
        if [ ! -f "$xml_file" ]; then
            continue
        fi

        # Check if this file contains credential errors
        if grep -q "Couldnt get credentials from ids" "$xml_file" 2>/dev/null; then
            # Extract class name
            if command -v xmllint &> /dev/null; then
                classname=$(xmllint --xpath "string(//testsuite/@name)" "$xml_file" 2>/dev/null)
            else
                classname=$(grep -oP 'name="\K[^"]+' "$xml_file" | head -1)
            fi

            echo "Class: $classname"

            # Extract test method names that failed
            if command -v xmllint &> /dev/null; then
                xmllint --xpath "//testcase[failure[contains(text(), 'Couldnt get credentials from ids')] or error[contains(text(), 'Couldnt get credentials from ids')]]/@name" "$xml_file" 2>/dev/null | grep -oP 'name="\K[^"]+' | while read -r method; do
                    echo "  - $method"
                done
            else
                # Fallback: search for testcase elements followed by failure/error with credential message
                grep -B 5 "Couldnt get credentials from ids" "$xml_file" | grep -oP '<testcase.*name="\K[^"]+' | while read -r method; do
                    echo "  - $method"
                done
            fi
            echo ""
        fi
    done

    echo "=================================================="
    echo "MAVEN EXCLUSION PATTERNS"
    echo "=================================================="
    echo ""
    echo "To exclude these tests, use the following Maven options:"
    echo ""

    for xml_file in "$REPORT_DIR"/TEST-*.xml; do
        if [ ! -f "$xml_file" ]; then
            continue
        fi

        if grep -q "Couldnt get credentials from ids" "$xml_file" 2>/dev/null; then
            if command -v xmllint &> /dev/null; then
                classname=$(xmllint --xpath "string(//testsuite/@name)" "$xml_file" 2>/dev/null)
            else
                classname=$(grep -oP 'name="\K[^"]+' "$xml_file" | head -1)
            fi

            # Extract just the test class name (without package)
            simple_name=$(echo "$classname" | awk -F. '{print $NF}')
            echo "  <exclude>**/${simple_name}.java</exclude>"
        fi
    done

    echo ""
    echo "Or use -Dtest exclusion pattern:"
    echo ""
    echo -n "  -Dtest='"
    first=true
    for xml_file in "$REPORT_DIR"/TEST-*.xml; do
        if [ ! -f "$xml_file" ]; then
            continue
        fi

        if grep -q "Couldnt get credentials from ids" "$xml_file" 2>/dev/null; then
            if command -v xmllint &> /dev/null; then
                classname=$(xmllint --xpath "string(//testsuite/@name)" "$xml_file" 2>/dev/null)
            else
                classname=$(grep -oP 'name="\K[^"]+' "$xml_file" | head -1)
            fi

            simple_name=$(echo "$classname" | awk -F. '{print $NF}')
            if [ "$first" = true ]; then
                echo -n "!${simple_name}"
                first=false
            else
                echo -n ",!${simple_name}"
            fi
        fi
    done
    echo "'"
    echo ""

    echo "=================================================="

} | tee "$OUTPUT_FILE"

echo ""
echo "Report saved to: $OUTPUT_FILE"
