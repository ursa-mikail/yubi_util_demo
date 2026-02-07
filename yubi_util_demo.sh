#!/bin/bash

# YubiKey PIV Manager
# A comprehensive menu-driven utility for YubiKey PIV operations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="./yubikey_backups"
SHARES_DIR="./yubikey_shares"
LOG_FILE="./yubikey_manager.log"
DEFAULT_SLOTS=("5FC101" "5FC102" "5FC103" "5FC104" "5FC105" "5FC106" "5FC107" "5FC108")

# Check if ykman is installed
check_dependencies() {
    if ! command -v ykman &> /dev/null; then
        echo -e "${RED}Error: ykman (YubiKey Manager) is not installed.${NC}"
        echo "Please install it from: https://developers.yubico.com/yubikey-manager/"
        exit 1
    fi
}

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Display banner
show_banner() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}    YubiKey PIV Manager v1.0${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# List connected YubiKeys
list_yubikeys() {
    echo -e "${YELLOW}Scanning for YubiKeys...${NC}"
    echo ""
    
    local serials=$(ykman list --serials 2>/dev/null)
    
    if [ -z "$serials" ]; then
        echo -e "${RED}No YubiKeys found!${NC}"
        echo "Please insert a YubiKey and try again."
        return 1
    fi
    
    echo -e "${GREEN}Found YubiKeys:${NC}"
    IFS=$'\n'
    local count=1
    for serial in $serials; do
        echo -e "${BLUE}$count.${NC} Serial: $serial"
        # Get basic info
        local info=$(ykman --device "$serial" info 2>/dev/null | head -10)
        echo "   $(echo "$info" | grep -E "Device|Version" | head -2 | sed 's/^/   /')"
        ((count++))
    done
    unset IFS
    
    echo ""
    return 0
}

# Select a YubiKey
select_yubikey() {
    local serials=$(ykman list --serials 2>/dev/null)
    
    if [ -z "$serials" ]; then
        echo -e "${RED}No YubiKeys found!${NC}"
        return ""
    fi
    
    echo -e "${YELLOW}Select a YubiKey:${NC}"
    
    IFS=$'\n'
    local options=()
    local count=1
    
    for serial in $serials; do
        echo "$count. Serial: $serial"
        options+=("$serial")
        ((count++))
    done
    unset IFS
    
    echo -n "Enter selection (1-${#options[@]}): "
    read choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        selected_serial="${options[$((choice-1))]}"
        echo -e "${GREEN}Selected YubiKey: $selected_serial${NC}"
        return 0
    else
        echo -e "${RED}Invalid selection!${NC}"
        return 1
    fi
}

# Reset PIV applet
reset_piv() {
    show_banner
    echo -e "${YELLOW}=== Reset PIV Applet ===${NC}"
    echo ""
    echo -e "${RED}WARNING: This will delete ALL PIV keys and certificates!${NC}"
    echo "This action cannot be undone."
    echo ""
    
    if ! select_yubikey; then
        return
    fi
    
    echo ""
    read -p "Are you sure you want to reset PIV on YubiKey $selected_serial? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Resetting PIV...${NC}"
        if ykman --device "$selected_serial" piv reset --force; then
            log "Reset PIV on YubiKey $selected_serial"
            echo -e "${GREEN}PIV reset successful!${NC}"
        else
            log "Failed to reset PIV on YubiKey $selected_serial"
            echo -e "${RED}PIV reset failed!${NC}"
        fi
    else
        echo "Reset cancelled."
    fi
    read -p "Press Enter to continue..."
}

# Change PIN/PUK/Management Key
change_access_codes() {
    show_banner
    echo -e "${YELLOW}=== Change Access Codes ===${NC}"
    echo ""
    
    if ! select_yubikey; then
        return
    fi
    
    while true; do
        show_banner
        echo -e "${YELLOW}Access Codes for YubiKey: $selected_serial${NC}"
        echo ""
        echo "1. Change PIN (6-8 digits, default: 123456)"
        echo "2. Change PUK (6-8 digits, default: 12345678)"
        echo "3. Change Management Key (48 hex chars)"
        echo "4. Back to main menu"
        echo ""
        read -p "Select option: " choice
        
        case $choice in
            1)
                echo -e "${YELLOW}Changing PIN...${NC}"
                ykman --device "$selected_serial" piv access change-pin
                log "Changed PIN on YubiKey $selected_serial"
                read -p "Press Enter to continue..."
                ;;
            2)
                echo -e "${YELLOW}Changing PUK...${NC}"
                ykman --device "$selected_serial" piv access change-puk
                log "Changed PUK on YubiKey $selected_serial"
                read -p "Press Enter to continue..."
                ;;
            3)
                echo -e "${YELLOW}Changing Management Key...${NC}"
                echo "Options:"
                echo "  1. Generate random key"
                echo "  2. Enter custom key"
                read -p "Select: " key_choice
                
                if [ "$key_choice" == "1" ]; then
                    # Generate random management key
                    openssl rand -hex 24 | ykman --device "$selected_serial" piv access change-management-key -m 010203040506070801020304050607080102030405060708 --new-key-mgm -
                    log "Changed Management Key (random) on YubiKey $selected_serial"
                else
                    ykman --device "$selected_serial" piv access change-management-key
                    log "Changed Management Key (manual) on YubiKey $selected_serial"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                break
                ;;
            *)
                echo -e "${RED}Invalid option!${NC}"
                ;;
        esac
    done
}

