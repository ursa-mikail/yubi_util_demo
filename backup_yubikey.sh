#!/bin/bash
# quick_backup_yubikey.sh

set -e

SERIAL=$(ykman list --serials | head -1)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./yubikey_backups"
BACKUP_FILE="${BACKUP_DIR}/yubikey_${SERIAL}_${TIMESTAMP}.tar.gz"
TEMP_DIR=$(mktemp -d)

echo "Backing up YubiKey: $SERIAL"
echo "Backup file: $BACKUP_FILE"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup slots 5FC101 to 5FC108
echo "Backing up PIV slots..."
for slot in 5FC101 5FC102 5FC103 5FC104 5FC105 5FC106 5FC107 5FC108; do
    OUTPUT_FILE="${TEMP_DIR}/slot_${slot}.json"
    if ykman --device "$SERIAL" piv objects export "$slot" "$OUTPUT_FILE" 2>/dev/null; then
        if [ -s "$OUTPUT_FILE" ]; then
            echo "  ✓ Slot $slot backed up"
        else
            rm -f "$OUTPUT_FILE"
        fi
    fi
done

# Create archive
echo "Creating archive..."
tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" .

# Cleanup
rm -rf "$TEMP_DIR"

# Create checksum
sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"

echo "Backup complete!"
echo "File: $BACKUP_FILE"
echo "Size: $(du -h "$BACKUP_FILE" | cut -f1)"