#!/bin/bash

# RAID Setup Script - Improved Version
# This script automates RAID array creation with enhanced error handling and validation

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Configuration
RAID_DEVICE="/dev/md0"
MDADM_CONF="/etc/mdadm/mdadm.conf"
LOG_FILE="/var/log/raid_setup_$(date +%Y%m%d_%H%M%S).log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "❌ ERROR: $1"
    exit 1
}

# Cleanup function for graceful exit
cleanup() {
    log "🧹 Performing cleanup..."
    # Any cleanup tasks can go here
}
trap cleanup EXIT

echo "========== RAID Setup Script (Improved) =========="
log "Script started by user: $(whoami)"

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root"
fi

# Check for required commands
REQUIRED_COMMANDS=("mdadm" "lsblk" "blkid" "mkfs.ext4" "wipefs")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        error_exit "Required command '$cmd' not found. Please install it first."
    fi
done

# Create mdadm config directory if it doesn't exist
mkdir -p "$(dirname "$MDADM_CONF")"

# Function to validate RAID level
validate_raid_level() {
    local level="$1"
    case "$level" in
        0|1|5|6|10) return 0 ;;
        *) return 1 ;;
    esac
}

# Function to get minimum disks for RAID level
get_min_disks() {
    case "$1" in
        0|1)  echo 2 ;;
        5)    echo 3 ;;
        6|10) echo 4 ;;
    esac
}

# Function to check if device is safe to use
check_device_safety() {
    local device="$1"
    
    # Check if device exists
    if [[ ! -b "$device" ]]; then
        error_exit "$device is not a valid block device"
    fi
    
    # Check if device is mounted
    if mount | grep -q "^$device"; then
        log "⚠️  $device is currently mounted"
        return 1
    fi
    
    # Check for existing filesystem
    if blkid "$device" &>/dev/null; then
        log "⚠️  $device contains an existing filesystem"
        return 1
    fi
    
    # Check if device is part of existing RAID
    if mdadm --examine "$device" &>/dev/null; then
        log "⚠️  $device has RAID signatures"
        return 1
    fi
    
    return 0
}

# Function to clean device
clean_device() {
    local device="$1"
    log "🧼 Cleaning device $device..."
    
    # Unmount all partitions
    for partition in "${device}"*; do
        if [[ "$partition" != "$device" ]] && mount | grep -q "^$partition"; then
            log "📤 Unmounting $partition..."
            umount "$partition" 2>/dev/null || umount -l "$partition" || true
        fi
    done
    
    # Zero RAID superblock
    mdadm --zero-superblock --force "$device" 2>/dev/null || true
    
    # Wipe filesystem signatures
    wipefs -a "$device" 2>/dev/null || true
    
    # Clear partition table
    dd if=/dev/zero of="$device" bs=1M count=10 2>/dev/null || true
    
    log "✅ Device $device cleaned"
}

# Ask for RAID level with validation
while true; do
    read -p "Enter RAID level (0, 1, 5, 6, 10): " RAID_LEVEL
    if validate_raid_level "$RAID_LEVEL"; then
        break
    else
        echo "❌ Invalid RAID level. Please enter 0, 1, 5, 6, or 10."
    fi
done

MIN_DISKS=$(get_min_disks "$RAID_LEVEL")
log "Selected RAID level: $RAID_LEVEL (minimum $MIN_DISKS disks required)"

# Ask for number of disks with validation
while true; do
    read -p "How many disks do you want to use? (Minimum $MIN_DISKS): " NUM_DISKS
    if [[ "$NUM_DISKS" =~ ^[0-9]+$ ]] && (( NUM_DISKS >= MIN_DISKS )); then
        break
    else
        echo "❌ Please enter a number >= $MIN_DISKS"
    fi
done

