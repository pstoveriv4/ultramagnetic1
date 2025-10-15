#!/bin/bash

echo "$(GetTimeStamp) START variables, functions, directory checking" >> /var/log/Deploy_dpdrivervm.sh.log

# Variables
AzSubscription="AzureCoreWorkLoads"
storageAccountName="sharedstorage0522024"
containerName="dpdrivervm"
blobName="cps.zip"
localFilePath="/tmp"
directoryPath="/usr/sbin"
processPath="/usr/sbin/cps/ncps"
max_retries=3
retry_delay=10 
tools=(
    "cps.zip"
    "ntttcp.zip"
    "latte.zip"
    "sockperf.zip"
)

echo "********************"
echo "Setting variables and functions"

# Avoid interactive prompts during apt-get
export DEBIAN_FRONTEND=noninteractive

# Function to get the current timestamp
GetTimeStamp() {
    date "+[%m/%d/%y %H:%M:%S]"
}

##### START - Ensure /tmp and /usr/sbin/cps directories exist #####
echo "$(GetTimeStamp) Ensuring /tmp and /usr/sbin directories exist"

# Create /opt directory if it doesn't exist
if [ ! -d "$localFilePath" ]; then
    echo "$(GetTimeStamp) /tmp does not exist, creating it..."
    sudo mkdir -p "$localFilePath"
fi

# Create /opt/CPS directory if it doesn't exist
if [ ! -d "$directoryPath" ]; then
    echo "$(GetTimeStamp) /usr/sbin does not exist, creating it..."
    sudo mkdir -p "$directoryPath"
fi

echo "$(GetTimeStamp) END variables, functions, directory checking" >> /var/log/Deploy_dpdrivervm.sh.log

# Wait for apt to be available
echo "$(GetTimeStamp) START apt-get lock checking" >> /var/log/Deploy_dpdrivervm.sh.log
while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
   echo "Waiting for apt lock..."
   sleep $retry_delay
done
echo "$(GetTimeStamp) END apt-get lock checking" >> /var/log/Deploy_dpdrivervm.sh.log

# Install required packages
echo "$(GetTimeStamp) START apt-get update process" >> /var/log/Deploy_dpdrivervm.sh.log
sudo apt-get update >> /var/log/Deploy_dpdrivervm.sh.log
sleep $retry_delay
sudo apt-get install -y unzip apt-transport-https curl
sleep $retry_delay
echo "$(GetTimeStamp) END apt-get update and unzip process" >> /var/log/Deploy_dpdrivervm.sh.log

echo "$(GetTimeStamp) START AZ CLI install" >> /var/log/Deploy_dpdrivervm.sh.log
# Install Azure CLI if not installed
if ! command -v az &> /dev/null
then
    echo "$(GetTimeStamp) Azure CLI not found, installing..." >> /var/log/Deploy_dpdrivervm.sh.log
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi
echo "$(GetTimeStamp) END AZ CLI install" >> /var/log/Deploy_dpdrivervm.sh.log

sleep $retry_delay

echo "$(GetTimeStamp) START AZ login and download blob .zips" >> /var/log/Deploy_dpdrivervm.sh.log

# Login to Azure using Managed Identity
echo "$(GetTimeStamp) Login to Azure using Managed Identity" >> /var/log/Deploy_dpdrivervm.sh.log
az login --identity --username "a68a7bc8-b41c-4e6b-83ca-e740c1d93c16"

# Set the subscription
az account set --subscription "$AzSubscription"

# Download the .zip from Azure Blob Storage with retry logic
echo "$(GetTimeStamp) Downloading blobs from Azure Blob Storage" >> /var/log/Deploy_dpdrivervm.sh.log

# Loop through each tool, download, and extract
for tool in "${tools[@]}"; do
    echo "$(GetTimeStamp) Downloading $tool from Azure Blob Storage" >> ${directoryPath}/Deploy_dpdrivervm.sh.log
    for (( i=1; i<=$max_retries; i++ )); do
        az storage blob download \
            --account-name $storageAccountName \
            --container-name $containerName \
            --name $tool \
            --file "${localFilePath}/${tool}" \
            --auth-mode login

        # Check if the file was downloaded successfully
        if [ -f "${localFilePath}/${tool}" ]; then
            echo "$(GetTimeStamp) Blob $tool downloaded successfully to ${localFilePath}/${tool}" >> ${directoryPath}/Deploy_dpdrivervm.sh.log
			echo "$(GetTimeStamp) Extracting the .zip to $directoryPath" >> ${directoryPath}/Deploy_dpdrivervm.sh.log

			folderName=$(basename "${tool}" .zip)

			# Create a directory with the base name of the zip file
			echo "$(GetTimeStamp) Creating directory $directoryPath/$folderName" >> ${directoryPath}/Deploy_dpdrivervm.sh.log
			mkdir -p "$directoryPath/$folderName"

			# Extract the .zip file into the created folder
			echo "$(GetTimeStamp) Extracting $tool to $directoryPath/$folderName" >> ${directoryPath}/Deploy_dpdrivervm.sh.log
			unzip -o "${localFilePath}/${tool}" -d "$directoryPath/$folderName"
            break
        else
            echo "$(GetTimeStamp) Failed to download $tool. Attempt $i of $max_retries." >> ${directoryPath}/Deploy_dpdrivervm.sh.log
            if [ $i -lt $max_retries ]; then
                echo "$(GetTimeStamp) Retrying in $retry_delay seconds..." >> ${directoryPath}/Deploy_dpdrivervm.sh.log
                sleep $retry_delay
            else
                echo "$(GetTimeStamp) Maximum retry attempts reached. Failed to download $tool." >> ${directoryPath}/Deploy_dpdrivervm.sh.log
            fi
        fi
    done
