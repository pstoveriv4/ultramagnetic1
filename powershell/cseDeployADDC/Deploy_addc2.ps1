# This script will post-provision configure the AD domain/controller

function Get-TimeStamp {    
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)    
}

# Variables
$AzSubscription="Compute Aurora - Aurora Redmond Services - Live"
$storageAccountName = "stauroraworkloadepic"
$containerName = "addc"
$localFilePath = "C:\windows\temp"
$adminUser="localadmin"
[Byte[]] $key = (1..16)
$adminPasswordSecure=get-content -path "C:\Windows\Temp\adminPasswordEncrypted.log" | ConvertTo-SecureString -Key $key
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPasswordSecure)
$adminPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# Starting script 2
Write-Output "$(Get-Timestamp) Starting script 2" >> C:\Windows\Temp\Deploy_addc.ps1.log

##### START - Add part 3 PS1 scheduled task for next startup #####
Write-Output "$(Get-Timestamp) Add AD DC part 3 PS1 scheduled task" >> C:\Windows\Temp\Deploy_addc.ps1.log
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskTrigger.Delay = 'PT3M'
$taskAction = New-ScheduledTaskAction -Execute "PowerShell" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Windows\Temp\Deploy_addc3.ps1`""
Register-ScheduledTask 'Deploy_addc3.ps1' -Action $taskAction -Trigger $taskTrigger -User $adminUser -Password $adminPassword
##### END - Add part 3 PS1 scheduled task for next startup #####

##### START - Delete the scheduled task which started AD part 2 #####
Write-Output "$(Get-Timestamp) Remove AD part 2 scheduled task" >> C:\Windows\Temp\Deploy_addc.ps1.log
Unregister-ScheduledTask -TaskName "Deploy_addc2.ps1" -Confirm:$false
##### END - Delete the scheduled task which started AD part 2 #####

Write-Output "$(Get-Timestamp) Sleep for 30 seconds" >> C:\Windows\Temp\Deploy_addc.ps1.log
Start-Sleep -Seconds 30

# Ending script 2
Write-Output "$(Get-Timestamp) Ending script 2" >> C:\Windows\Temp\Deploy_addc.ps1.log

# Restart the server
Write-Output "$(Get-Timestamp) Restart server" >> C:\Windows\Temp\Deploy_addc.ps1.log
Restart-computer -force