# Clean up existing RAID device
if [ -e "$RAID_DEVICE" ]; then
    log "🧹 Cleaning up existing $RAID_DEVICE..."
    
    # Check if mounted and unmount
    if mount | grep -q "^$RAID_DEVICE"; then
        MOUNTED_AT=$(mount | grep "^$RAID_DEVICE" | awk '{print $3}')
        log "📤 Unmounting $RAID_DEVICE from $MOUNTED_AT..."
        umount "$RAID_DEVICE" || umount -l "$RAID_DEVICE" || error_exit "Failed to unmount $RAID_DEVICE"
    fi
    
    # Stop RAID array if active
    if grep -q "$(basename "$RAID_DEVICE")" /proc/mdstat 2>/dev/null; then
        log "🛑 Stopping RAID array $RAID_DEVICE..."
        mdadm --stop "$RAID_DEVICE" || error_exit "Failed to stop RAID array"
        sleep 2
    fi
    
    # Remove device node
    if [ -e "$RAID_DEVICE" ]; then
        log "🗑️  Removing device node $RAID_DEVICE..."
        mdadm --remove "$RAID_DEVICE" 2>/dev/null || true
    fi
fi

# Show available disks
log "🔍 Scanning available disks..."
echo -e "\n🔍 Available Disks:"
declare -A DISK_INFO
while IFS= read -r line; do
    device=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    
    # Skip if device doesn't exist
    [[ ! -b "$device" ]] && continue
    
    # Check device status
    status="✅"
    warnings=""
    
    if mount | grep -q "^$device"; then
        status="⚠️ "
        warnings+="[MOUNTED] "
    fi
    
    if blkid "$device" &>/dev/null; then
        status="⚠️ "
        warnings+="[HAS_FS] "
    fi
    
    if mdadm --examine "$device" &>/dev/null; then
        status="⚠️ "
        warnings+="[RAID_SIG] "
    fi
    
    echo "$status $device ($size) $warnings"
    DISK_INFO["$device"]="$size"
done < <(lsblk -dpno NAME,SIZE,TYPE | grep -E "disk")

# Collect disk selections
echo
log "Collecting disk selections..."
DISKS=()
for (( i=1; i<=NUM_DISKS; i++ )); do
    while true; do
        read -p "Disk $i: " disk
        
        # Trim whitespace
        disk=$(echo "$disk" | xargs)
        
        # Validate device
        if [[ ! -b "$disk" ]]; then
            echo "❌ $disk is not a valid block device"
            continue
        fi
        
        # Check if already selected
        if [[ " ${DISKS[*]} " =~ " $disk " ]]; then
            echo "❌ $disk already selected"
            continue
        fi
        
        # Add to array
        DISKS+=("$disk")
        log "Selected disk $i: $disk"
        break
    done
done

# Show final selection and get confirmation
echo
log "Final disk selection: ${DISKS[*]}"
echo "You selected the following disks for RAID $RAID_LEVEL:"
for i in "${!DISKS[@]}"; do
    disk="${DISKS[$i]}"
    size="${DISK_INFO[$disk]:-unknown}"
    echo "  $(($i + 1)). $disk ($size)"
done

echo
echo "❗ WARNING: This will COMPLETELY ERASE all data on the selected disks!"
echo "❗ This action is IRREVERSIBLE!"
echo
read -p "Type 'YES' to continue (case sensitive): " confirm
[[ "$confirm" != "YES" ]] && error_exit "Operation cancelled by user"

# Clean all selected disks
log "🧼 Cleaning selected disks..."
for disk in "${DISKS[@]}"; do
    clean_device "$disk"
done

# Verify devices are clean
log "🔍 Verifying devices are clean..."
for disk in "${DISKS[@]}"; do
    if ! check_device_safety "$disk"; then
        error_exit "Device $disk is not safe to use after cleaning"
    fi
done

# Create RAID array
log "🚧 Creating RAID $RAID_LEVEL array on $RAID_DEVICE..."
if ! mdadm --create "$RAID_DEVICE" \
    --level="$RAID_LEVEL" \
    --raid-devices="$NUM_DISKS" \
    "${DISKS[@]}" \
    --verbose; then
    error_exit "Failed to create RAID array"
fi

sleep 3

# Wait for array to be active
log "⏳ Waiting for RAID array to become active..."
timeout=60
while [ $timeout -gt 0 ]; do
    if [ -b "$RAID_DEVICE" ] && mdadm --detail "$RAID_DEVICE" &>/dev/null; then
        break
    fi
    sleep 1
    ((timeout--))
