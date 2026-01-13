Azure Monthly Cost Report for Storage Accounts and Managed Disks

This PowerShell script generates a monthly Azure cost report for Storage Accounts and Managed Disks across all enabled subscriptions. The report uses Azure Cost Management APIs and exports results to CSV for governance, cost analysis, and FinOps activities.

Key Features
Automatically calculates the last full billing month.

Queries actual costs using Azure Cost Management.

Supports multiple enabled subscriptions.

Maps cost data to resource metadata.

Exports a sortable CSV report.

Prerequisites
PowerShell 7.x or Windows PowerShell 5.1

Az PowerShell modules

Az.Accounts

Az.CostManagement

Az.Storage

Az.Compute

Azure permissions

Cost Management Reader at subscription scope

Reader on resource groups

Storage Account Reader

Disk Reader

Usage
.\Get-AzureMonthlyStorageAndDiskCost.ps1
