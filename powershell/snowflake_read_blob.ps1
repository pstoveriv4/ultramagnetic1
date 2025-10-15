<#
.SYNOPSIS
This script performs read tests against blob storage within a region to determine network throughput and storage latency.

.NOTES
Author: Azure
Copyright (c) Microsoft Corporation.
Licensed for your reference purposes only on an as is basis, without warranty of any kind.
#>

param
(
    [Parameter(Mandatory = $true)]
    [string]$storageAccountName,
    [string]$clientVmPrefix,
    [string]$accountId,
    [string]$subscriptionId
)

    function Get-Percentile {
        param (
        [float[]]$numbers,
        [float]$percentile = 90
        )

		$sortedNumbers = $numbers | Sort-Object
		$index = [math]::Ceiling(($percentile / 100) * $sortedNumbers.Count) - 1
		return $sortedNumbers[$index]
        }

# Manifest file Powershell script parameters

#====================================
#  Declare check metadata
#====================================

# Declare check metadata
New-Variable -Option Constant -Name CheckResultMetricsName -Value 'snowflakechecktool' # fill this field for the metric name when emitting check result
New-Variable -Option Constant -Name CheckToolName -Value 'snowflake_read_blob.ps1' # fill  field with check tool's file name

$startTime = (Get-Date).ToUniversalTime().ToString("o")
# Common logic shared across checks
#====================================

# Source common function files by searching either 
# (1)script directory: location of this script
# (2)package directory: root location of this package (2-levels up)
$scriptDir = $MyInvocation.MyCommand.Path | Split-Path -Parent | Join-Path -ChildPath "common"
$packageDir = $scriptDir | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent | Join-Path -ChildPath "common"

$scriptDirFileCount = Get-ChildItem -Path $scriptDir -Filter '*.ps1' -ErrorAction SilentlyContinue
$packageDirFileCount = Get-ChildItem -Path $packageDir -Filter '*.ps1' -ErrorAction SilentlyContinue
New-Variable -Option Constant -Name CheckStartTime -Value $startTime

Remove-Variable -Name @('Scenario', 'CheckCaseName') -ErrorAction Ignore 

#====================================

if ( $null -ne $scriptDirFileCount) {
    $commonLibPath = $scriptDir
}
elseif ( $null -ne $packageDirFileCount) {
    $commonLibPath = $packageDir
}
else {
    $checkEndTime = (Get-Date).ToUniversalTime().ToString("o")
    $checkResult = 3
    $logHashTable = [ordered]@{ 
        "Type"           = 'Metrics'
        "Message"        = 'Cannot find common directory containing helper functions. Exiting.'
        "CheckToolName"  = $CheckToolName
        "MetricsName"    = $CheckResultMetricsName
        "MetricsUnit"    = 'CheckResult'
        "MetricsValue"   = $checkResult
        "CheckStartTime" = $CheckStartTime
        "CheckEndTime"   = $checkEndTime
    } 
    $logHashTable | ConvertTo-Json | Write-LogInformation
    exit $checkResult
}

. $(Join-Path $commonLibPath "Constants.ps1");
. $(Join-Path $commonLibPath "Utils.ps1");
. $(Join-Path $commonLibPath "Log.ps1");
. $(Join-Path $commonLibPath "InstallPackages.ps1");
. $(Join-Path $commonLibPath "AggregateUtils.ps1");


# Check variables required by log.sh functions
$requiredVarName = @('CheckResultMetricsName', 'CheckToolName', 'CheckStartTime')
if (!(Confirm-SetVariable -VariableNames $requiredVarName)) {
    $checkEndTime = Get-CurrentTimestamp
    Write-LogCheckResultAndExit -Message 'Required log parameters are not set. Exiting.' -MetricsValue $CHECK_FAILURE_INVALID_ARG -CheckEndTime $checkEndTime
}

# Install Az modules
$installRetCode = Install-ModuleWithChecks -ModuleName 'Az.Accounts' -RetryTime 2 -SleepSec 5
if (!$installRetCode) {
    $checkEndTime = Get-CurrentTimestamp
    Write-LogError -Message "Failed to install Az.Accounts module." -CheckEndTime $checkEndTime
    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_DEPENDENT_TOOL -CheckEndTime $checkEndTime
}