done

if [ $timeout -eq 0 ]; then
    error_exit "RAID array did not become active within 60 seconds"
fi

# Show initial status
log "📊 Initial RAID status:"
mdadm --detail "$RAID_DEVICE" | tee -a "$LOG_FILE"

# Optional: Monitor sync progress (non-blocking)
if grep -qE '\[.*_.*\]' /proc/mdstat; then
    log "🔄 RAID sync in progress. You can monitor with: watch cat /proc/mdstat"
    echo "Note: The script will continue without waiting for sync to complete."
    echo "This is safe - the array is usable during sync."
fi

# Format with ext4
log "🧱 Formatting $RAID_DEVICE with ext4..."
if ! mkfs.ext4 -F -L "RAID$RAID_LEVEL" "$RAID_DEVICE"; then
    error_exit "Failed to format RAID device"
fi

# Create mount point and mount
MOUNT_POINT="/mnt/raid$RAID_LEVEL"
log "📁 Creating mount point: $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"

log "📦 Mounting $RAID_DEVICE to $MOUNT_POINT..."
if ! mount "$RAID_DEVICE" "$MOUNT_POINT"; then
    error_exit "Failed to mount RAID device"
fi

# Set appropriate permissions
chmod 755 "$MOUNT_POINT"

# Add to fstab
UUID=$(blkid -s UUID -o value "$RAID_DEVICE")
if [[ -z "$UUID" ]]; then
    error_exit "Could not get UUID for RAID device"
fi

log "📝 Adding to /etc/fstab (UUID: $UUID)..."
# Create backup of fstab
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)

# Add entry if not already present
if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID  $MOUNT_POINT  ext4  defaults,nofail  0  0" >> /etc/fstab
    log "✅ Added fstab entry"
else
    log "ℹ️  fstab entry already exists"
fi

# Save RAID configuration
log "🧬 Updating $MDADM_CONF..."
# Create backup
if [[ -f "$MDADM_CONF" ]]; then
    cp "$MDADM_CONF" "${MDADM_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Add array definition
ARRAY_DEF=$(mdadm --detail --scan)
if ! grep -Fq "$RAID_DEVICE" "$MDADM_CONF" 2>/dev/null; then
    echo "$ARRAY_DEF" >> "$MDADM_CONF"
    log "✅ Added RAID configuration to $MDADM_CONF"
else
    log "ℹ️  RAID configuration already exists in $MDADM_CONF"
fi

# Update initramfs for boot-time RAID support
if command -v update-initramfs &>/dev/null; then
    log "🔄 Updating initramfs..."
    update-initramfs -u
elif command -v dracut &>/dev/null; then
    log "🔄 Updating initramfs with dracut..."
    dracut -f
elif command -v mkinitcpio &>/dev/null; then
    log "🔄 Updating initramfs with mkinitcpio..."
    mkinitcpio -p linux
else
    log "⚠️  Could not find initramfs update command. Manual update may be required."
fi

# Final status and summary
echo
echo "🎉 =============== SUCCESS =============== 🎉"
log "✅ RAID $RAID_LEVEL array created successfully!"
echo
echo "📋 Summary:"
echo "  • RAID Level: $RAID_LEVEL"
echo "  • Device: $RAID_DEVICE"
echo "  • Mount Point: $MOUNT_POINT"
echo "  • Filesystem: ext4"
echo "  • UUID: $UUID"
echo "  • Log File: $LOG_FILE"
echo
echo "📊 Array Details:"
mdadm --detail "$RAID_DEVICE"
echo
echo "💾 Disk Usage:"
df -h "$MOUNT_POINT"
echo
echo "🔧 Useful Commands:"
echo "  • Check RAID status: cat /proc/mdstat"
echo "  • Detailed info: mdadm --detail $RAID_DEVICE"
echo "  • Monitor sync: watch cat /proc/mdstat"
echo "  • View logs: tail -f $LOG_FILE"

log "Script completed successfully"
