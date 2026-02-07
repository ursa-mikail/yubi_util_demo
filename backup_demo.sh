#!/bin/bash
# backup_yubikey.sh - Backup YubiKey PIV objects from retired slots
# Author: YubiKey Manager
# Version: 1.0

set -e  # Exit on error

# Configuration
BACKUP_DIR="./secure/backups"
TEMP_DIR="/tmp/yubikey_backup_$$"  # Use PID for uniqueness
LOG_FILE="./backup_yubikey.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up temporary directory: $TEMP_DIR"
    fi
}

# Error handler
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    log "ERROR: $1"
    cleanup
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check ykman
    if ! command -v ykman &> /dev/null; then
        error_exit "ykman not found. Please install YubiKey Manager first."
    fi
    
    # Check if any YubiKey is connected
    if ! ykman list --serials &> /dev/null; then
        error_exit "No YubiKey detected. Please insert a YubiKey."
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR" || error_exit "Cannot create backup directory: $BACKUP_DIR"
    
    # Create temp directory
    mkdir -p "$TEMP_DIR" || error_exit "Cannot create temporary directory: $TEMP_DIR"
    
    log "Prerequisites check passed"
}

# Get YubiKey serial
get_yubikey_serial() {
    local serials
    serials=$(ykman list --serials 2>/dev/null)
    
    if [ -z "$serials" ]; then
        error_exit "No YubiKey serial numbers found"
    fi
    
    # Count YubiKeys
    local count
    count=$(echo "$serials" | wc -l | tr -d ' ')
    
    if [ "$count" -eq 1 ]; then
        # Single YubiKey
        SERIAL="$serials"
        log "Found single YubiKey: $SERIAL"
    else
        # Multiple YubiKeys - prompt user
        echo -e "${YELLOW}Multiple YubiKeys detected:${NC}"
        echo "$serials" | nl
        echo ""
        read -p "Select YubiKey number (1-$count): " selection
        
        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
            error_exit "Invalid selection"
        fi
        
        SERIAL=$(echo "$serials" | sed -n "${selection}p")
        log "Selected YubiKey $selection: $SERIAL"
    fi
}

# Backup PIV slots
backup_piv_slots() {
    local slots=("5FC101" "5FC102" "5FC103" "5FC104" "5FC105" "5FC106" "5FC107" "5FC108")
    local backed_up=0
    local total_slots=${#slots[@]}
    
    log "Starting backup of $total_slots slots from YubiKey $SERIAL"
    
    for slot in "${slots[@]}"; do
        local output_file="$TEMP_DIR/slot_${slot}.json"
        log "Checking slot $slot..."
        
        # Try to export from slot
        if ykman --device "$SERIAL" piv objects export "$slot" "$output_file" 2>/dev/null; then
            # Check if file has content (not empty)
            if [ -s "$output_file" ]; then
                ((backed_up++))
                log "  ✓ Backed up slot $slot"
                
                # Add metadata to the file
                add_metadata "$output_file" "$slot"
            else
                rm -f "$output_file"
                log "  ○ Slot $slot is empty"
            fi
        else
            log "  ○ Slot $slot not accessible or empty"
        fi
    done
    
    log "Successfully backed up $backed_up of $total_slots slots"
    
    if [ "$backed_up" -eq 0 ]; then
        echo -e "${YELLOW}Warning: No data found in any slot${NC}"
        log "Warning: No data found in any slot"
    fi
}

# Add metadata to backup files
add_metadata() {
    local file="$1"
    local slot="$2"
    local temp_file="${file}.tmp"
    
    # If it's already JSON, update it
    if head -c 1 "$file" | grep -q '{'; then
        # It's JSON, add/update metadata
        jq --arg slot "$slot" \
           --arg serial "$SERIAL" \
           --arg timestamp "$(date -Iseconds)" \
           '.metadata = (.metadata // {}) | .metadata.backup_timestamp = $timestamp | .metadata.slot = $slot | .metadata.serial = $serial' \
           "$file" > "$temp_file" && mv "$temp_file" "$file" 2>/dev/null || true
    else
        # It's raw data, wrap it in JSON
        local data
        data=$(cat "$file")
        cat > "$temp_file" << EOF
{
  "slot": "$slot",
  "serial": "$SERIAL",
  "backup_timestamp": "$(date -Iseconds)",
  "data": "$(echo "$data" | base64 | tr -d '\n')",
  "data_encoding": "base64",
  "metadata": {
    "original_format": "raw",
    "backup_version": "1.0"
  }
}
EOF
        mv "$temp_file" "$file"
    fi
}

# Create backup archive
create_backup_archive() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/yubikey_${SERIAL}_${timestamp}.tar.gz"
    
    log "Creating backup archive: $backup_file"
    
    # Create manifest file
    create_manifest "$backup_file"
    
    # Create tar.gz archive
    if tar -czf "$backup_file" -C "$TEMP_DIR" .; then
        # Calculate checksum
        local checksum
        checksum=$(sha256sum "$backup_file" | cut -d' ' -f1)
        
        # Save checksum
        echo "$checksum  $(basename "$backup_file")" > "${backup_file}.sha256"
        
        # Display summary
        local size
        size=$(du -h "$backup_file" | cut -f1)
        
        echo -e "${GREEN}✓ Backup completed successfully!${NC}"
        echo "  Backup file: $backup_file"
        echo "  Size: $size"
        echo "  SHA256: $checksum"
        echo "  Checksum file: ${backup_file}.sha256"
        
        log "Backup created: $backup_file (Size: $size, SHA256: $checksum)"
    else
        error_exit "Failed to create backup archive"
    fi
}