$installRetCode = Install-ModuleWithChecks -ModuleName 'Az.Compute' -RetryTime 2 -SleepSec 5
if (!$installRetCode) {
    $checkEndTime = Get-CurrentTimestamp
    Write-LogError -Message "Failed to install Az.Compute module." -CheckEndTime $checkEndTime
    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_DEPENDENT_TOOL -CheckEndTime $checkEndTime
}

$installRetCode = Install-ModuleWithChecks -ModuleName 'Az.Monitor' -RetryTime 2 -SleepSec 5
if (!$installRetCode) {
    $checkEndTime = Get-CurrentTimestamp
    Write-LogError -Message "Failed to install Az.Monitor module." -CheckEndTime $checkEndTime
    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_DEPENDENT_TOOL -CheckEndTime $checkEndTime
}

$installRetCode = Install-ModuleWithChecks -ModuleName 'Az.Storage' -RetryTime 2 -SleepSec 5
if (!$installRetCode) {
    $checkEndTime = Get-CurrentTimestamp
    Write-LogError -Message "Failed to install Az.Storage module." -CheckEndTime $checkEndTime
    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_DEPENDENT_TOOL -CheckEndTime $checkEndTime
}

# Import Az modules
try{
    Import-Module Az.Accounts
    Write-LogInformation -Message "Az.Accounts module imported successfully."
}
catch{
    $checkEndTime = Get-CurrentTimestamp
    Write-LogError -Message "Failed to import Az.Accounts module. Exception: $_." -CheckEndTime $checkEndTime
    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_DEPENDENT_TOOL -CheckEndTime $checkEndTime
}
try{
    Import-Module Az.Compute
    Write-LogInformation -Message "Az.Compute module imported successfully."
}
catch{
    $checkEndTime = Get-CurrentTimestamp
    Write-LogError -Message "Failed to import Az.Compute module. Exception: $_." -CheckEndTime $checkEndTime
    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_DEPENDENT_TOOL -CheckEndTime $checkEndTime
}

try{
    Import-Module Az.Monitor
    Write-LogInformation -Message "Az.Monitor module imported successfully."
}
catch{
    $checkEndTime = Get-CurrentTimestamp
    Write-LogError -Message "Failed to import Az.Monitor module. Exception: $_." -CheckEndTime $checkEndTime
    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_DEPENDENT_TOOL -CheckEndTime $checkEndTime
}

try{
    Import-Module Az.Storage
    Write-LogInformation -Message "Az.Storage module imported successfully."
}
catch{
    $checkEndTime = Get-CurrentTimestamp
    Write-LogError -Message "Failed to import Az.Storage module. Exception: $_." -CheckEndTime $checkEndTime
    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_DEPENDENT_TOOL -CheckEndTime $checkEndTime
}

#=========================================
# Customized check logic - Snowflake
#=========================================

# Common items
$hostName = [Environment]::MachineName
$OSTemp = [System.IO.Path]::GetTempPath()

Write-LogInformation -Message "accountId: $accountId on $hostName"
Write-LogInformation -Message "subscriptionId: $subscriptionId on $hostName"
Connect-AzAccount -identity -AccountId $accountId -SubscriptionId $subscriptionId > connectaz.log

# Connect to Azure and set context as UMI
Connect-AzAccount -identity -AccountId $accountId -SubscriptionId $subscriptionId

#=========================================
# Cleanup operations of previous downloaded temp files
If ($hostName -like "$clientVmPrefix*") {
    Write-LogInformation -Message "Client VM type on $hostName"
	Write-LogInformation -Message "Perform .parquet file cleanup before downloads on $hostName"
	cd /tmp/parquet
	rm *.parquet
	rm *.txt
	rm *.log
}

# Prepare parquet testing directory if not exist
$parquetDir = "${OSTemp}parquet"
If (!(Test-Path -Path $parquetDir)) {
    New-Item -ItemType Directory -Path $parquetDir
}

#=========================================
# Create file hash comparison CSV if not exist

