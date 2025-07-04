# validateMetrics.ps1
# Validates the schema of the metrics.json file.
# This script is used by the GitHub Actions workflow.

param (
    [Parameter(Mandatory = $true)]
    [string]$metricsFile
)

# Test if metrics.json exists
if (-not (Test-Path $metricsFile)) {
    Write-Host "::error::Metrics file not found at '$metricsFile'."
    exit 1
}

# Convert JSON to PowerShell objects
$objects = Get-Content $metricsFile | ConvertFrom-Json -NoEnumerate

# Ensure the root of the JSON is an array (strings are also IEnumerable)
if ($objects -isnot [System.Collections.IEnumerable] -or $objects -is [string] -or $objects.Count -eq $null) {
    Write-Host "::error file=$metricsFile::Root JSON element must be an array."
    exit 1
}

# Define the expected schema
$schema = @{
    id                = [string]
    metricNamespace   = [string]
    metricName        = [string]
    aggregationType   = [string]
    timeGrain         = [string]
    # dimensions        = [object] // tbd
    # staticThresholds  = [object] // tbd
    # dynamicThresholds = [object] // tbd
    recommended       = [bool]
}

# Define allowed values for specific properties
$allowedValues = @{
    aggregationType = @("Average","Maximum","Minimum","Total","Count")
    recommended = @($true, $false)
}

# Validate each object against the schema
$isSchemaValid = $true

# Check if metricName is unqiue per metrics.json
$objects | Group-Object -Property metricName | Where-Object { $_.Count -gt 1 } | ForEach-Object {
    Write-Host "::error file=$metricsFile::Duplicate metricName detected for '$($_.Name)'."
    $isSchemaValid = $false
}

# Check if id is unqiue per metrics.json (another check is needed to check that across all files)
$objects | Group-Object -Property id | Where-Object { $_.Count -gt 1 } | ForEach-Object {
    Write-Host "::error file=$metricsFile::Duplicate id detected for '$($_.Name)'."
    $isSchemaValid = $false
}

foreach ($object in $objects) {
    foreach ($property in $schema.Keys) {
        # Check if the property exists
        if ($object.$property -isnot $schema[$property]) {
            Write-Host "::error file=$metricsFile::Invalid schema detected for '$property'."
            $isSchemaValid = $false
            break
        }

        # Check if the property value is in the allowed values array
        if ($allowedValues.ContainsKey($property) -and $object.$property -notin $allowedValues[$property]) {
            Write-Host "::error file=$metricsFile::Invalid value detected for '$property'. Set to $($object.$property). Allowed values are $($allowedValues[$property])."
            $isSchemaValid = $false
            break
        }

    }
}

if ($isSchemaValid) {
    Write-Host "Schema validation successful for $metricsFile."
} else {
    Write-Host "::error file=$metricsFile::Schema validation failed for $metricsFile."
    exit 1
}
