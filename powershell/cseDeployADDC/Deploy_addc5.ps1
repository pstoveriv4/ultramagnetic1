# This script will post-provision configure the AD domain/controller

function Get-TimeStamp {    
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)    
}

# Variables
[Byte[]] $key = (1..16)
$adminPasswordSecure=get-content -path "C:\Windows\Temp\adminPasswordEncrypted.log" | ConvertTo-SecureString -Key $key
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPasswordSecure)
$adminPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
$AzSubscription="Compute Aurora - Aurora Redmond Services - Live"
$storageAccountName = "stauroraworkloadepic"
$containerName1 = "citrixinfr"
$containerName2 = "citrixvda"
$containerName3 = "clientvm"
$blobName1 = "epicsynthetics_root.crt"
$blobName2 = "epicsynthetics_wildcard.pfx"
$localFilePath = "C:\windows\temp"
$testUserCount=5 #number of AD testuserxxx accounts to create

# Starting script 5
Write-Output "$(Get-Timestamp) Starting script 5" >> C:\Windows\Temp\Deploy_addc.ps1.log

##### START - Add AD GUI management tools #####
Write-Output "$(Get-Timestamp) Add AD GUI management tools" >> C:\Windows\Temp\Deploy_addc.ps1.log
add-WindowsFeature RSAT-ADDS-Tools
##### END - Add AD GUI management tools #####

##### START - Add OUs structure #####
Write-Output "$(Get-Timestamp) Add OUs structure" >> C:\Windows\Temp\Deploy_addc.ps1.log
New-ADOrganizationalUnit -Name "Citrix" -Path "DC=epicsynthetics,dc=com"
New-ADOrganizationalUnit -Name "Users and Groups" -Path "OU=Citrix,DC=epicsynthetics,dc=com"
New-ADOrganizationalUnit -Name "VDAs" -Path "OU=Citrix,DC=epicsynthetics,dc=com"
New-ADOrganizationalUnit -Name "Infrastructure" -Path "OU=Citrix,DC=epicsynthetics,dc=com"
##### END - Add OUs structure #####


##### START - Add users and groups #####
Write-Output "$(Get-Timestamp) Add users and groups" >> C:\Windows\Temp\Deploy_addc.ps1.log
for($i=1; $i -le $testUserCount; $i++) `
{
	$testusercountFormat3='{0:d3}' -f $i
	$testusername="testuser$($testusercountFormat3)"
	
	New-ADUser -Path "OU=Users and Groups,OU=Citrix,DC=epicsynthetics,dc=com" -Name $testusername `
-samAccountName $testusername -UserPrincipalName "${testusername}@epicsynthetics.com" -DisplayName $testusername `
-GivenName $testusername -Surname "user" -AccountPassword $adminPasswordSecure -Enabled $true

	}

# Add test users group #
New-ADGroup -Name "Citrix Users" -SamAccountName "Citrix Users" -GroupCategory Security -GroupScope Global `
 -DisplayName "Citrix Users" -Path "OU=Users and Groups,OU=Citrix,DC=epicsynthetics,dc=com" -Description "Citrix users"