If ($hostName -like "$clientVmPrefix*") {
    Write-LogInformation -Message "Client VM type on $hostName"
	Write-LogInformation -Message "Perform file hash file create if not exist on $hostName"

    $fileHashCSVFilePath = "${OSTemp}parquet/fileHash.csv"

    If (-not (Test-Path $fileHashCSVFilePath)) {
	    $header = "file,hash"
        Set-Content -Path $fileHashCSVFilePath -Value $header
        $fileHashCSVFileExist = "false"
    } else {
        $fileHashCSVFileExist = "true"
    }
}

#=========================================
# Perform read test (downloads) to client VMs
$curlBin = "/usr/local/bin/curl"

If ($hostName -like "$clientVmPrefix*") {
    Write-LogInformation -Message "Client VM type on $hostName"
    Write-LogInformation -Message "Perform read test (downloads) to client VMs on $hostName"

    try {

	    # Get storage account names like RG and add to array
        $storageAccountsFilter = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -like "$storageAccountName*" }
        $storageAccounts = $storageAccountsFilter | Select-Object -ExpandProperty StorageAccountName

	    $blobURLsString=@()

        ForEach ($itemStg in $storageAccounts) {
		    $storageContext = New-AzStorageContext -StorageAccountName $itemStg -UseConnectedAccount
		    $blobsFilter = Get-AzStorageBlob -Container "read" -Context $storageContext | Where-Object { $_.Name -like "*.parquet" }
		    $blobs = $blobsFilter | Select-Object -ExpandProperty Name		
		    ForEach ($itemBlob in $blobs) {
			    $blobURLsString +="https://${itemStg}.blob.core.windows.net/read/${itemBlob}"
		    }
	    }

	    $blobURLsString > "${OSTemp}parquet/curlConfig.txt"
	    shuf "${OSTemp}parquet/curlConfig.txt" > "${OSTemp}parquet/shufCurlConfig.txt"

        # Obtain access token for Curl to use based on user managed identity
        $resource = "https://storage.azure.com/" # generic URL for storage
        $accountId = $accountId # AppId for UMI

        $maxRetries = 3
        $retryCount = 0
        $tokenResponse = $null
        while ($retryCount -lt $maxRetries -and $tokenResponse -eq $null) {
            try {
                $tokenResponse = Invoke-RestMethod -Method Get -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01" -Headers @{Metadata="true"} -Body @{resource=$resource; client_id=$accountId}
            }
            catch {
                Write-LogError -Message "Failed to obtain access token. Attempt $($retryCount + 1) of $maxRetries. Exception: $_."
                Start-Sleep -Seconds 5
                $retryCount++
            }
        }
        if ($tokenResponse -eq $null) {
            $checkEndTime = Get-CurrentTimestamp
            Write-LogError -Message "Failed to obtain access token after $maxRetries attempts." -CheckEndTime $checkEndTime
            Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_WITH_ERROR -CheckEndTime $checkEndTime
        }
        $accessToken = $tokenResponse.access_token

	    Write-LogInformation -Message "Downloading parquet files with Curl START on $hostName"

        # Curl start time
	    $curlStartTime = Get-Date

        # Download with Curl all files in parallel
        cd "${OSTemp}parquet"
	    $curlDownloadsLog = "${OSTemp}parquet/curlDownloads.log"
	    cat "${OSTemp}parquet/shufCurlConfig.txt" | xargs -n 1 -P 10 $curlBin -O -H "Authorization: Bearer $accessToken" -H "x-ms-version: 2020-04-08" --write-out "%{url_effective} %{size_download} %{speed_download} bytes/sec\n" >> "$curlDownloadsLog" -s
	
	    Write-LogInformation -Message "Downloading parquet files with Curl END on $hostName"

        # Curl end time
	    $curlEndTime = Get-Date

	    $curlTimeSpan = New-TimeSpan -Start $curlStartTime -End $curlEndTime
	    $curlTimeElapsed = $curlTimeSpan.TotalSeconds
	
	    # Sleep for 15 seconds between file downloads and hash comparisons
	    Write-LogInformation -Message "Sleeping 15 seconds between file downloads and file hash comparisons on $hostName"	
	    Start-Sleep -Seconds 15
    }
    catch {
	    Write-LogError -Message "Unexpected exception occured when running the checktool" -CheckEndTime Get-CurrentTimestamp
	    $checkEndTime = Get-CurrentTimestamp
	    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_WITH_ERROR -CheckEndTime $checkEndTime
    }
}
		
