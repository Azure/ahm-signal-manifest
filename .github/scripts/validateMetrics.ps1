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
try {
    $objects = Get-Content $metricsFile -Raw | ConvertFrom-Json
    if (-not $objects -or $objects.Count -eq 0) {
        Write-Host "::error file=$metricsFile::Metrics file is empty or contains no valid metrics."
        exit 1
    }
} catch {
    Write-Host "::error file=$metricsFile::Failed to parse JSON file: $($_.Exception.Message)"
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

# Define the expected staticThresholds schema
$staticThresholdsSchema = @{
    degradedThreshold   = [double]
    degradedOperator    = [string]
    unhealthyThreshold  = [double]
    unhealthyOperator   = [string]
}

# Define allowed values for specific properties
$allowedValues = @{
    aggregationType = @("Average","Maximum","Minimum","Total","Count")
    recommended = @($true, $false)
}

# Define allowed operators for thresholds
$allowedOperators = @("GreaterThan", "GreaterOrEquals", "LowerThan", "LowerOrEquals", $null)

# Define allowed units (common Azure Monitor units)
$allowedUnits = @("Percent", "Count", "Seconds", "MilliSeconds", "Bytes", "BytesPerSecond", "CountPerSecond", "BitsPerSecond", $null)

# Define allowed dynamic threshold models
$allowedDynamicModels = @("AnomalyDetection")

# Function to validate timeGrain format (ISO 8601 duration)
function Test-TimeGrain {
    param (
        [string]$timeGrain,
        [string]$metricName,
        [string]$metricsFile
    )
    
    if ($timeGrain -notmatch '^PT\d+[MH]$') {
        Write-Host "::error file=$metricsFile::Invalid timeGrain format '$timeGrain' for metric '$metricName'. Expected format: PT{number}M or PT{number}H (e.g., PT5M, PT1H)."
        return $false
    }
    return $true
}

# Function to validate dynamicThresholds
function Test-DynamicThresholds {
    param (
        [object]$dynamicThresholds,
        [string]$metricName,
        [string]$metricsFile
    )
    
    $isValid = $true
    
    if ($dynamicThresholds -eq $null) {
        return $isValid
    }
    
    # Check if dynamicThresholds is an object
    if ($dynamicThresholds -isnot [PSCustomObject]) {
        Write-Host "::error file=$metricsFile::dynamicThresholds for metric '$metricName' must be an object or null."
        return $false
    }
    
    $dynamicProperties = $dynamicThresholds.PSObject.Properties.Name
    
    # Validate required properties
    $requiredProps = @("sensitivity", "model", "operator")
    foreach ($prop in $requiredProps) {
        if ($dynamicProperties -notcontains $prop) {
            Write-Host "::error file=$metricsFile::dynamicThresholds for metric '$metricName' missing required property '$prop'."
            $isValid = $false
        }
    }
    
    # Validate individual properties
    foreach ($property in $dynamicProperties) {
        switch ($property) {
            "sensitivity" {
                $sensitivityValue = $null
                if (-not ([int]::TryParse($dynamicThresholds.$property, [ref]$sensitivityValue)) -or $sensitivityValue -lt 0 -or $sensitivityValue -gt 2) {
                    Write-Host "::error file=$metricsFile::dynamicThresholds property 'sensitivity' for metric '$metricName' must be an integer between 0 and 2."
                    $isValid = $false
                }
            }
            "model" {
                if ($dynamicThresholds.$property -notin $allowedDynamicModels) {
                    Write-Host "::error file=$metricsFile::dynamicThresholds property 'model' for metric '$metricName' has invalid value '$($dynamicThresholds.$property)'. Allowed values are: $($allowedDynamicModels -join ', ')."
                    $isValid = $false
                }
            }
            "operator" {
                if ($dynamicThresholds.$property -notin $allowedOperators) {
                    Write-Host "::error file=$metricsFile::dynamicThresholds property 'operator' for metric '$metricName' has invalid value '$($dynamicThresholds.$property)'. Allowed values are: $($allowedOperators -join ', ')."
                    $isValid = $false
                }
            }
            default {
                Write-Host "::warning file=$metricsFile::Unknown property '$property' in dynamicThresholds for metric '$metricName'."
            }
        }
    }
    
    return $isValid
}

# Function to validate staticThresholds
function Test-StaticThresholds {
    param (
        [object]$staticThresholds,
        [string]$metricName,
        [string]$metricsFile
    )
    
    $isValid = $true
    
    if ($staticThresholds -eq $null) {
        return $isValid
    }
    
    # Check if staticThresholds is an object/hashtable
    if ($staticThresholds -isnot [PSCustomObject]) {
        Write-Host "::error file=$metricsFile::staticThresholds for metric '$metricName' must be an object or null."
        return $false
    }
    
    # Get all properties of staticThresholds
    $thresholdProperties = $staticThresholds.PSObject.Properties.Name
    
    # Check for required operator-threshold pairs
    $hasUnhealthy = ($thresholdProperties -contains "unhealthyThreshold") -and ($thresholdProperties -contains "unhealthyOperator")
    $hasDegraded = ($thresholdProperties -contains "degradedThreshold") -and ($thresholdProperties -contains "degradedOperator")
    
    if (-not $hasUnhealthy) {
        Write-Host "::error file=$metricsFile::staticThresholds for metric '$metricName' must include both 'unhealthyThreshold' and 'unhealthyOperator'."
        $isValid = $false
    }
      # Validate each threshold property
    foreach ($property in $thresholdProperties) {
        switch ($property) {
            { $_ -in @("degradedThreshold", "unhealthyThreshold") } {
                # Check if it's a numeric value (int, double, decimal, or numeric string)
                # $numericValue = $null
                # if (-not ([double]::TryParse($staticThresholds.$property, [ref]$numericValue))) {
                #     Write-Host "::error file=$metricsFile::staticThresholds property '$property' for metric '$metricName' must be a number."
                #     $isValid = $false
                # }
            }
            { $_ -in @("degradedOperator", "unhealthyOperator") } {
                if ($staticThresholds.$property -notin $allowedOperators) {
                    Write-Host "::error file=$metricsFile::staticThresholds property '$property' for metric '$metricName' has invalid value '$($staticThresholds.$property)'. Allowed values are: $($allowedOperators -join ', ')."
                    $isValid = $false
                }
            }
            default {
                Write-Host "::warning file=$metricsFile::Unknown property '$property' in staticThresholds for metric '$metricName'."
            }
        }
    }
    
    return $isValid
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
    # Validate basic schema properties
    foreach ($property in $schema.Keys) {
        # Check if the property exists
        if ($object.$property -isnot $schema[$property]) {
            Write-Host "::error file=$metricsFile::Invalid schema detected for '$property' in metric '$($object.metricName)'."
            $isSchemaValid = $false
            break
        }

        # Check if the property value is in the allowed values array
        if ($allowedValues.ContainsKey($property) -and $object.$property -notin $allowedValues[$property]) {
            Write-Host "::error file=$metricsFile::Invalid value detected for '$property' in metric '$($object.metricName)'. Set to $($object.$property). Allowed values are $($allowedValues[$property])."
            $isSchemaValid = $false
            break
        }
    }
    
    # Validate timeGrain format
    if ($object.PSObject.Properties.Name -contains "timeGrain") {
        $timeGrainValid = Test-TimeGrain -timeGrain $object.timeGrain -metricName $object.metricName -metricsFile $metricsFile
        if (-not $timeGrainValid) {
            $isSchemaValid = $false
        }
    }
    
    # Validate unit if present
    if ($object.PSObject.Properties.Name -contains "unit") {
        if ($object.unit -notin $allowedUnits) {
            Write-Host "::warning file=$metricsFile::Unusual unit value '$($object.unit)' for metric '$($object.metricName)'. Common units are: $($allowedUnits -ne $null -join ', ')."
        }
    }
    
    # Validate staticThresholds if present
    if ($object.PSObject.Properties.Name -contains "staticThresholds") {
        $staticThresholdsValid = Test-StaticThresholds -staticThresholds $object.staticThresholds -metricName $object.metricName -metricsFile $metricsFile
        if (-not $staticThresholdsValid) {
            $isSchemaValid = $false
        }
    }
    
    # Validate dynamicThresholds if present
    if ($object.PSObject.Properties.Name -contains "dynamicThresholds") {
        $dynamicThresholdsValid = Test-DynamicThresholds -dynamicThresholds $object.dynamicThresholds -metricName $object.metricName -metricsFile $metricsFile
        if (-not $dynamicThresholdsValid) {
            $isSchemaValid = $false
        }
    }
    
    # Validate that at least one threshold type is defined
    $hasStaticThresholds = $object.staticThresholds -ne $null
    $hasDynamicThresholds = $object.dynamicThresholds -ne $null
    
    if (-not $hasStaticThresholds -and -not $hasDynamicThresholds) {
        Write-Host "::warning file=$metricsFile::Metric '$($object.metricName)' has neither staticThresholds nor dynamicThresholds defined."
    }
    
    if ($hasStaticThresholds -and $hasDynamicThresholds) {
        Write-Host "::warning file=$metricsFile::Metric '$($object.metricName)' has both staticThresholds and dynamicThresholds defined. Typically only one should be used."
    }
}

if ($isSchemaValid) {
    $metricCount = $objects.Count
    $staticThresholdCount = ($objects | Where-Object { $_.staticThresholds -ne $null }).Count
    $dynamicThresholdCount = ($objects | Where-Object { $_.dynamicThresholds -ne $null }).Count
    
    Write-Host "Schema validation successful for $metricsFile."
    Write-Host "Validated $metricCount metrics ($staticThresholdCount with static thresholds, $dynamicThresholdCount with dynamic thresholds)."
    Write-Host "Checks performed: Basic schema, unique IDs/metric names, timeGrain format, staticThresholds, dynamicThresholds, and threshold consistency."
} else {
    Write-Host "::error file=$metricsFile::Schema validation failed for $metricsFile."
    exit 1
}