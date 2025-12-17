# This script will post-provision configure the AD domain/controller

function Get-TimeStamp {    
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)    
}

# Variables
$adminUser="epicsynthetics\localadmin"
[Byte[]] $key = (1..16)
$adminPasswordSecure=get-content -path "C:\Windows\Temp\adminPasswordEncrypted.log" | ConvertTo-SecureString -Key $key
$adminUsername="localadmin"
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPasswordSecure)
$stringAdminPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

#AD static IP values
$IPType = "IPv4"
$IP = "10.15.0.11"
$MaskBits = "24"
$Gateway = "10.15.0.1"
$Dns = "10.15.0.11"

# Starting script 3
Write-Output "$(Get-Timestamp) Starting script 3" >> C:\Windows\Temp\Deploy_addc.ps1.log

##### START - Specify static IP address and DNS server pointer on network adapter #####
Write-Output "$(Get-Timestamp) Specify static IP address and DNS server pointer on network adapter" >> C:\Windows\Temp\Deploy_addc.ps1.log
$adapter = Get-NetAdapter | ? {$_.InterfaceDescription -eq "Microsoft Hyper-V Network Adapter"}
$adapter | New-NetIPAddress `
 -AddressFamily $IPType `
 -IPAddress $IP `
 -PrefixLength $MaskBits `
 -DefaultGateway $Gateway
$adapter | Set-DnsClientServerAddress -ServerAddresses $DNS
##### END - Specify static IP address and DNS server pointer on network adapter #####

##### START - Create AD domain with DNS services #####
Write-Output "$(Get-Timestamp) Create AD domain with DNS services" >> C:\Windows\Temp\Deploy_addc.ps1.log
Install-windowsfeature AD-domain-services
Install-ADDSForest -DomainName "epicsynthetics.com" -InstallDNS -SafeModeAdministratorPassword $adminPasswordSecure -NoRebootOnCompletion:$true -force
##### END - Create AD domain with DNS services #####

##### START - Add part 4 PS1 scheduled task for next startup #####
Write-Output "$(Get-Timestamp) Add AD DC part 4 PS1 scheduled task" >> C:\Windows\Temp\Deploy_addc.ps1.log
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskAction = New-ScheduledTaskAction -Execute "PowerShell" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\Windows\Temp\Deploy_addc4.ps1`""
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount
Register-ScheduledTask 'Deploy_addc4.ps1' -Action $taskAction -Trigger $taskTrigger -Principal $Principal
##### END - Add part 4 PS1 scheduled task for next startup #####

##### START - Delete the scheduled task which started AD part 3 #####
Write-Output "$(Get-Timestamp) Remove AD part 3 scheduled task" >> C:\Windows\Temp\Deploy_addc.ps1.log
Unregister-ScheduledTask -TaskName "Deploy_addc3.ps1" -Confirm:$false
##### END - Delete the scheduled task which started AD part 3 #####

# Ending script 3
Write-Output "$(Get-Timestamp) Ending script 3" >> C:\Windows\Temp\Deploy_addc.ps1.log

# Restart the server
Write-Output "$(Get-Timestamp) Restart server" >> C:\Windows\Temp\Deploy_addc.ps1.log
Restart-computer -force





