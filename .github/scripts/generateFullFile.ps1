<#
.SYNOPSIS
This script generates a full file by combining multiple metrics.json files.

.DESCRIPTION
The script takes two mandatory parameters: $path and $outputPath. It searches for metrics.json files recursively in the specified $path directory and combines their contents into a single JSON file at the $outputPath.

.PARAMETER path
Specifies the directory path where the metrics.json files are located.

.PARAMETER outputPath
Specifies the path of the output file where the combined JSON data will be saved. This file will contain the combined contents of all metrics.json files found in the specified $path directory.

.EXAMPLE
Generate-FullFile -path "C:\metrics" -outputPath "C:\combinedMetrics.json"
This example generates a full file by combining all metrics.json files found in the "C:\metrics" directory and saves the output to "C:\combinedMetrics.json".
#>

param (
    [Parameter(Mandatory=$true)][string]$path,
    [Parameter(Mandatory=$true)][string]$outputPath
)

$allJson = @()

Get-ChildItem -Path $path -Recurse -Filter metrics.json | ForEach-Object {
    $json = Get-Content $_.FullName | ConvertFrom-Json
    $allJson += $json
}

$allJson | ConvertTo-JSON | Set-Content -Path $outputPath -Force