# Import/Export key shares
manage_key_shares() {
    show_banner
    echo -e "${YELLOW}=== Manage Key Shares ===${NC}"
    echo ""
    
    if ! select_yubikey; then
        return
    fi
    
    mkdir -p "$SHARES_DIR"
    
    while true; do
        show_banner
        echo -e "${YELLOW}Key Share Management for YubiKey: $selected_serial${NC}"
        echo ""
        echo "1. Import key share to slot"
        echo "2. Export key share from slot"
        echo "3. List all slots with content"
        echo "4. Generate test key shares"
        echo "5. Back to main menu"
        echo ""
        read -p "Select option: " choice
        
        case $choice in
            1)
                echo -e "${YELLOW}Available slots:${NC}"
                for slot in "${DEFAULT_SLOTS[@]}"; do
                    echo "  $slot"
                done
                echo ""
                read -p "Enter slot (e.g., 5FC108): " slot
                read -p "Enter path to key share file: " share_file
                
                if [ -f "$share_file" ]; then
                    echo -e "${YELLOW}Importing to slot $slot...${NC}"
                    if ykman --device "$selected_serial" piv objects import "$slot" "$share_file"; then
                        log "Imported key share to $slot on YubiKey $selected_serial"
                        echo -e "${GREEN}Import successful!${NC}"
                    else
                        echo -e "${RED}Import failed!${NC}"
                    fi
                else
                    echo -e "${RED}File not found: $share_file${NC}"
                fi
                read -p "Press Enter to continue..."
                ;;
            2)
                echo -e "${YELLOW}Available slots:${NC}"
                for slot in "${DEFAULT_SLOTS[@]}"; do
                    echo "  $slot"
                done
                echo ""
                read -p "Enter slot (e.g., 5FC108): " slot
                read -p "Enter output filename: " output_file
                
                echo -e "${YELLOW}Exporting from slot $slot...${NC}"
                mkdir -p "$(dirname "$output_file")"
                if ykman --device "$selected_serial" piv objects export "$slot" "$output_file"; then
                    log "Exported key share from $slot on YubiKey $selected_serial to $output_file"
                    echo -e "${GREEN}Export successful!${NC}"
                    echo "Saved to: $output_file"
                else
                    echo -e "${RED}Export failed!${NC}"
                fi
                read -p "Press Enter to continue..."
                ;;
            3)
                echo -e "${YELLOW}Checking slot contents...${NC}"
                echo ""
                for slot in "${DEFAULT_SLOTS[@]}"; do
                    echo -n "Slot $slot: "
                    if ykman --device "$selected_serial" piv objects export "$slot" /dev/null 2>/dev/null; then
                        echo -e "${GREEN}Contains data${NC}"
                    else
                        echo "Empty"
                    fi
                done
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                echo -e "${YELLOW}Generating test key shares...${NC}"
                echo "This creates sample JSON files for testing."
                echo ""
                read -p "How many shares to generate? " num_shares
                
                for ((i=1; i<=num_shares; i++)); do
                    share_file="$SHARES_DIR/key_share_$(printf "%02d" $i).json"
                    cat > "$share_file" << EOF
{
  "share_id": "$(printf "%02d" $i)",
  "yubikey_serial": "$selected_serial",
  "slot": "${DEFAULT_SLOTS[$((i-1))]}",
  "timestamp": "$(date -Iseconds)",
  "data": "$(openssl rand -base64 32)",
  "metadata": {
    "purpose": "test_share",
    "threshold": 3,
    "total_shares": $num_shares
  }
}
EOF
                    echo "Generated: $share_file"
                done
                echo -e "${GREEN}Generated $num_shares test shares in $SHARES_DIR${NC}"
                read -p "Press Enter to continue..."
                ;;
            5)
                break
                ;;
            *)
                echo -e "${RED}Invalid option!${NC}"
                ;;
        esac
    done
}

