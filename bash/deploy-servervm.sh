#!/bin/bash
# ORIGINAL
# This bash script is for formatting/mounting data disk and installing Apache www

current_time=$(date +"%H:%M:%S")
echo "----------------------------------------------------------------"
echo "Started deploy-servervm.sh script at $current_time"

current_time=$(date +"%H:%M:%S")

echo "Get the data disk block device at $current_time"
# find the block device with the dataDiskSizeGB match from the ARM template/Manifest parameter
# dataDiskSizeGB="${1}G"
dataDiskSizeGB="256G"
device=$(lsblk -ndo NAME,SIZE | awk '$2=="'"$dataDiskSizeGB"'" {print "/dev/" $1}')
if [ -z "$device" ]; then
    echo "Error: No device found matching size $dataDiskSizeGB"
    exit 1
fi

echo "dataDiskSizeGB: $dataDiskSizeGB"
echo "device: $device"

current_time=$(date +"%H:%M:%S")

# format and mount the Azure VM data disk attached
echo "Formatting $device block device at $current_time"
mkfs.ext4 $device
echo "mounting the data disk to /var/www"
mkdir /var/www
mount $device /var/www
echo "enabling automount on reboot if needed"
UUID=$(lsblk -no UUID $device)
echo "UUID=$UUID /var/www ext4 defaults,nofail 0 2" | tee -a /etc/fstab


# install and configure Apache www

current_time=$(date +"%H:%M:%S")

echo "Update package info and install apache2 to default /var/www at $current_time"
apt update
apt install -y apache2
echo "enable and start apache2"
systemctl enable apache2
systemctl start apache2
systemctl status apache2
echo "open OS firewall for Apache"
ufw allow 'Apache Full' 

current_time=$(date +"%H:%M:%S")

echo "Completed deploy-servervm.sh script at $current_time"