#=========================================
# Perform file hash comparison on client VMs

If ($hostName -like "$clientVmPrefix*") {
	Write-LogInformation -Message "Client VM type on $hostName"
	Write-LogInformation -Message "Perform file hash comparison on client VMs"
	
    try {
	
        # File hash writing
        If ($fileHashCSVFileExist -eq "false") {

            ForEach ($itemFile in $fileArray) {
                $joinFileHash = Join-Path -Path "${OSTemp}parquet" -ChildPath $itemFile
		        $localFileHash = (Get-FileHash $joinFileHash -Algorithm MD5).Hash

		        # write the file hash into a .csv file that can be compared against going forward
		        Add-Content -Path $fileHashCSVFilePath -Value "$itemFile,$localFileHash"
            }
        } elseif ($fileHashCSVFileExist -eq "true") {

            $importCSV = Import-Csv -Path $fileHashCSVFilePath
            # Convert CSV to a Hashtable for fast lookup
            $fileHashCSVHashTable = @{}
            foreach ($row in $importCSV) {
                $fileHashCSVHashTable[$row.file] = $row.hash
            }

            # Directory where downloaded files are stored
            $parquetFilesFolder = "${OSTemp}parquet"

            # Get all downloaded files
            $parquetFiles = Get-ChildItem -Path $parquetFilesFolder -Filter "*.parquet" -File

            ForEach ($parquetFile in $parquetFiles) {
                $parquetFilePath = $parquetFile.FullName
                $parquetFileName = $parquetFile.Name

                if ($fileHashCSVHashTable.ContainsKey($parquetFileName)) {
                    $computedHash = (Get-FileHash -Path $parquetFilePath -Algorithm MD5).Hash
	                $fileHashCSVHashTableHash = $fileHashCSVHashTable[$parquetFileName]
	                    if ($computedHash -ne $fileHashCSVHashTableHash) {
                            $checkEndTime = Get-CurrentTimestamp
                            Write-LogError -Message "Hashes do NOT match for $parquetFileName Local file: $computedHash - csvFileHash: $fileHashCSVHashTableHash" -CheckEndTime $checkEndTime
				            Write-LogInformation -Message "Perform .parquet file hash CSV file reset on $hostName"
				            cd "${OSTemp}parquet"
				            rm fileHash.csv
                            Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_WITH_ERROR -CheckEndTime $checkEndTime
	                    }
                } else {
                    $checkEndTime = Get-CurrentTimestamp
				    Write-LogError -Message "File does not exist in hash table $parquetFileName" -CheckEndTime $checkEndTime
				    Write-LogInformation -Message "Perform .parquet file hash CSV file reset on $hostName"
				    cd "${OSTemp}parquet"
				    rm fileHash.csv
				    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_WITH_ERROR -CheckEndTime $checkEndTime
                }
            }
	    }
    }	
    catch {
		    Write-LogError -Message "Unexpected exception occured when running the checktool" -CheckEndTime Get-CurrentTimestamp
		    $checkEndTime = Get-CurrentTimestamp
		    Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_WITH_ERROR -CheckEndTime $checkEndTime
    }
}

#=========================================
# Get network throughput metrics on client VMs

