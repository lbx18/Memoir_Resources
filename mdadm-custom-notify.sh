#!/bin/bash
# Custom RAID Event Notification Script
# Usage: mdadm-custom-notify.sh <event> <device> [component]

EVENT="$1"
DEVICE="$2"
COMPONENT="$3"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)
EMAIL="YOUR_EMAIL_ADDRESS"

# Function to send email
send_notification() {
    local subject="$1"
    local body="$2"
    local priority="$3"
    
    {
        echo "Subject: [RAID Alert] $subject"
        echo "From: raid-monitor@$HOSTNAME"
        echo "To: $EMAIL"
        echo "Priority: $priority"
        echo ""
        echo "$body"
        echo ""
        echo "---"
        echo "Server: $HOSTNAME"
        echo "Time: $TIMESTAMP"
        echo "Device: $DEVICE"
        if [ -n "$COMPONENT" ]; then
            echo "Component: $COMPONENT"
        fi
        echo ""
        echo "Current RAID Status:"
        cat /proc/mdstat
    } | msmtp "$EMAIL"
}

# Get detailed device info
get_device_info() {
    if [ -n "$DEVICE" ] && [ -e "$DEVICE" ]; then
        mdadm --detail "$DEVICE" 2>/dev/null
    fi
}

# Handle specific events
case "$EVENT" in
    "Fail")
        SUBJECT="🔴 CRITICAL: Drive Failure Detected"
        BODY="CRITICAL ALERT: A drive has failed in your RAID array!

Device: $DEVICE
Failed Component: $COMPONENT

IMMEDIATE ACTION REQUIRED:
1. Replace the failed drive as soon as possible
2. Monitor the array status closely
3. Ensure you have recent backups

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "high"
        ;;
        
    "FailSpare")
        SUBJECT="🟡 WARNING: Spare Drive Failed"
        BODY="WARNING: A spare drive has failed.

Device: $DEVICE
Failed Spare: $COMPONENT

This reduces your redundancy. Consider replacing the spare drive.

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "normal"
        ;;

    "SpareActive")
        SUBJECT="🟢 INFO: Spare Drive Activated"
        BODY="INFORMATION: A spare drive has been activated and is rebuilding.

Device: $DEVICE
Active Spare: $COMPONENT

The array is rebuilding. Monitor progress with: watch cat /proc/mdstat

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "normal"
        ;;

    "NewArray")
        SUBJECT="🆕 INFO: New RAID Array Created"
        BODY="INFORMATION: A new RAID array has been created.

Device: $DEVICE

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "low"
        ;;

    "DegradedArray")
        SUBJECT="🟠 WARNING: Array Degraded"
        BODY="WARNING: RAID array is running in degraded mode.

Device: $DEVICE

This means the array is functioning but with reduced redundancy.
Consider investigating and replacing any failed drives.

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "high"
        ;;

    "MoveSpare")
        SUBJECT="🔄 INFO: Spare Drive Moved"
        BODY="INFORMATION: A spare drive has been moved between arrays.

Device: $DEVICE
Spare: $COMPONENT

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "low"
        ;;

    "SparesMissing")
        SUBJECT="⚠️ WARNING: No Spare Drives Available"
        BODY="WARNING: The RAID array has no spare drives available.

Device: $DEVICE

Consider adding spare drives to improve fault tolerance.

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "normal"
        ;;

    "TestMessage")
        SUBJECT="🧪 TEST: RAID Monitoring Test"
        BODY="This is a test message from your RAID monitoring system.

Device: $DEVICE

If you receive this message, your notification system is working correctly.

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "low"
        ;;

    "DeviceDisappeared")
        SUBJECT="🚨 CRITICAL: RAID Device Disappeared"
        BODY="CRITICAL ALERT: A RAID device has disappeared from the system!

Device: $DEVICE

This could indicate:
- Drive failure
- Connection issues
- Power problems

IMMEDIATE INVESTIGATION REQUIRED!

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "high"
        ;;

    "RebuildStarted")
        SUBJECT="🔧 INFO: RAID Rebuild Started"
        BODY="INFORMATION: RAID rebuild has started.

Device: $DEVICE

Monitor progress with: watch cat /proc/mdstat
Rebuild may take several hours depending on drive size.

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "normal"
        ;;

    "RebuildFinished")
        SUBJECT="✅ SUCCESS: RAID Rebuild Complete"
        BODY="SUCCESS: RAID rebuild has completed successfully!

Device: $DEVICE

Your array is now fully redundant again.

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "normal"
        ;;

    *)
        SUBJECT="❓ UNKNOWN: RAID Event"
        BODY="An unknown RAID event has occurred.

Event: $EVENT
Device: $DEVICE
Component: $COMPONENT

Please check the system logs for more information.

Detailed Information:
$(get_device_info)"
        send_notification "$SUBJECT" "$BODY" "normal"
        ;;
esac

# Log the event
echo "$(date): RAID Event - $EVENT on $DEVICE ($COMPONENT)" >> /var/log/mdadm-custom.log

exit 0