# Add test users to group #
for($i=1; $i -le $testUserCount; $i++) `
{
	$testusercountFormat3='{0:d3}' -f $i
	$testusername="testuser$($testusercountFormat3)"
	Add-ADGroupMember -Identity "Citrix Users" -Members "CN=$testusername,OU=Users and Groups,OU=Citrix,DC=epicsynthetics,dc=com"

	}
	
# Add c2sadmin and svc-CitrixAdmin Citrix service account, add to Domain Admins/Enterprise Admins group #
New-ADUser -Path "OU=Users and Groups,OU=Citrix,DC=epicsynthetics,dc=com" -Name "c2sadmin" `
-samAccountName "c2sadmin" -UserPrincipalName "c2sadmin@epicsynthetics.com" -DisplayName "c2sadmin" `
-GivenName "c2sadmin" -Surname "user" -AccountPassword $adminPasswordSecure -Enabled $true

New-ADUser -Path "OU=Users and Groups,OU=Citrix,DC=epicsynthetics,dc=com" -Name "svc-CitrixAdmin" `
-samAccountName "svc-CitrixAdmin" -UserPrincipalName "svc-CitrixAdmin@epicsynthetics.com" -DisplayName "svc-CitrixAdmin" `
-GivenName "svc-CitrixAdmin" -Surname "user" -AccountPassword $adminPasswordSecure -Enabled $true

Add-ADGroupMember -Identity "Domain Admins" -Members "CN=c2sadmin,OU=Users and Groups,OU=Citrix,DC=epicsynthetics,dc=com"
Add-ADGroupMember -Identity "Domain Admins" -Members "CN=svc-CitrixAdmin,OU=Users and Groups,OU=Citrix,DC=epicsynthetics,dc=com"
Add-ADGroupMember -Identity "Enterprise Admins" -Members "CN=c2sadmin,OU=Users and Groups,OU=Citrix,DC=epicsynthetics,dc=com"
Add-ADGroupMember -Identity "Enterprise Admins" -Members "CN=svc-CitrixAdmin,OU=Users and Groups,OU=Citrix,DC=epicsynthetics,dc=com"
##### END - Add users and groups #####


##### START - Add Certificate Services role service and export out root/wildcard certificates #####
Write-Output "$(Get-Timestamp) Add Certificate Services role service and export out root/wildcard certificates" >> C:\Windows\Temp\Deploy_addc.ps1.log
Install-WindowsFeature "Adcs-Cert-Authority"
$params = @{
    CAType              = 'EnterpriseRootCa'
    CryptoProviderName  = "RSA#Microsoft Software Key Storage Provider"
    KeyLength           = 2048
    HashAlgorithmName   = 'SHA256'
    ValidityPeriod      = 'Years'
    ValidityPeriodUnits = 5
}
Install-AdcsCertificationAuthority @params -force
Install-WindowsFeature "RSAT-ADCS-Mgmt"

##### Share C:\install as Install$ #####
New-Item -Path "c:\" -Name "Install" -ItemType "directory"
New-SmbShare -Name "Install$" -Path "C:\Install"
Write-Output "$(Get-Timestamp) Add TCP 445 inbound firewall rule" >> C:\Windows\Temp\Deploy_addc.ps1.log
New-NetFirewallRule -DisplayName "Allow TCP 445 inbound" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 445

##### Export root cert to a file on C:\install #####
start-process -filepath certutil.exe -argumentlist "-ca.cert c:\install\epicsynthetics_root.crt"

##### Create wildcard cert with SAN and export to C:\install #####
$file = @'
[NewRequest]
FriendlyName="epicsynthetics wildcard certificate"
Subject = "CN=*.epicsynthetics.com,O=C2S Technologies,OU=IT,L=Bellevue,S=Washington,C=US"
KeyLength = 2048
Exportable = TRUE
MachineKeySet = True
[Extensions]
; If your client operating system is Windows Server 2008, Windows Server 2008 R2, Windows Vista, or Windows 7
; SANs can be included in the Extensions section by using the following text format. Note 2.5.29.17 is the OID for a SAN extension.
2.5.29.17 = "{text}"
_continue_ = "dns=*.epicsynthetics.com&"
[RequestAttributes]
CertificateTemplate = "WebServer"
'@

Set-Content temp.inf $file

# create a new request from an .inf file
certreq -new temp.inf temp.req

# submit a request to the certificate authority
certreq -submit -config "epic-ctx-AD01.epicsynthetics.com\epicsynthetics-Epic-ctx-AD01-CA" temp.req temp.cer

# accept and install a response to a certificate request
certreq -accept temp.cer

# get certificate thumbprint
$CertThumbprint=(get-childitem -path cert:\Localmachine\my | where-object {$_.Subject -like "*S=Washington*"}).Thumbprint

Export-PfxCertificate -Cert cert:\LocalMachine\My\$CertThumbprint -FilePath C:\Install\epicsynthetics_wildcard.pfx -Password $adminPasswordSecure
##### END - Add Certificate Services role service and export out root/wildcard certificates #####


##### START - Upload certificates to addc Blob container for downloading by other workloads #####
Write-Output "$(Get-Timestamp) Upload certificates to addc Blob container for downloading by other workloads" >> C:\Windows\Temp\Deploy_addc.ps1.log 

# Azure Storage context
#install necessary AZ storage and Nuget modules
Install-PackageProvider -name NuGet -force
Set-PSrepository -name "PSGallery" -installationpolicy Trusted
install-module Az.Storage -force
connect-azaccount -identity -AccountId 3767dcc1-41d1-4d77-9ddb-eb237e2f2095
Select-AzSubscription -SubscriptionName $AzSubscription
$storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount

# Upload certificates to Azure Storage
Set-AzStorageBlobContent -Container $containerName1 -File "C:\install\epicsynthetics_root.crt" -Blob $blobName1 -Context $storageContext -force
Set-AzStorageBlobContent -Container $containerName1 -File "C:\install\epicsynthetics_wildcard.pfx" -Blob $blobName2 -Context $storageContext -force
Set-AzStorageBlobContent -Container $containerName2 -File "C:\install\epicsynthetics_root.crt" -Blob $blobName1 -Context $storageContext -force
Set-AzStorageBlobContent -Container $containerName2 -File "C:\install\epicsynthetics_wildcard.pfx" -Blob $blobName2 -Context $storageContext -force
Set-AzStorageBlobContent -Container $containerName3 -File "C:\install\epicsynthetics_root.crt" -Blob $blobName1 -Context $storageContext -force
Set-AzStorageBlobContent -Container $containerName3 -File "C:\install\epicsynthetics_wildcard.pfx" -Blob $blobName2 -Context $storageContext -force
##### END - Upload certificates to addc Blob container for downloading by other workloads #####

##### START - Delete the scheduled task which started AD part 5 #####
Write-Output "$(Get-Timestamp) Remove AD part 5 scheduled task" >> C:\Windows\Temp\Deploy_addc.ps1.log
Unregister-ScheduledTask -TaskName "Deploy_addc5.ps1" -Confirm:$false
##### END - Delete the scheduled task which started AD part 5 #####

##### START - Cleanup #####
Write-Output "$(Get-Timestamp) Cleanup " >> C:\Windows\Temp\Deploy_addc.ps1.log
Remove-Item "C:\Windows\Temp\adminPasswordEncrypted.log"
##### END - Cleanup #####

# Ending script 5
Write-Output "$(Get-Timestamp) Ending script 5" >> C:\Windows\Temp\Deploy_addc.ps1.log








