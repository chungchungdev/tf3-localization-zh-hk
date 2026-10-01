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

APP_ID="3493540"
STAGING_FOLDER_NAME="tf3_chungchungdev_localization_zh_hk"
SOURCE_DIR="$(pwd)/src"

echo "=========================================="
echo " Transport Fever 3 - Localization Deployer"
echo "=========================================="

# Ensure required commands exist
for cmd in zip rsync; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required tool '$cmd' is not installed. Please install it first."
        exit 1
    fi
done

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    log_error "Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

# Step 1: Find Steam installation path
log_info "[Step 1/5] Detecting Steam installation path..."

STEAM_PATH=""
POSSIBLE_PATHS=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.steam/root"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" # Flatpak installation
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path/userdata" ]; then
        STEAM_PATH="$path"
        break
    fi
done

if [ -z "$STEAM_PATH" ]; then
    log_error "Could not locate Steam installation directory with a valid 'userdata' folder."
    exit 1
fi

log_success "Found Steam path: $STEAM_PATH"

# Step 2: Find Steam user IDs and handle selection
log_info "[Step 2/5] Scanning for Steam User IDs..."

USERDATA_DIR="$STEAM_PATH/userdata"
mapfile -t USER_IDS < <(find "$USERDATA_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | grep -E '^[0-9]+$' | sort -u)

if [ ${#USER_IDS[@]} -eq 0 ]; then
    log_error "No Steam user profiles found under $USERDATA_DIR."
    exit 1
fi

SELECTED_USER_ID=""

if [ ${#USER_IDS[@]} -eq 1 ]; then
    SELECTED_USER_ID="${USER_IDS[0]}"
    log_info "Single Steam User ID detected: $SELECTED_USER_ID. Auto-selecting."
else
    log_warn "Multiple Steam User IDs found. Please choose one:"
    select uid in "${USER_IDS[@]}"; do
        if [ -n "$uid" ]; then
            SELECTED_USER_ID="$uid"
            break
        else
            echo "Invalid selection. Please enter a valid number."
        fi
    done
fi

log_success "Selected Steam User ID: $SELECTED_USER_ID"

# Step 3: Create target_path
log_info "[Step 3/5] Resolving target directory..."
TARGET_PATH="$STEAM_PATH/userdata/$SELECTED_USER_ID/$APP_ID/local/staging_area/$STAGING_FOLDER_NAME"

log_info "Target Path: $TARGET_PATH"

# Step 4: Backup existing files and clean directory
log_info "[Step 4/5] Checking for existing files in target directory..."

if [ -d "$TARGET_PATH" ] && [ -n "$(ls -A "$TARGET_PATH")" ]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="${TARGET_PATH}_backup_${TIMESTAMP}.zip"

    log_warn "Existing files found. Creating backup: $BACKUP_FILE"
    
    # Create zip from inside target_path to keep internal structure relative
    (cd "$TARGET_PATH" && zip -r -q "$BACKUP_FILE" .)
    log_success "Backup created successfully."

    log_info "Cleaning target directory..."
    rm -rf "${TARGET_PATH:?}"/*
    log_success "Target directory cleaned."
else
    log_info "Target directory is clear or empty. Creating structure if missing..."
    mkdir -p "$TARGET_PATH"
fi

# Step 5: Copy files from <cwd>/src/ to target_path
log_info "[Step 5/5] Deploying files from $SOURCE_DIR to $TARGET_PATH..."

# Use rsync to safely transfer files with permissions intact
rsync -av --progress "$SOURCE_DIR/" "$TARGET_PATH/"

log_success "Files successfully copied to deployment target."

echo "=========================================="
log_success "Deployment completed successfully!"
echo "=========================================="