#!/bin/bash
# restore_yubikey.sh

set -e

BACKUP_DIR="./yubikey_backups"
RESTORE_DIR="/tmp/yubikey_restore_$$"

# Select backup file
echo "Available backups:"
ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | nl || {
    echo "No backups found in $BACKUP_DIR"
    exit 1
}

echo ""
read -p "Select backup number: " choice

BACKUP_FILE=$(ls -1 "$BACKUP_DIR"/*.tar.gz | sed -n "${choice}p")
[ -f "$BACKUP_FILE" ] || {
    echo "Invalid selection"
    exit 1
}

# Verify checksum
if [ -f "${BACKUP_FILE}.sha256" ]; then
    echo "Verifying checksum..."
    if sha256sum -c "${BACKUP_FILE}.sha256"; then
        echo "✓ Checksum verified"
    else
        echo "✗ Checksum verification failed!"
        read -p "Continue anyway? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi
fi

# Get YubiKey serial
read -p "Enter YubiKey serial (or press Enter to detect): " serial
if [ -z "$serial" ]; then
    serial=$(ykman list --serials | head -1)
    [ -n "$serial" ] || {
        echo "No YubiKey detected"
        exit 1
    }
fi

echo "Restoring to YubiKey: $serial"

# Extract backup
mkdir -p "$RESTORE_DIR"
tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"

# Restore slots
echo "Restoring PIV slots..."
for backup_file in "$RESTORE_DIR"/slot_*.json; do
    [ -f "$backup_file" ] || continue
    
    slot=$(basename "$backup_file" | sed 's/slot_\(.*\)\.json/\1/')
    echo "  Restoring slot $slot..."
    
    if ykman --device "$serial" piv objects import "$slot" "$backup_file"; then
        echo "    ✓ Restored"
    else
        echo "    ✗ Failed to restore"
    fi
done

# Cleanup
rm -rf "$RESTORE_DIR"

echo "Restore complete!"