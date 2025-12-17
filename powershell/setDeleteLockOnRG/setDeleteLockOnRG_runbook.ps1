
<#
.SYNOPSIS
  Applies a CanNotDelete lock named 'deleteLock' to all resource groups in the current subscription.

.DESCRIPTION
  Idempotent: if a resource group already has a lock with that name, it is skipped.
  Optionally supports a dry-run mode to preview changes.

.PARAMETER SubscriptionId
  (Optional) Target subscription. If omitted, uses current Az context.

.PARAMETER LockName
  (Optional) Name of the lock to apply. Default: 'deleteLock'

.PARAMETER Notes
  (Optional) Notes stored with the lock.

.PARAMETER WhatIf
  (Switch) If specified, shows what would be changed without making changes.

.EXAMPLE
  .\Apply-RgDeleteLocks.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
  .\Apply-RgDeleteLocks.ps1 -WhatIf
  
#>

param(
  [Parameter(Mandatory=$false)]
  [string] $SubscriptionId,

  [Parameter(Mandatory=$false)]
  [string] $LockName = "deleteLock",

  [Parameter(Mandatory=$false)]
  [string] $AccountId = "e4e2a5e7-4a2c-4aa5-ac48-63ee10bd9a54",

  [Parameter(Mandatory=$false)]
  [string] $Notes = "Auto-applied delete protection at RG scope",

  [switch] $WhatIf
)

function Ensure-AzContext {
  if (-not (Get-AzContext)) {
    Write-Host "No Az context detected. Connecting..." -ForegroundColor Yellow
    Connect-AzAccount -Identity -AccountId $AccountId | Out-Null
  }
  if ($SubscriptionId) {
    Write-Host "Setting context to subscription $SubscriptionId ..." -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
  }
}

function Apply-LockToResourceGroup {
  param(
    [Parameter(Mandatory=$true)][string] $ResourceGroupName,
    [Parameter(Mandatory=$true)][string] $LockName,
    [Parameter(Mandatory=$true)][ValidateSet('CanNotDelete','ReadOnly')] [string] $LockLevel,
    [Parameter(Mandatory=$false)][string] $Notes,
    [switch] $WhatIf
  )

  try {
    # Get all locks at the RG scope
    $existingLocks = Get-AzResourceLock -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

    $existing = $existingLocks | Where-Object { $_.LockName -eq $LockName }
    if ($existing) {
      Write-Host "[$ResourceGroupName] Lock '$LockName' already exists (level: $($existing.LockLevel)). Skipping." -ForegroundColor Green
      return
    }

    $msg = "[$ResourceGroupName] Creating lock '$LockName' (level: $LockLevel)"
    if ($WhatIf) {
      Write-Host "$msg (WhatIf)" -ForegroundColor Yellow
    } else {
      Write-Host $msg -ForegroundColor Cyan
      New-AzResourceLock -LockName $LockName -LockLevel $LockLevel -ResourceGroupName $ResourceGroupName -Force
      Write-Host "[$ResourceGroupName] Lock created." -ForegroundColor Green
    }
  }
  catch {
    Write-Host "[$ResourceGroupName] ERROR: $($_.Exception.Message)" -ForegroundColor Red
  }
}

# AZ context
Ensure-AzContext

# Pull all resource groups in current context
$resourceGroups = Get-AzResourceGroup -ErrorAction Stop
if (-not $resourceGroups) {
  Write-Host "No resource groups found in the current subscription/context." -ForegroundColor Yellow
  return
}

foreach ($rg in $resourceGroups) {
  Apply-LockToResourceGroup `
    -ResourceGroupName $rg.ResourceGroupName `
    -LockName $LockName `
    -LockLevel 'CanNotDelete' `
    -Notes $Notes `
    -WhatIf:$WhatIf
}

Write-Host "Done. Processed $($resourceGroups.Count) resource group(s)." -ForegroundColor Green
