#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
FORMAT="report"  # report | lcov | html
MIN_COVERAGE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --lcov)
            FORMAT="lcov"
            shift
            ;;
        --html)
            FORMAT="html"
            shift
            ;;
        --min)
            MIN_COVERAGE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--lcov | --html] [--min <percentage>]"
            echo ""
            echo "Options:"
            echo "  --lcov           Output lcov format to .build/coverage/lcov.info"
            echo "  --html           Generate HTML report in .build/coverage/html/"
            echo "  --min <percent>  Fail if line coverage is below this percentage (e.g., 80)"
            echo ""
            echo "Default: Print summary report to stdout."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "Running tests with code coverage..."
swift test --package-path "$PROJECT_DIR" --enable-code-coverage 2>&1

# Resolve paths
BIN_PATH=$(swift build --package-path "$PROJECT_DIR" --show-bin-path)
PROFDATA="$PROJECT_DIR/.build/$(swift build --package-path "$PROJECT_DIR" --show-bin-path | sed "s|$PROJECT_DIR/.build/||" | cut -d/ -f1-2)/codecov/default.profdata"
TEST_BINARY="$BIN_PATH/asukuPackageTests.xctest/Contents/MacOS/asukuPackageTests"

# Verify files exist
if [ ! -f "$PROFDATA" ]; then
    echo "Error: profdata not found at $PROFDATA"
    echo "Searching..."
    find "$PROJECT_DIR/.build" -name "default.profdata" -print 2>/dev/null
    exit 1
fi

if [ ! -f "$TEST_BINARY" ]; then
    echo "Error: test binary not found at $TEST_BINARY"
    exit 1
fi

# Common flags: exclude test code and build artifacts from coverage
IGNORE_REGEX='.build|Tests/'

COVERAGE_DIR="$PROJECT_DIR/.build/coverage"
mkdir -p "$COVERAGE_DIR"

case "$FORMAT" in
    report)
        echo ""
        echo "=== Code Coverage Report ==="
        echo ""
        xcrun llvm-cov report \
            "$TEST_BINARY" \
            --instr-profile "$PROFDATA" \
            --ignore-filename-regex="$IGNORE_REGEX"
        ;;
    lcov)
        LCOV_FILE="$COVERAGE_DIR/lcov.info"
        xcrun llvm-cov export \
            "$TEST_BINARY" \
            --instr-profile "$PROFDATA" \
            --ignore-filename-regex="$IGNORE_REGEX" \
            --format=lcov \
            > "$LCOV_FILE"
        echo "lcov written to: $LCOV_FILE"
        ;;
    html)
        HTML_DIR="$COVERAGE_DIR/html"
        rm -rf "$HTML_DIR"
        xcrun llvm-cov show \
            "$TEST_BINARY" \
            --instr-profile "$PROFDATA" \
            --ignore-filename-regex="$IGNORE_REGEX" \
            --format=html \
            --output-dir="$HTML_DIR"
        echo "HTML report written to: $HTML_DIR/index.html"
        ;;
esac

# Minimum coverage gate
if [ -n "$MIN_COVERAGE" ]; then
    # Extract total line coverage percentage from report.
    # TOTAL row layout: ... Lines MissedLines Cover% Branches MissedBranches Cover
    # Line coverage % is at field $10 (NF-3).
    ACTUAL=$(xcrun llvm-cov report \
        "$TEST_BINARY" \
        --instr-profile "$PROFDATA" \
        --ignore-filename-regex="$IGNORE_REGEX" \
        | grep "^TOTAL" \
        | awk '{print $(NF-3)}' \
        | tr -d '%')

    echo ""
    echo "Line coverage: ${ACTUAL}% (minimum: ${MIN_COVERAGE}%)"

    # Compare as integers (multiply by 100 to avoid float issues)
    ACTUAL_INT=$(echo "$ACTUAL" | awk '{printf "%d", $1 * 100}')
    MIN_INT=$(echo "$MIN_COVERAGE" | awk '{printf "%d", $1 * 100}')

    if [ "$ACTUAL_INT" -lt "$MIN_INT" ]; then
        echo "FAIL: Coverage ${ACTUAL}% is below minimum ${MIN_COVERAGE}%"
        exit 1
    else
        echo "PASS: Coverage meets minimum threshold."
    fi
fi