If ($hostName -like "$clientVmPrefix*") {
	Write-LogInformation -Message "Get network throughput metrics"
	
    try {	
	    $curlDownloadsData = Get-Content $curlDownloadsLog
	    $curlTotalDownloadSize = 0
	    $curlTotalDownloadFiles = 0
	    $curlBwArray = @()
	
	    foreach ($line in $curlDownloadsData) {
		    $parts = $line -split ' '
		    if ($parts.Count -ge 2) {
			    $fileSize = [long]$parts[1]
			    $curlTotalDownloadSize += $fileSize
			    $curlTotalDownloadFiles ++
			    $curlBw = ([long]$parts[2] * 8) / 1000000
			    $curlBwArray += $curlBW	
		    }
	    }
        # Total download size using parallel downloads
	    $curlTotalDownloadSizeMB = [math]::Round($curlTotalDownloadSize / 1MB, 2)
        # Total throughput using parallel downloads
	    $curlNetworkThroughputTotal_Parallel = ($curlTotalDownloadSizeMB / $curlTimeElapsed) * 8

        # Curl reported per file throughput (not taking into account parallel requests)
	    $curlBw_Agg = Get-AggregatedMetrics $curlBwArray
	    $curlBwArrayMin = $curlBw_Agg.Min
	    $curlBwArrayMax = $curlBw_Agg.Max
	    $curlBwArrayAvg = $curlBw_Agg.Average
	    $curlBwArrayMed = $curlBw_Agg.Median	
	    $curlBw_P25 = (Get-Percentile -numbers $curlBwArray -percentile 25)
	    $curlBw_P50 = (Get-Percentile -numbers $curlBwArray -percentile 50)
	    $curlBw_P90 = (Get-Percentile -numbers $curlBwArray -percentile 90)
	    $curlBw_P99 = (Get-Percentile -numbers $curlBwArray -percentile 99)
	    $curlBw_P999 = (Get-Percentile -numbers $curlBwArray -percentile 99.9)
	
	    # Log check result
        $status="Success"
        $checkEndTime = Get-CurrentTimestamp
	    Write-LogInformation "Snowflake checktool succeeded - Perform read test - $checkEndTime"

    }
    catch {
        Write-LogError -Message "Unexpected exception occured when running the checktool" -CheckEndTime Get-CurrentTimestamp
	    $checkEndTime = Get-CurrentTimestamp
        Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_WITH_ERROR -CheckEndTime $checkEndTime
    }
}

#=========================================
# Get storage latency metrics from client VMs

If ($hostName -like "$clientVmPrefix*") {
    Write-LogInformation -Message "Client VM type on $hostName"
    Write-LogInformation -Message "Perform storage latency test to Storage Accounts on $hostName"

    try {	
	    # Regress 60 seconds to $curlStartTime if less than 60 to allow Get-AzMetric small tests to function (fails if less than 1 minute sample)
	    If ($curlTimeElapsed -lt 60) {
		    Write-LogInformation -Message "Moving curlStartTime back 60 seconds to impact Get-AzMetric on $hostName"
		    $curlStartTime = $curlStartTime.AddSeconds(-60)
	    }

        $E2ELatencyMetricAverageLatencyArray = @()
        $serverLatencyMetricAverageLatencyArray = @()

        ForEach ($itemStg in $storageAccounts) {
            $storageContext = New-AzStorageContext -StorageAccountName $itemStg -UseConnectedAccount
            $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $itemStg }
            $storageAccountRG = $storageAccount.ResourceGroupName
            $resourceId = (Get-AzStorageAccount -ResourceGroupName $storageAccountRG -Name $itemStg).Id
            $interval = "00:01:00"  # 1 minute granularity

            $E2ELatency = Get-AzMetric -ResourceId $resourceId -MetricName "SuccessE2ELatency" -AggregationType Average -TimeGrain $interval -StartTime $curlStartTime -EndTime $curlEndTime	
            $serverLatency = Get-AzMetric -ResourceId $resourceId -MetricName "SuccessServerLatency" -AggregationType Average -TimeGrain $interval -StartTime $curlStartTime -EndTime $curlEndTime	

            $E2ELatencyAvgArray += ($E2ELatency.Data | Measure-Object -Property Average -Average).Average
            $E2ELatencyMaxArray += ($E2ELatency.Data | Measure-Object -Property Average -Maximum).Maximum
            $serverLatencyAvgArray += ($serverLatency.Data | Measure-Object -Property Average -Average).Average
            $serverLatencyMaxArray += ($serverLatency.Data | Measure-Object -Property Average -Maximum).Maximum
	
        }
    	    $E2ELatencyAvgArrayAvg = ($E2ELatencyAvgArray | Measure-Object -Average).Average
		    $E2ELatencyMaxArrayMax = ($E2ELatencyMaxArray | Measure-Object -Maximum).Maximum
    	    $serverLatencyAvgArrayAvg = ($serverLatencyAvgArray | Measure-Object -Average).Average
		    $serverLatencyMaxArrayMax = ($serverLatencyMaxArray | Measure-Object -Maximum).Maximum

	
        # Log check result
        $status="Success"
        $checkEndTime = Get-CurrentTimestamp
	    Write-LogInformation "Snowflake checktool succeeded - Storage read latency from Storage Accounts - $checkEndTime"

    }
    catch {
        Write-LogError -Message "Unexpected exception occured when running the checktool" -CheckEndTime Get-CurrentTimestamp
	    $checkEndTime = Get-CurrentTimestamp
        Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_WITH_ERROR -CheckEndTime $checkEndTime
    }
}

