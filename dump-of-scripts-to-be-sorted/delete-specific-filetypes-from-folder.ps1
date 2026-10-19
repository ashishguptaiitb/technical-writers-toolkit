# PowerShell script to delete image files and .txt files recursively
# More to delete are PDF, JSON, CSV, XLSX, ZIP, MP4, and INI files.
<#
Basic usage: Delete with confirmation

.\DeleteFiles.ps1 -FolderPath "C:\Your\Folder\Path"

Dry run: Just Preview what would get deleted without actually deleting files:

.\DeleteFiles.ps1 -FolderPath "C:\Your\Folder\Path" -WhatIf


Daring run: No confirmation, just delete files:

.\DeleteFiles.ps1 -FolderPath "C:\Your\Folder\Path" -Confirm:$false

No arguments run: Execute script without providing arguments. Define the value of `$folderPath` variable as your fixed folder path.
$folderPath = C:\Your\Folder\Path

#>

$folderPath = "C:\Users\Ashish.Gupta\Documents\GitHub"

param(
    [Parameter(Mandatory=$true)]
    [string]$FolderPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Confirm = $true
)

# Define file extensions to delete
$imageExtensions = @(
    "*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.tiff", "*.tif", 
    "*.webp", "*.svg", "*.ico", "*.raw", "*.cr2", "*.nef", "*.arw", 
    "*.dng", "*.psd", "*.ai", "*.eps", "*.heic", "*.heif", "*.avif"
)

$textExtensions = @("*.txt")

# Combine all extensions
$allExtensions = $imageExtensions + $textExtensions

# Validate folder path exists
if (-not (Test-Path -Path $FolderPath)) {
    Write-Error "Folder path does not exist: $FolderPath"
    exit 1
}

Write-Host "Scanning folder: $FolderPath" -ForegroundColor Cyan
Write-Host "Extensions to delete: $($allExtensions -join ', ')" -ForegroundColor Yellow

# Find all files matching the extensions
$filesToDelete = @()
foreach ($extension in $allExtensions) {
    $files = Get-ChildItem -Path $FolderPath -Filter $extension -Recurse -File
    $filesToDelete += $files
}

if ($filesToDelete.Count -eq 0) {
    Write-Host "No files found matching the specified extensions." -ForegroundColor Green
    exit 0
}

# Group files by extension for summary
$fileGroups = $filesToDelete | Group-Object Extension | Sort-Object Name

Write-Host "`nFiles found:" -ForegroundColor Cyan
foreach ($group in $fileGroups) {
    Write-Host "  $($group.Name): $($group.Count) files" -ForegroundColor White
}

Write-Host "`nTotal files to delete: $($filesToDelete.Count)" -ForegroundColor Red

# Show what will be deleted if WhatIf is specified
if ($WhatIf) {
    Write-Host "`n--- WHAT-IF MODE: No files will actually be deleted ---" -ForegroundColor Magenta
    foreach ($file in $filesToDelete | Sort-Object FullName) {
        Write-Host "Would delete: $($file.FullName)" -ForegroundColor Yellow
    }
    exit 0
}

# Confirm deletion unless -Confirm:$false is specified
if ($Confirm) {
    $response = Read-Host "`nAre you sure you want to DELETE these $($filesToDelete.Count) files? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y' -and $response -ne 'yes') {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        exit 0
    }
}

# Delete the files
$deletedCount = 0
$errorCount = 0

Write-Host "`nDeleting files..." -ForegroundColor Red

foreach ($file in $filesToDelete) {
    try {
        Remove-Item -Path $file.FullName -Force
        Write-Host "Deleted: $($file.FullName)" -ForegroundColor Green
        $deletedCount++
    }
    catch {
        Write-Error "Failed to delete $($file.FullName): $($_.Exception.Message)"
        $errorCount++
    }
}

# Summary
Write-Host "`n--- OPERATION SUMMARY ---" -ForegroundColor Cyan
Write-Host "Successfully deleted: $deletedCount files" -ForegroundColor Green
if ($errorCount -gt 0) {
    Write-Host "Failed to delete: $errorCount files" -ForegroundColor Red
}
Write-Host "Operation completed." -ForegroundColor Cyan