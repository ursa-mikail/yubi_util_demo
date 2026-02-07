# YubiKey PIV Manager
A comprehensive menu-driven shell script for managing YubiKey PIV (Personal Identity Verification) operations, including key share management using retired PIV slots.

# 📋 Overview
This script provides an interactive terminal interface for managing YubiKey PIV functionality, with special focus on using retired key slots (like 5FC108) for storing Shamir secret shares and other cryptographic objects.

# 🎯 Features
```
YubiKey Detection: List and select from multiple connected YubiKeys

PIV Management: Reset, configure, and manage PIV applets

Access Control: Change PIN, PUK, and management keys

Key Share Management: Import/export cryptographic shares to retired slots

Certificate Operations: Basic certificate management

Backup & Restore: Create and manage backups of PIV objects

Activity Logging: Comprehensive logging of all operations

User-Friendly: Color-coded menu system with confirmation prompts
```

# 🔧 Installation
Prerequisites
```
YubiKey Manager (ykman): Install from Yubico's official site

Bash shell (version 4.0+)

YubiKey with PIV support (4 series or later recommended)
```

# Setup
```bash
# Make it executable
chmod +x yubi_util_demo.sh

# Run the script
./yubi_util_demo.sh
```

# 📖 Understanding PIV Slots
## Standard PIV Slots

```text
9A          - PIV Authentication (Digital Signature)
9C          - Card Authentication (Physical Access)
9D          - Secure Messaging (Key Management)
9E          - Retired Key Management (Encryption)
```

## Retired Key Slots (for general/key storage)
These are additional slots for storing keys/certificates:

```text
5FC101 5FC102 5FC103 5FC104 5FC105 5FC106 5FC107 5FC108
5FC109 5FC10A 5FC10B 5FC10C 5FC10D 5FC10E 5FC10F 5FC110
5FC111 5FC112 5FC113 5FC114 5FC115 5FC116 5FC117 5FC118
5FC119 5FC11A 5FC11B 5FC11C 5FC11D 5FC11E 5FC11F

Total: 32 retired key slots (from 5FC101 to 5FC11F)
```

## Other Important Slots
```text
5FC120      - X.509 Certificate for PIV Authentication (9A)
5FC121      - X.509 Certificate for Digital Signature (9C)
5FC122      - X.509 Certificate for Key Management (9D)
5FC123      - X.509 Certificate for Card Authentication (9E)
5FC10A      - Biometric Information Template
5FFF10      - Discovery Object
5FFF11      - Key History Object
```

## 🚀 Usage
Main Menu Options
```
List YubiKeys: Show all connected YubiKeys with serial numbers

Show Information: Display detailed YubiKey and PIV information

Reset PIV Applet: ⚠️ WARNING: Deletes ALL PIV keys and certificates

Change Access Codes: Modify PIN, PUK, and management keys

Manage Key Shares: Import/export cryptographic shares to retired slots

Manage Certificates: Basic certificate operations

Backup & Restore: Create and manage backups

View Log: Check activity history

Exit: Close the application
```

## Key Share Management Example
The script supports storing Shamir secret shares in retired PIV slots:

```bash
# Import a key share to slot 5FC108
ykman --device <SERIAL> piv objects import 5FC108 ./shares/key_share_01.json

# Export a key share from slot 5FC108
ykman --device <SERIAL> piv objects export 5FC108 ./backup/key_share_01.json
```

## 🛡️ Security Best Practices
Slot Selection Strategy
```
Standard slots (9A, 9C, 9D, 9E): Use for their intended cryptographic purposes

Retired slots (5FC101-5FC11F): Ideal for custom applications like:

-Shamir secret shares
-Backup keys
-Custom cryptographic objects
-Application-specific data
```

Management Key Security
```
The management key (set via change-management-key) is required for import/export operations

Store management keys securely

Consider using the YubiKey's touch requirement for additional security
```

Operational Guidelines
```
Documentation: Keep track of which slots are used for which purposes

Testing: Always test operations on non-production YubiKeys first

Backups: Regularly backup important shares and certificates

Access Control: Limit physical access to YubiKeys with sensitive data
```

# 📝 Configuration
Default Settings
The script uses these default directories:
```
Backups: $HOME/yubikey_backups/

Key Shares: $HOME/yubikey_shares/

Logs: $HOME/yubikey_manager.log
```

## 🔍 Common Use Cases
Shamir Secret Sharing
Store cryptographic key shares across multiple YubiKeys for distributed security:

bash
# Distribute shares across different slots
./yubi_util_demo.sh
# Select "Manage Key Shares"
# Import different shares to different slots (5FC101, 5FC102, etc.)

## Multi-Factor Authentication Setup
Configure standard PIV slots for various authentication scenarios:
```
9A: Login authentication

9C: Physical access control

9D: Secure email encryption
```

## Key Backup and Recovery
Use retired slots to store backup keys that can be restored if primary keys are lost.

⚠️ Important Warnings
```
PIV Reset: The "Reset PIV Applet" option will permanently delete all PIV data

Management Key: Losing the management key may render YubiKey slots inaccessible

PIN Attempts: Multiple failed PIN attempts will lock the YubiKey (use PUK to unlock)

PUK Attempts: Multiple failed PUK attempts will permanently block the YubiKey
```

🐛 Troubleshooting
Common Issues
1. "No YubiKeys found"

Ensure YubiKey is properly inserted

Check lsusb or system_profiler SPUSBDataType (macOS) to confirm detection

Reinstall ykman if necessary

2. "Permission denied" errors

Run with appropriate permissions: sudo ./yubi_util_demo.sh

Check udev rules on Linux systems

3. Import/export failures

Verify the management key is correct

Check slot availability (not already occupied)

Ensure file permissions allow reading/writing

## Logs
Check the log file for detailed error information:

```bash
tail -f ./yubikey_manager.log
```

🔄 Integration Examples
With Shamir's Secret Sharing
bash
# Generate shares
ssss-split -t 3 -n 5 -s "my-secret-key"

# Store shares on different YubiKeys
for i in {1..5}; do
    ykman --device <SERIAL_$i> piv objects import 5FC101 share_$i.txt
done

# Automated Backup Script
```bash
#!/bin/bash
# backup_yubikey.sh
SERIAL=$(ykman list --serials | head -1)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/secure/backups/yubikey_${SERIAL}_${TIMESTAMP}.tar"

# Backup all retired slots
for slot in {5FC101..5FC108}; do
    ykman --device $SERIAL piv objects export $slot /tmp/share_$slot.json 2>/dev/null
done

tar -cf $BACKUP_FILE /tmp/share_*.json
rm /tmp/share_*.json
```
```
# Make scripts executable
chmod +x backup_yubikey.sh restore_yubikey.sh

# Run backup
./backup_yubikey.sh

# List backups
ls -la ./secure/backups/

# Restore
./restore_yubikey.sh
```

"""
yubi_util_demo % echo "my-test-secret" | ssss-split -t 2 -n 3 -q | ssss-combine -t 2 -q
> my-test-secret
"""