# Create manifest file
create_manifest() {
    local backup_file="$1"
    local manifest_file="$TEMP_DIR/MANIFEST.txt"
    
    cat > "$manifest_file" << EOF
YubiKey Backup Manifest
=======================
Backup Date: $(date)
YubiKey Serial: $SERIAL
Backup File: $(basename "$backup_file")
Created By: $USER
Hostname: $(hostname)

Contents:
$(ls -la "$TEMP_DIR" | tail -n +2)

Slot Status:
$(for slot in 5FC101 5FC102 5FC103 5FC104 5FC105 5FC106 5FC107 5FC108; do
    if [ -f "$TEMP_DIR/slot_${slot}.json" ]; then
        echo "✓ $slot: Backed up"
    else
        echo "○ $slot: Empty or not accessible"
    fi
done)

EOF
}

# Verify backup
verify_backup() {
    local latest_backup
    latest_backup=$(ls -t "${BACKUP_DIR}/yubikey_${SERIAL}_"*.tar.gz 2>/dev/null | head -1)
    
    if [ -n "$latest_backup" ] && [ -f "${latest_backup}.sha256" ]; then
        log "Verifying latest backup: $(basename "$latest_backup")"
        
        if sha256sum -c "${latest_backup}.sha256" &> /dev/null; then
            log "✓ Backup verification successful"
            echo -e "${GREEN}✓ Backup verification successful${NC}"
        else
            log "✗ Backup verification failed!"
            echo -e "${RED}✗ Backup verification failed!${NC}"
            return 1
        fi
    fi
    return 0
}

# Main execution
main() {
    echo -e "${YELLOW}=== YubiKey Backup Utility ===${NC}"
    echo ""
    
    # Initialize
    check_prerequisites
    get_yubikey_serial
    
    # Perform backup
    backup_piv_slots
    
    # Create archive
    create_backup_archive
    
    # Verify backup
    verify_backup
    
    # Cleanup
    cleanup
    
    echo ""
    echo -e "${GREEN}Backup process completed!${NC}"
    log "Backup process completed successfully"
}

# Trap signals for cleanup
trap cleanup EXIT INT TERM

# Run main function
main