# Generate and manage certificates
manage_certificates() {
    show_banner
    echo -e "${YELLOW}=== Certificate Management ===${NC}"
    echo ""
    
    if ! select_yubikey; then
        return
    fi
    
    while true; do
        show_banner
        echo -e "${YELLOW}Certificate Management for YubiKey: $selected_serial${NC}"
        echo ""
        echo "1. Generate self-signed certificate"
        echo "2. Generate CSR (Certificate Signing Request)"
        echo "3. Import certificate"
        echo "4. List certificates"
        echo "5. Back to main menu"
        echo ""
        read -p "Select option: " choice
        
        case $choice in
            1)
                echo -e "${YELLOW}Available slots:${NC}"
                echo "  9A - PIV Authentication"
                echo "  9C - Card Authentication"
                echo "  9D - Secure Messaging"
                echo "  9E - Retired Key Management"
                echo ""
                read -p "Enter slot (9A, 9C, 9D, 9E): " slot
                read -p "Enter subject (e.g., /CN=John Doe/OU=Security/O=Company): " subject
                
                echo -e "${YELLOW}Generating key and certificate...${NC}"
                # This is a simplified example - real implementation would be more complex
                echo "Note: Actual certificate generation requires more steps"
                echo "Consider using: ykman piv keys generate $slot public.pem"
                echo "              && ykman piv certificates generate $slot public.pem --subject '$subject'"
                read -p "Press Enter to continue..."
                ;;
            4)
                echo -e "${YELLOW}Certificate slots:${NC}"
                echo ""
                for slot in "9A" "9C" "9D" "9E"; do
                    echo -n "Slot $slot: "
                    if ykman --device "$selected_serial" piv certificates export "$slot" /dev/null 2>/dev/null; then
                        echo -e "${GREEN}Certificate present${NC}"
                    else
                        echo "No certificate"
                    fi
                done
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                break
                ;;
            *)
                echo -e "${RED}Invalid option!${NC}"
                ;;
        esac
    done
}

