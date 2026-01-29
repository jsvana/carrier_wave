#!/usr/bin/env bash
# Pre-commit hook for FullDuplex
# Runs SwiftFormat (check) and SwiftLint on staged Swift files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Get staged Swift files (excluding Tools/ which contains standalone scripts)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' | grep -v '^Tools/' || true)

if [ -z "$STAGED_FILES" ]; then
    echo -e "${GREEN}No Swift files staged, skipping lint/format checks${NC}"
    exit 0
fi

echo -e "${YELLOW}Checking staged Swift files...${NC}"

# Check if tools are available
SWIFTFORMAT_AVAILABLE=false
SWIFTLINT_AVAILABLE=false

if command -v swiftformat &> /dev/null; then
    SWIFTFORMAT_AVAILABLE=true
else
    echo -e "${YELLOW}Warning: swiftformat not found. Install with: brew install swiftformat${NC}"
fi

if command -v swiftlint &> /dev/null; then
    SWIFTLINT_AVAILABLE=true
else
    echo -e "${YELLOW}Warning: swiftlint not found. Install with: brew install swiftlint${NC}"
fi

FAILED=false

# Run SwiftFormat check
if [ "$SWIFTFORMAT_AVAILABLE" = true ]; then
    echo -e "${YELLOW}Running SwiftFormat check...${NC}"

    UNFORMATTED_FILES=""
    for FILE in $STAGED_FILES; do
        if [ -f "$FILE" ]; then
            if ! swiftformat --lint "$FILE" 2>/dev/null; then
                UNFORMATTED_FILES="$UNFORMATTED_FILES $FILE"
            fi
        fi
    done

    if [ -n "$UNFORMATTED_FILES" ]; then
        echo -e "${RED}The following files need formatting:${NC}"
        for FILE in $UNFORMATTED_FILES; do
            echo "  $FILE"
        done
        echo -e "${YELLOW}Run 'make format' to fix formatting${NC}"
        FAILED=true
    else
        echo -e "${GREEN}SwiftFormat check passed${NC}"
    fi
fi

# Run SwiftLint
if [ "$SWIFTLINT_AVAILABLE" = true ]; then
    echo -e "${YELLOW}Running SwiftLint...${NC}"

    LINT_ERRORS=false
    for FILE in $STAGED_FILES; do
        if [ -f "$FILE" ]; then
            if ! swiftlint lint --strict --quiet "$FILE" 2>/dev/null; then
                LINT_ERRORS=true
            fi
        fi
    done

    if [ "$LINT_ERRORS" = true ]; then
        echo -e "${RED}SwiftLint found issues. Run 'make lint' for details${NC}"
        FAILED=true
    else
        echo -e "${GREEN}SwiftLint check passed${NC}"
    fi
fi

if [ "$FAILED" = true ]; then
    echo -e "${RED}Pre-commit checks failed${NC}"
    exit 1
fi

echo -e "${GREEN}All pre-commit checks passed${NC}"
exit 0
