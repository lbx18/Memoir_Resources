# Documentation: Custom mdadm Event Notification Script (mdadm-custom-notify.sh)

## Overview

This script is designed to be triggered by the mdadm daemon whenever a RAID event occurs. It sends clear, detailed, and prioritized email alerts for various events, such as drive failures, rebuilds, and spare activations. This provides much more informative and actionable notifications than the default mdadm behavior.

### Key Features

- Event-Specific Alerts: Sends uniquely tailored emails for different events (e.g., Fail, RebuildStarted, RebuildFinished, TestMessage).

- Rich Information: Each email includes the hostname, timestamp, the affected RAID device, the component disk (if applicable), and the full output of cat /proc/mdstat for immediate context.

- Prioritized Subjects: Uses emojis and keywords like "CRITICAL" and "WARNING" in email subjects to help you quickly identify the severity of an event.

- Simple Logging: Appends a one-line summary of each event to /var/log/mdadm-custom.log.

- Easy Configuration: Requires only setting a single variable for the destination email address.

---

### Configuration & Integration

To make this script work, you need to configure it and tell mdadm to use it.

### Step 1: Configure the Script

- Make the script executable:

```bash
chmod +x mdadm-custom-notify.sh
```

- Move it to a system location:

```bash
sudo mv mdadm-custom-notify.sh /usr/local/sbin/
```

- Edit the script to set your email address:
Open the script and change the EMAIL variable to your own email.
**`EMAIL="your-real-email@example.com"`**

```bash
sudo nano /usr/local/sbin/mdadm-custom-notify.sh
```

---

### Step 2: Configure msmtp to use Gmail

This script relies on msmtp to send emails. This guide shows how to configure it to use a Gmail account.

A. Create a Google App Password

Because this script will access your Google account non-interactively, you cannot use your regular password, especially if you have 2-Factor Authentication (2FA) enabled. Instead, you must generate an "App Password".

- Go to your Google Account settings: https://myaccount.google.com/

- Navigate to the Security section:

- Under "How you sign in to Google," make sure 2-Step Verification is turned On. You cannot create App Passwords without it.

- In the same section, click on App passwords. You may need to sign in again.

- On the App passwords page:

- Click Select app and choose Mail.

- Click Select device and choose Other (Custom name).

- Give it a descriptive name like "RAID Monitor" and click Generate.

Google will display a 16-character password. Copy this password immediately. This is the password you will use in the msmtp configuration file. Do not use your regular Google password.

### B. Create the msmtp Configuration File

Now, create the configuration file that msmtp will use. This can be a system-wide file at **`/etc/msmtprc`**.

Open the file for editing:

```bash
sudo nano /etc/msmtprc
```

Add the following content, replacing your-email@gmail.com with your actual Gmail address and YOUR_16_CHAR_APP_PASSWORD with the App Password you just generated.

```bash
Set default values for all accounts
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

host           smtp.gmail.com
port           587
from           your-email@gmail.com
user           your-email@gmail.com
password       YOUR_16_CHAR_APP_PASSWORD

# Set gmail as the default account to use
account default : gmail
```

- Crucial: Set the correct permissions to protect your password.

```bash
sudo chmod 600 /etc/msmtprc
```

### Step 3: Configure mdadm to Use the Script

- Edit the mdadm configuration file:

```bash
sudo nano /etc/mdadm/mdadm.conf
```

- Add/modify two lines:

Set MAILADDR to your email.

MAILADDR your-real-email@example.com
MAILFROM your-real-email@example.com

![alt](images/md.png)


### Step 4: Set up a custom mdadm Service

My custom **mdadm-custom-notify.sh** will in my repository under the same name, so you can use it directly.
Create a new systemd service file for mdadm monitoring:

```bash
sudo nano /etc/systemd/system/mdadm-monitor.service
```

Add the following content:

```ini
[Unit]
Description=Raid Monitoring via mdadm
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/mdadm --monitor --scan --mail=your-real-email@example.com --program=/usr/local/bin/mdadm-custom-notify.sh
Restart=always
RestartSec=15
KillMode=mixed
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
```

---

Service File: mdadm-monitor.service

This systemd unit file is designed to run the mdadm RAID monitoring daemon and execute a custom script for notifications.

**[Unit]** Section

This section contains generic options about the unit, which are independent of the type of service.

**[Unit] :** Denotes the start of the Unit definition section.

**Description=Raid Monitoring via mdadm :**	Provides a brief, human-readable description of what the service does.

**After=network.target :**Defines a dependency: this service should only be started after the network.target (which signifies that network configuration is complete) is active. This ensures that the service can send email notifications or run network-dependent scripts immediately upon starting.

---

2.**[Service]** Section
This section contains directives that control the execution and behavior of the service process.

**[Service] :** Denotes the start of the Service definition section.

**Type=simple:** Specifies the service start-up type. simple means the process specified by ExecStart is the main process of the service, and systemd considers the service started immediately after this process is successfully forked.

**ExecStart=/usr/sbin/mdadm --monitor --scan --mail=your-real-email@example.com --program=/usr/local/bin/mdadm-custom-notify.sh :**  

The command to execute when the service is started. **`/usr/sbin/mdadm --monitor --scan:`** Starts the mdadm daemon in continuous monitoring mode, checking all RAID arrays found via a scan. **`--mail=...:`** Configures mdadm to send standard email alerts for events (like a drive failure) to the specified address. **`--program=...`** Specifies a custom script (**`mdadm-custom-notify.sh`**) to execute when a RAID event occurs. This is the mechanism for custom monitoring (e.g., sending alerts to Slack or a logging server).

**Restart=always:** Configures systemd to automatically restart the service under all circumstances, ensuring continuous monitoring even if the mdadm process crashes or is killed.

**RestartSec=15 :** Defines a 15-second delay that systemd will wait before attempting to restart the service.

**KillMode=mixed:** Specifies how systemd attempts to stop the service. mixed usually means systemd first sends a signal (like SIGTERM) to the main process, then sends another signal to all remaining processes in the control group.

**TimeoutStartSec=120:** Sets the maximum time (120 seconds) systemd will wait for the service's ExecStart command to complete before concluding the start-up failed.

---

**[Install] :**	 Denotes the start of the Install definition section.

**WantedBy=multi-user.target**	Specifies that the service should be started when the system reaches the multi-user.target state (the standard run level for a server with a console, usually without a graphical desktop). When the service is enabled, a symbolic link is created in the multi-user.target.wants directory pointing to this unit file.

---

### Enable and Start the Service

- Enable the service to start on boot:

```bash
sudo systemctl enable mdadm-monitor.service
```

- Reload systemd to recognize the new service:

```bash
sudo systemctl daemon-reload
```

- Start the service:

```bash
sudo systemctl start mdadm-monitor.service
```

- Check the status to ensure it's running:

```bash
sudo systemctl status mdadm-monitor.service
```

### Using mdadm monitor

You can test the setup by sending a test message:

```bash
sudo /usr/local/sbin/mdadm-custom-notify.sh "Fail" "/dev/md" "/dev/sdX"
```

This should trigger an email notification to the address you configured.