done
echo "$(GetTimeStamp) END AZ login and download blob .zips" >> /var/log/Deploy_dpdrivervm.sh.log

echo "$(GetTimeStamp) START FW rules" >> /var/log/Deploy_dpdrivervm.sh.log
# Create an inbound firewall rule for the ncps process
#echo "$(GetTimeStamp) Creating inbound firewall rule for ncps" >> ${directoryPath}/Deploy_dpdrivervm.sh.log
#sudo ufw allow in on any to any port 8080 proto tcp from any # Adjust port and protocol if needed
echo "$(GetTimeStamp) END FW rules" >> /var/log/Deploy_dpdrivervm.sh.log


echo "$(GetTimeStamp) START rc.local and limits.conf edits" >> /var/log/Deploy_dpdrivervm.sh.log
echo "********************"
echo "Limits.conf and rc.local optimization lines"
echo "$(GetTimeStamp) Limits.conf optimization items lines" >> ${directoryPath}/Deploy_dpdrivervm.sh.log

# Get the hostname of the machine
hostname=$(hostname)
echo $(hostname)

##### START - Modify /etc/security/limits.conf #####
echo "*   soft    nofile  1048575" | sudo tee -a /etc/security/limits.conf
echo "*   hard    nofile  1048575" | sudo tee -a /etc/security/limits.conf
echo "$(GetTimeStamp) Updated file limits in /etc/security/limits.conf" >> ${directoryPath}/Deploy_dpdrivervm.sh.log

if [ ! -f /etc/rc.local ]; then
    sudo touch /etc/rc.local
    sudo chmod +x /etc/rc.local
fi   
 
sudo bash -c 'cat << EOF > /etc/rc.local

#!/bin/sh
 
# TIME_WAIT work-around
sysctl -w net.ipv4.tcp_tw_reuse=1
 
# Increase ephemeral port range (client side only)
#sysctl -w net.ipv4.ip_local_port_range="10000 60000"
 
# Disable connection tracking
iptables -t raw -I OUTPUT -j NOTRACK
iptables -t raw -I PREROUTING -j NOTRACK
 
# Increase file descriptors limit
sysctl -w fs.file-max=1048576
 
# Disable connection tracking (some kernels may need this)
sysctl -w net.netfilter.nf_conntrack_max=0
 
# Reduce TCP SYN cookies protection
sysctl -w net.ipv4.tcp_syncookies=0
 
# Increase max SYN backlog
sysctl -w net.ipv4.tcp_max_syn_backlog=2048
 
# Disable reverse path filtering
sysctl -w net.ipv4.conf.all.rp_filter=0
 
# Reduce TCP FIN timeout for faster port recycling (not strictly needed for NCPS)
sysctl -w net.ipv4.tcp_fin_timeout=5

exit 0
EOF'

# Adding changes to /etc/rc.local for permanent usage
    echo "$(GetTimeStamp) System tuning settings added to /etc/rc.local" >> ${directoryPath}/Deploy_dpdrivervm.sh.log
 
# Check if hostname contains 'client' and add ephemeral ports config only for clients
if hostname | grep -qi "client"; then
    echo "sysctl -w net.ipv4.ip_local_port_range=\"10000 60000\"  # ephemeral ports increased (do this on client side only)" >> /etc/rc.local
fi
echo "********************"
echo "rc.local commands for immediate setting"
echo "$(GetTimeStamp) rc.local commands for immediate setting" >> ${directoryPath}/Deploy_dpdrivervm.sh.log

    # Apply the sysctl settings immediately
    sudo sysctl -w net.ipv4.tcp_tw_reuse=1
    sudo sysctl -w net.netfilter.nf_conntrack_max=0
    sudo sysctl -w net.ipv4.tcp_syncookies=0
    sudo sysctl -w net.ipv4.tcp_max_syn_backlog=2048
    sudo sysctl -w net.ipv4.conf.all.rp_filter=0
    sudo sysctl -w net.ipv4.tcp_fin_timeout=5
    sudo sysctl -w fs.file-max=1048576

	#sockperf settings
	sudo sysctl -w net.core.busy_poll=50
	sudo sysctl -w net.core.busy_read=50 

if hostname | grep -qi "client"; then
	sudo sysctl -w net.ipv4.ip_local_port_range="10000 60000"
fi
echo "$(GetTimeStamp) END rc.local and limits.conf edits" >> /var/log/Deploy_dpdrivervm.sh.log

echo "$(GetTimeStamp) START chmod (3)" >> /var/log/Deploy_dpdrivervm.sh.log
echo "**********************"
echo "$(GetTimeStamp) chmod 755 on ncps, ntttcp, sockperf binaries" >> ${directoryPath}/Deploy_dpdrivervm.sh.log
sudo chmod 755 $processPath
sudo chmod 755 "/usr/sbin/ntttcp/ntttcp.bin"
sudo chmod 755 "/usr/sbin/sockperf/sockperf.bin"
echo "$(GetTimeStamp) END chmod (3)" >> /var/log/Deploy_dpdrivervm.sh.log

echo "********************"
echo "Sleep for 60 seconds and then restarting VM"
echo "$(GetTimeStamp) Sleep for 60 seconds and then restarting VM" >> ${directoryPath}/Deploy_dpdrivervm.sh.log

