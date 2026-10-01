#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# Visual log formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Configuration
WEBLATE_URL="http://localhost:4000/download/transport-fever-3/base/zh_Hant_HK/"
TARGET_DIR="$(pwd)/src/strings/zh_HK/LC_MESSAGES"

# Create a temporary working directory inside Linux's default temp folder (/tmp)
TEMP_DIR=$(mktemp -d -t tf3_build_XXXXXX)

# Ensure temporary files are cleaned up on script exit (even on errors)
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=========================================="
echo " Transport Fever 3 - Translation Builder"
echo "=========================================="

# Check for required tools
for cmd in curl msgattrib msgfmt; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required tool '$cmd' is not installed. Please install it to proceed."
        exit 1
    fi
done

# Step 1 & 2: Check Weblate connectivity and download the file
log_info "[Step 1/5] Checking connection to Weblate..."

# Check server reachability with a 3-second timeout
if ! curl -s --head --request GET "http://localhost:4000" --connect-timeout 3 > /dev/null; then
    log_error "Unable to connect to Weblate. Please ensure Weblate is running on http://localhost:4000."
    exit 1
fi

log_info "[Step 2/5] Downloading base file from Weblate..."
PO_TEMP="$TEMP_DIR/base.po"

if curl -s -f -o "$PO_TEMP" "$WEBLATE_URL"; then
    log_success "Downloaded PO file to temporary path."
else
    log_error "Failed to download the translation file from Weblate URL."
    exit 1
fi

# Step 3: Clear fuzzy translations
log_info "[Step 3/5] Removing fuzzy translation flags..."
PO_NO_FUZZY="$TEMP_DIR/base_clean.po"

msgattrib --clear-fuzzy "$PO_TEMP" -o "$PO_NO_FUZZY"
log_success "Fuzzy entries cleared."

# Step 4: Compile .po to .mo
log_info "[Step 4/5] Compiling PO file to MO binary format..."
MO_TEMP="$TEMP_DIR/base.mo"

msgfmt -o "$MO_TEMP" "$PO_NO_FUZZY"
log_success "Compiled successfully to MO format."

# Step 5: Move result to target destination
log_info "[Step 5/5] Deploying output file..."

if [ ! -d "$TARGET_DIR" ]; then
    log_info "Target directory does not exist. Creating: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

mv "$MO_TEMP" "$TARGET_DIR/base.mo"
log_success "File deployed to: $TARGET_DIR/base.mo"

echo "=========================================="
log_success "Build completed successfully!"
echo "=========================================="