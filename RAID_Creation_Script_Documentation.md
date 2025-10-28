# Documentation: RAID Array Setup Script (raid_setup_improved.sh)

## Overview

This script provides an interactive and safe way to create a new mdadm software RAID array on a Linux system. It guides the user through selecting a RAID level and member disks, performs extensive safety checks to prevent accidental data loss, and automates the entire process from disk cleaning to filesystem creation and system configuration.

### Key Features

Interactive Prompts: Guides you through selecting a RAID level (0, 1, 5, 6, 10) and the number of disks.

**`Enhanced Safety:`**

- Checks for mounted devices, existing filesystems, and prior RAID signatures before use.

- Requires explicit, case-sensitive confirmation (YES) before wiping any data.

- Thoroughly cleans disks by wiping RAID superblocks, filesystem signatures, and partition tables.

- Robust Error Handling: The script will exit immediately if any command fails or an error occurs.

**`Full Automation`**:

- Creates the RAID array.

- Formats the array with an ext4 filesystem.

- Creates a mount point (e.g., /mnt/raid5).

- Automatically adds the correct entries to /etc/fstab (for auto-mounting on boot) and /etc/mdadm/mdadm.conf (for array discovery).

- Updates the initramfs to ensure the array is available during early boot.

- Detailed Logging: Creates a comprehensive log file for each run in /var/log/, which is useful for troubleshooting.

**`Prerequisites :`**

Before running the script, ensure the necessary tools are installed on your system.

- On Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install mdadm msmtp-utils msmtp
```

The script will automatically check for mdadm, lsblk, blkid, mkfs.ext4, and wipefs.

**`How to Use :`**

- Make the script executable:

```bash
chmod +x raid_setup_improved.sh
```

- Run the script with root privileges:

```bash
sudo ./raid_setup_improved.sh
```

- Follow the on-screen prompts:

  - Enter your desired RAID level.

  - Enter the number of disks you wish to use.

  - Provide the device paths for each disk (e.g., /dev/sda, /dev/sdb).

  - Review your selections and type YES to confirm and begin the creation process.

The script will handle the rest. Upon completion, it will display a summary of the new array and its mount point.

❗ WARNING: This script is designed to be destructive to the target disks. It will permanently erase all data on the disks you select. Double-check your disk selections and ensure you have backups of any important data.
