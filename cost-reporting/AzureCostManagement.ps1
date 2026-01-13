
# =================================================
# Azure Monthly Cost Report (Storage & Disks)
# =================================================

# -------------------------------------------------
# 1. Login to Azure
# -------------------------------------------------
try {
    if (-not (Get-AzContext)) {
        Write-Host "Signing in to Azure..." -ForegroundColor Cyan
        Connect-AzAccount | Out-Null
    }
} catch {
    Write-Error "Failed to authenticate to Azure: $_"
    exit 1
}

# -------------------------------------------------
# 2. Output file configuration
# -------------------------------------------------
$OutputPath = "$env:USERPROFILE\Documents"
$OutputFile = Join-Path $OutputPath "AzureCosts_$(Get-Date -Format yyyyMMdd).csv"

# -------------------------------------------------
# 3. Calculate last full month
# -------------------------------------------------
$Today = Get-Date
$FirstDayThisMonth = Get-Date -Year $Today.Year -Month $Today.Month -Day 1
$FromDate = $FirstDayThisMonth.AddMonths(-1)
$ToDate = $FirstDayThisMonth.AddDays(-1)

Write-Host "Reporting period: $($FromDate.ToString('yyyy-MM-dd')) to $($ToDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan

# -------------------------------------------------
# 4. Cost Management query settings
# -------------------------------------------------
$Aggregation = @{
    totalCost = @{
        name     = 'Cost'
        function = 'Sum'
    }
}

$Grouping = @(
    @{ type = 'Dimension'; name = 'ResourceId' }
)

# -------------------------------------------------
# 5. Helper function to query cost by resource type
# -------------------------------------------------
function Get-CostByResourceType {
    param (
        [Parameter(Mandatory)]
        [string]$SubscriptionId,

        [Parameter(Mandatory)]
        [string]$ResourceType
    )

    # Compatible with older Az.CostManagement versions
    $Dimension = New-AzCostManagementQueryComparisonExpressionObject `
        -Name 'ResourceType' `
        -Value $ResourceType

    $Filter = New-AzCostManagementQueryFilterObject -Dimensions $Dimension

    Invoke-AzCostManagementQuery `
        -Scope "/subscriptions/$SubscriptionId" `
        -Type 'ActualCost' `
        -Timeframe 'Custom' `
        -TimePeriodFrom $FromDate `
        -TimePeriodTo $ToDate `
        -DatasetAggregation $Aggregation `
        -DatasetGrouping $Grouping `
        -DatasetGranularity 'None' `
        -DatasetFilter $Filter
}

# -------------------------------------------------
# 6. Get enabled subscriptions
# -------------------------------------------------
$Subscriptions = Get-AzSubscription | Where-Object State -eq 'Enabled'
$Results = @()

foreach ($Sub in $Subscriptions) {

    Write-Host "Processing subscription: $($Sub.Name)" -ForegroundColor Yellow
    Select-AzSubscription -SubscriptionId $Sub.Id | Out-Null

    # ---------------------------------------------
    # Storage Account metadata
    # ---------------------------------------------
    $StorageMap = @{}
    foreach ($SA in Get-AzStorageAccount) {
        $Rid = ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Storage/storageAccounts/{2}" -f `
                $Sub.Id, $SA.ResourceGroupName, $SA.StorageAccountName).ToLower()
        $StorageMap[$Rid] = $SA
    }

    # ---------------------------------------------
    # Managed Disk metadata
    # ---------------------------------------------
    $DiskMap = @{}
    foreach ($Disk in Get-AzDisk) {
        $Rid = ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/disks/{2}" -f `
                $Sub.Id, $Disk.ResourceGroupName, $Disk.Name).ToLower()
        $DiskMap[$Rid] = $Disk
    }

    # ---------------------------------------------
    # Helper to parse cost data
    # ---------------------------------------------
    function Add-CostResults {
        param (
            $QueryResult,
            [string]$ResourceType,
            [hashtable]$MetadataMap
        )

        if (-not $QueryResult.Rows) { return }

        $CostIndex = ($QueryResult.Columns | Where-Object Name -eq 'Cost').Index
        $IdIndex   = ($QueryResult.Columns | Where-Object Name -eq 'ResourceId').Index
        $CurIndex  = ($QueryResult.Columns | Where-Object Name -eq 'Currency').Index

        foreach ($Row in $QueryResult.Rows) {
            $ResourceId = $Row[$IdIndex].ToLower()

            if ($MetadataMap.ContainsKey($ResourceId)) {
                $Meta = $MetadataMap[$ResourceId]

                $Results += [PSCustomObject]@{
                    SubscriptionName = $Sub.Name
                    SubscriptionId   = $Sub.Id
                    ResourceType     = $ResourceType
                    Name             = $Meta.Name
                    ResourceGroup    = $Meta.ResourceGroupName
                    Location         = $Meta.Location
                    SkuName          = if ($ResourceType -eq 'Disk') { $Meta.Sku.Name } else { $Meta.SkuName }
                    LastMonthCost    = [decimal]$Row[$CostIndex]
                    Currency         = $Row[$CurIndex]
                }
            }
        }
    }

    # ---------------------------------------------
    # Run cost queries
    # ---------------------------------------------
    Add-CostResults `
        (Get-CostByResourceType -SubscriptionId $Sub.Id -ResourceType 'Microsoft.Storage/storageAccounts') `
        'StorageAccount' $StorageMap

    Add-CostResults `
        (Get-CostByResourceType -SubscriptionId $Sub.Id -ResourceType 'Microsoft.Compute/disks') `
        'Disk' $DiskMap
}

# -------------------------------------------------
# 7. Export result to CSV
# -------------------------------------------------
$Results |
Sort-Object LastMonthCost -Descending |
Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

Write-Host "✅ Cost report successfully created:" -ForegroundColor Green
Write-Host "   $OutputFile"
