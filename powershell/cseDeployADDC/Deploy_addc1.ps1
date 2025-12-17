# This script will post-provision configure the AD domain/controller

param (
	[Parameter(Mandatory=$True, Position=0, ValueFromPipeline=$false)]
	[System.String]
	$adminPassword

)

function Get-TimeStamp {    
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)    
}

# Variables
$AzSubscription="Compute Aurora - Aurora Redmond Services - Live"
$storageAccountName = "stauroraworkloadepic"
$containerName = "addc"
$blobName1 = "Deploy_addc2.ps1"
$blobName2 = "Deploy_addc3.ps1"
$blobName3 = "Deploy_addc4.ps1"
$blobName4 = "Deploy_addc5.ps1"
$localFilePath = "C:\windows\temp"

# Starting script 1
Write-Output "$(Get-Timestamp) Starting script 1" >> C:\Windows\Temp\Deploy_addc.ps1.log

##### START - Azure Storage context and downloads #####
Write-Output "$(Get-Timestamp) Azure Storage context and downloads" >> C:\Windows\Temp\Deploy_addc.ps1.log
Install-PackageProvider -name NuGet -force
Set-PSrepository -name "PSGallery" -installationpolicy Trusted
Install-module Az.Accounts -force
Install-module Az.Storage -force
connect-azaccount -identity -AccountId 3767dcc1-41d1-4d77-9ddb-eb237e2f2095
Select-AzSubscription -SubscriptionName $AzSubscription
$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
# Download the PS1 scripts from Azure Storage
Get-AzStorageBlobContent -Container $containerName -Blob $blobName1 -Destination $localFilePath -Context $storageContext -force
Get-AzStorageBlobContent -Container $containerName -Blob $blobName2 -Destination $localFilePath -Context $storageContext -force
Get-AzStorageBlobContent -Container $containerName -Blob $blobName3 -Destination $localFilePath -Context $storageContext -force
Get-AzStorageBlobContent -Container $containerName -Blob $blobName4 -Destination $localFilePath -Context $storageContext -force
##### END - Azure Storage context and downloads #####

##### START - Output encrypted password #####
Write-Output "$(Get-Timestamp) Output encrypted password" >> C:\Windows\Temp\Deploy_addc.ps1.log
$secureStringPwd=ConvertTo-SecureString $adminPassword -AsPlainText -Force
[Byte[]] $key = (1..16)
$encryptedStringPwd=ConvertFrom-SecureString -SecureString $secureStringPwd -key $key | Out-file -filepath "C:\Windows\Temp\adminPasswordEncrypted.log"
##### START - Output encrypted password #####

##### START - Add part 2 PS1 scheduled task for next startup #####
Write-Output "$(Get-Timestamp) Add AD DC part 2 PS1 scheduled task" >> C:\Windows\Temp\Deploy_addc.ps1.log
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskAction = New-ScheduledTaskAction -Execute "PowerShell" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Windows\Temp\Deploy_addc2.ps1`""
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount
Register-ScheduledTask 'Deploy_addc2.ps1' -Action $taskAction -Trigger $taskTrigger -Principal $Principal
##### END - Add part 2 PS1 scheduled task for next startup #####

# Ending script 1
Write-Output "$(Get-Timestamp) Ending script 1" >> C:\Windows\Temp\Deploy_addc.ps1.log

# Restart the server
Write-Output "$(Get-Timestamp) Restart server" >> C:\Windows\Temp\Deploy_addc.ps1.log
Restart-computer -force






