# PowerShell script to find unused assets in Markdown files
# Sample run:  .\find-unused-assets.ps1 -AssetListFile "complete-asset-listing-in-a-repo.txt" -MarkdownFolderPath "path-of-parent-folder-with-md-files"
#
# Sample run: .\find-unused-assets.ps1 -AssetListFile ".\xo-total-assests.txt" -MarkdownFolderPath "xo"

param(
    [Parameter(Mandatory = $true)]
    [string]$MarkdownFolderPath,

    [Parameter(Mandatory = $true)]
    [string]$AssetListFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "unused_assets.txt",

    [Parameter(Mandatory = $false)]
    [switch]$CaseSensitive = $false,

    [Parameter(Mandatory = $false)]
    [switch]$ShowVerbose = $false
)

# ----------------------------
# Validate input parameters
# ----------------------------
if (-not (Test-Path -Path $MarkdownFolderPath)) {
    Write-Error "Markdown folder path does not exist: $MarkdownFolderPath"
    exit 1
}

if (-not (Test-Path -Path $AssetListFile)) {
    Write-Error "Asset list file does not exist: $AssetListFile"
    exit 1
}

Write-Host "Starting asset usage analysis..." -ForegroundColor Cyan
Write-Host "Markdown folder: $MarkdownFolderPath" -ForegroundColor White
Write-Host "Asset list file: $AssetListFile" -ForegroundColor White
Write-Host "Output file: $OutputFile" -ForegroundColor White
Write-Host "Case sensitive: $CaseSensitive" -ForegroundColor White

# ----------------------------
# Read asset list
# ----------------------------
try {
    $assetList = Get-Content -Path $AssetListFile |
                 Where-Object { $_.Trim() -ne "" }

    Write-Host "`nFound $($assetList.Count) assets to check" -ForegroundColor Green
}
catch {
    Write-Error "Failed to read asset list file: $($_.Exception.Message)"
    exit 1
}

# ----------------------------
# Collect Markdown files
# ----------------------------
$markdownFiles = Get-ChildItem -Path $MarkdownFolderPath -Recurse -File -Filter "*.md"

if ($markdownFiles.Count -eq 0) {
    Write-Warning "No Markdown files found in $MarkdownFolderPath"
    exit 0
}

Write-Host "Found $($markdownFiles.Count) Markdown files to search" -ForegroundColor Green

# ----------------------------
# Read Markdown content
# ----------------------------
Write-Host "`nReading Markdown files..." -ForegroundColor Yellow
$allMarkdownContent = ""
$fileReadErrors = @()

foreach ($file in $markdownFiles) {
    try {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $allMarkdownContent += "`n" + $content

        if ($ShowVerbose) {
            Write-Host "  Read: $($file.Name)" -ForegroundColor Gray
        }
    }
    catch {
        $fileReadErrors += "Failed to read $($file.FullName): $($_.Exception.Message)"
    }
}

if ($fileReadErrors.Count -gt 0) {
    Write-Warning "Encountered $($fileReadErrors.Count) file read errors:"
    $fileReadErrors | ForEach-Object { Write-Warning "  $_" }
}

# ----------------------------
# Asset usage check
# ----------------------------
Write-Host "`nChecking asset usage..." -ForegroundColor Yellow
$unusedAssets = @()
$usedAssets   = @()

foreach ($asset in $assetList) {
    $assetName = $asset.Trim()
    if ([string]::IsNullOrEmpty($assetName)) {
        continue
    }

    if ($CaseSensitive) {
        $isUsed = $allMarkdownContent.Contains($assetName)
    }
    else {
        $isUsed = $allMarkdownContent.ToLower().Contains($assetName.ToLower())
    }

    if ($isUsed) {
        $usedAssets += $assetName
        if ($ShowVerbose) {
            Write-Host "  USED: $assetName" -ForegroundColor Green
        }
    }
    else {
        $unusedAssets += $assetName
        if ($ShowVerbose) {
            Write-Host "  UNUSED: $assetName" -ForegroundColor Red
        }
    }
}

# ----------------------------
# Output results
# ----------------------------
Write-Host "`nANALYSIS RESULTS" -ForegroundColor Cyan
Write-Host "Total assets checked: $($assetList.Count)" -ForegroundColor White
Write-Host "Used assets: $($usedAssets.Count)" -ForegroundColor Green
Write-Host "Unused assets: $($unusedAssets.Count)" -ForegroundColor Red

if ($unusedAssets.Count -eq 0) {
    Write-Host "`nAll assets are being used." -ForegroundColor Green
    "" | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "Empty output file created: $OutputFile" -ForegroundColor Green
}
else {
    $unusedAssets | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "`nUnused assets written to $OutputFile" -ForegroundColor Yellow
}

Write-Host "`nAnalysis completed." -ForegroundColor Cyan