#=========================================
# Metrics writing to Kusto

If ($hostName -like "$clientVmPrefix*") {
    Write-LogInformation -Message "Metrics writing/uploading on $hostName"
	Write-LogInformation -Message "Data for metrics: Total Download Size - $curlTotalDownloadSizeMB on $hostName"
	Write-LogInformation -Message "Data for metrics: Time Elapsed - $curlTimeElapsed on $hostName"
	Write-LogInformation -Message "Data for metrics: Total Download Files - $curlTotalDownloadFiles on $hostName"

    try {

	    # Network throughput from client VM
        Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputTotal_Parallel" -MetricsUnit "Mbps" -MetricsValue $curlNetworkThroughputTotal_Parallel -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }
	    Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputFile_Minimum" -MetricsUnit "Mbps" -MetricsValue $curlBwArrayMin -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }
	    Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputFile_Maximum" -MetricsUnit "Mbps" -MetricsValue $curlBwArrayMax -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }
	    Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputFile_Average" -MetricsUnit "Mbps" -MetricsValue $curlBwArrayAvg -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }
	    Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputFile_Median" -MetricsUnit "Mbps" -MetricsValue $curlBwArrayMed -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }
	    Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputFile_P25" -MetricsUnit "Mbps" -MetricsValue $curlBw_P25 -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }
	    Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputFile_P50" -MetricsUnit "Mbps" -MetricsValue $curlBw_P50 -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }
	    Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputFile_P90" -MetricsUnit "Mbps" -MetricsValue $curlBw_P90 -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }
	    Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputFile_P99" -MetricsUnit "Mbps" -MetricsValue $curlBw_P99 -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }
	    Write-LogMetricsWithCustomProps -MetricsName "NetworkThroughputFile_P999" -MetricsUnit "Mbps" -MetricsValue $curlBw_P999 -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostName }

	    # Storage read latency from client VM	
        Write-LogMetricsWithCustomProps -MetricsName "StorageLatency_E2ELatency_Avg_Avg" -MetricsUnit $METRIC_UNIT_MilliSeconds -MetricsValue $E2ELatencyAvgArrayAvg -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostname }
        Write-LogMetricsWithCustomProps -MetricsName "StorageLatency_E2ELatency_Max_Max" -MetricsUnit $METRIC_UNIT_MilliSeconds -MetricsValue $E2ELatencyMaxArrayMax -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostname }
        Write-LogMetricsWithCustomProps -MetricsName "StorageLatency_serverLatency_Avg_Avg" -MetricsUnit $METRIC_UNIT_MilliSeconds -MetricsValue $serverLatencyAvgArrayAvg -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostname }
        Write-LogMetricsWithCustomProps -MetricsName "StorageLatency_serverLatency_Max_Max" -MetricsUnit $METRIC_UNIT_MilliSeconds -MetricsValue $serverLatencyMaxArrayMax -CheckEndTime $checkEndTime -ThresholdType "Upper" -Props @{"Source" = $hostname }

        # Log check result
        $status="Success"
        $checkEndTime = Get-CurrentTimestamp
	    Write-LogInformation "Snowflake checktool succeeded - Metrics generation - $checkEndTime"

    }
    catch {
        Write-LogError -Message "Unexpected exception occured when running the checktool" -CheckEndTime Get-CurrentTimestamp
	    $checkEndTime = Get-CurrentTimestamp
        Write-LogCheckResultAndExit -MetricsValue $CHECK_FAILURE_WITH_ERROR -CheckEndTime $checkEndTime
    }
}

