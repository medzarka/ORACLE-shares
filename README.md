# ORACLE-shares
Oracle Cloud based VM creation script to share data.

### Description
This script is used to create a Linux Alpine linux VM hosted on Oracle Cloud Free Tier.
Originally, the created VM uses Ubuntu 22.04. But with 1G of RAM, Ubuntu appears to be heavly slow.
To solve this issue, we install Alpine linux which is much lighter.

### Steps

#### Version 1.0

- S1 - Install Alpine 3.19 inplace of Ubuntu 22.04
- S2 - Connect to the root user
- S3 - Update the system
- S4 - Install required packages
- S5 - Configure NTP
- S6 - Update user's password
- S7 - Configure the firewall
- S8 - Hardening the SSH service access
- S9 - Diable IPv6
- S10 - Configure doas
- S11 - Install webdav with apache ...
- S12 - Install and configure Rclone
- S13 - configure CRON and create a daily system update script
- Last step -  Cleaning the system and reboot
