# Compare all-assets.txt with used-assets.txt
# and create a list of assets that are not used.

Clear-Host

Write-Host "=== Unused Assets Finder ===" -ForegroundColor Cyan
Write-Host ""

# Prompt for the all-assets file
$AllAssetsFile = Read-Host "Enter the path to the all-assets .txt file"

# Prompt for the used-assets file
$UsedAssetsFile = Read-Host "Enter the path to the used-assets .txt file"

# Remove surrounding double quotes from the supplied file paths
$AllAssetsFile = $AllAssetsFile.Trim().Trim('"')
$UsedAssetsFile = $UsedAssetsFile.Trim().Trim('"')

# Validate input files
if (-not (Test-Path -LiteralPath $AllAssetsFile -PathType Leaf)) {
    Write-Host "ERROR: all-assets file was not found:" -ForegroundColor Red
    Write-Host $AllAssetsFile
    exit 1
}

if (-not (Test-Path -LiteralPath $UsedAssetsFile -PathType Leaf)) {
    Write-Host "ERROR: used-assets file was not found:" -ForegroundColor Red
    Write-Host $UsedAssetsFile
    exit 1
}

# Read both files
$AllAssets = Get-Content -LiteralPath $AllAssetsFile
$UsedAssets = Get-Content -LiteralPath $UsedAssetsFile

Write-Host ""
Write-Host "Reading asset lists..." -ForegroundColor Yellow

# Normalize each path for comparison:
# - Remove whitespace
# - Remove surrounding double quotes
# - Convert backslashes to forward slashes
# - Remove leading ./ if present
function Normalize-RelativePath {
    param (
        [string]$Path
    )

    $Path = $Path.Trim()
    $Path = $Path.Trim('"')
    $Path = $Path.Replace('\', '/')

    if ($Path.StartsWith("./")) {
        $Path = $Path.Substring(2)
    }

    return $Path
}

# Build a hash set of all used assets.
# HashSet provides efficient lookups for large asset lists.
$UsedAssetSet = New-Object 'System.Collections.Generic.HashSet[string]' (
    [System.StringComparer]::OrdinalIgnoreCase
)

$UsedCount = $UsedAssets.Count
$UsedIndex = 0

foreach ($Asset in $UsedAssets) {

    $UsedIndex++

    Write-Progress `
        -Activity "Reading used-assets" `
        -Status "Processing $UsedIndex of $UsedCount" `
        -PercentComplete (($UsedIndex / $UsedCount) * 100)

    if (-not [string]::IsNullOrWhiteSpace($Asset)) {
        $NormalizedAsset = Normalize-RelativePath $Asset

        if (-not [string]::IsNullOrWhiteSpace($NormalizedAsset)) {
            [void]$UsedAssetSet.Add($NormalizedAsset)
        }
    }
}

Write-Progress -Activity "Reading used-assets" -Completed

# Compare all-assets against used-assets
$UnusedAssets = New-Object System.Collections.Generic.List[string]

$AllCount = $AllAssets.Count
$AllIndex = 0

foreach ($Asset in $AllAssets) {

    $AllIndex++

    Write-Progress `
        -Activity "Finding unused assets" `
        -Status "Processing $AllIndex of $AllCount" `
        -PercentComplete (($AllIndex / $AllCount) * 100)

    if (-not [string]::IsNullOrWhiteSpace($Asset)) {

        $NormalizedAsset = Normalize-RelativePath $Asset

        if (
            -not [string]::IsNullOrWhiteSpace($NormalizedAsset) -and
            -not $UsedAssetSet.Contains($NormalizedAsset)
        ) {
            [void]$UnusedAssets.Add($NormalizedAsset)
        }
    }
}

Write-Progress -Activity "Finding unused assets" -Completed

# Create output file in the same folder as the all-assets file
$OutputDirectory = Split-Path -Parent (Resolve-Path -LiteralPath $AllAssetsFile)
$OutputFile = Join-Path $OutputDirectory "unused-assets.txt"

# Write the unused asset paths
$UnusedAssets | Set-Content -LiteralPath $OutputFile -Encoding UTF8

# Display summary
Write-Host ""
Write-Host "=== Complete ===" -ForegroundColor Green
Write-Host "All assets      : $($AllAssets.Count)"
Write-Host "Used assets     : $($UsedAssetSet.Count)"
Write-Host "Unused assets   : $($UnusedAssets.Count)"
Write-Host ""
Write-Host "Output file:" -ForegroundColor Cyan
Write-Host $OutputFile