# Backup and restore
backup_restore() {
    show_banner
    echo -e "${YELLOW}=== Backup & Restore ===${NC}"
    echo ""
    
    mkdir -p "$BACKUP_DIR"
    
    echo "1. Create backup of PIV objects"
    echo "2. Restore PIV objects from backup"
    echo "3. List backups"
    echo "4. Back to main menu"
    echo ""
    read -p "Select option: " choice
    
    case $choice in
        1)
            if ! select_yubikey; then
                return
            fi
            
            backup_file="$BACKUP_DIR/yubikey_${selected_serial}_$(date +%Y%m%d_%H%M%S).tar.gz"
            temp_dir=$(mktemp -d)
            
            echo -e "${YELLOW}Creating backup...${NC}"
            
            # Backup key shares
            mkdir -p "$temp_dir/shares"
            for slot in "${DEFAULT_SLOTS[@]}"; do
                if ykman --device "$selected_serial" piv objects export "$slot" /dev/null 2>/dev/null; then
                    ykman --device "$selected_serial" piv objects export "$slot" "$temp_dir/shares/share_$slot.json" 2>/dev/null
                fi
            done
            
            # Backup info
            ykman --device "$selected_serial" info > "$temp_dir/device_info.txt" 2>&1
            ykman --device "$selected_serial" piv info > "$temp_dir/piv_info.txt" 2>&1
            
            # Create archive
            tar -czf "$backup_file" -C "$temp_dir" .
            rm -rf "$temp_dir"
            
            log "Created backup: $backup_file"
            echo -e "${GREEN}Backup created: $backup_file${NC}"
            read -p "Press Enter to continue..."
            ;;
        2)
            echo -e "${RED}Warning: Restore functionality is complex${NC}"
            echo "Due to security constraints, direct restore isn't trivial."
            echo "Please use individual import commands instead."
            read -p "Press Enter to continue..."
            ;;
        3)
            echo -e "${YELLOW}Available backups:${NC}"
            echo ""
            if [ -d "$BACKUP_DIR" ]; then
                ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found"
            else
                echo "No backups found"
            fi
            echo ""
            read -p "Press Enter to continue..."
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}Invalid option!${NC}"
            ;;
    esac
}

# Show YubiKey info
show_info() {
    show_banner
    echo -e "${YELLOW}=== YubiKey Information ===${NC}"
    echo ""
    
    if ! list_yubikeys; then
        read -p "Press Enter to continue..."
        return
    fi
    
    echo ""
    if select_yubikey; then
        echo ""
        echo -e "${YELLOW}Detailed Information:${NC}"
        echo "----------------------------------------"
        ykman --device "$selected_serial" info
        echo ""
        echo -e "${YELLOW}PIV Information:${NC}"
        echo "----------------------------------------"
        ykman --device "$selected_serial" piv info
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Main menu
main_menu() {
    while true; do
        show_banner
        echo -e "${GREEN}Main Menu${NC}"
        echo ""
        echo "1. List YubiKeys"
        echo "2. Show YubiKey Information"
        echo "3. Reset PIV Applet"
        echo "4. Change PIN/PUK/Management Key"
        echo "5. Manage Key Shares (Import/Export)"
        echo "6. Manage Certificates"
        echo "7. Backup & Restore"
        echo "8. View Log"
        echo "9. Exit"
        echo ""
        read -p "Select option: " choice
        
        case $choice in
            1)
                show_banner
                list_yubikeys
                read -p "Press Enter to continue..."
                ;;
            2)
                show_info
                ;;
            3)
                reset_piv
                ;;
            4)
                change_access_codes
                ;;
            5)
                manage_key_shares
                ;;
            6)
                manage_certificates
                ;;
            7)
                backup_restore
                ;;
            8)
                show_banner
                echo -e "${YELLOW}=== Activity Log ===${NC}"
                echo ""
                if [ -f "$LOG_FILE" ]; then
                    tail -50 "$LOG_FILE"
                else
                    echo "Log file empty or not created yet."
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            9)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Initialize
init() {
    check_dependencies
    mkdir -p "$BACKUP_DIR" "$SHARES_DIR"
    touch "$LOG_FILE"
    log "=== YubiKey Manager started ==="
}

# Run
init
main_menu