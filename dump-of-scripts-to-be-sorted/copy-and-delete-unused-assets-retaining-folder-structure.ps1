# Provide a .txt file. It must contain full file path, file name, and its extension. Only 1 filepath entry per row. This script will copy the listed files in a separate folder and then it'll delete those files.
# Get the input .txt file from another script to list unused assets.
#
# -InputFile: Provide .txt file containing paths of unused assets to be copied separately and deleted from the GitHub repo.

param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile
)

# ----------------------------
# Setup
# ----------------------------
$ScriptRoot = Get-Location
$DestinationRoot = Join-Path $ScriptRoot "copied-files"

# Create destination folder
if (-not (Test-Path $DestinationRoot)) {
    New-Item -Path $DestinationRoot -ItemType Directory | Out-Null
}

# Validate input file
if (-not (Test-Path $InputFile)) {
    Write-Error "Input file does not exist: $InputFile"
    exit 1
}

Write-Host "Destination folder: $DestinationRoot" -ForegroundColor Cyan

# ----------------------------
# Process input lines
# ----------------------------
$Lines = Get-Content $InputFile | Where-Object { $_.Trim() -ne "" }

$Copied  = 0
$Deleted = 0
$Skipped = 0
$Missing = 0
$Failed  = 0

foreach ($Line in $Lines) {

    $Line = $Line.Trim()

    # Skip rows starting with 'duplicate' or 'not found'
    if ($Line -match '^(duplicate|not\s+found)') {
        $Skipped++
        continue
    }

    # Ensure file exists
    if (-not (Test-Path -LiteralPath $Line)) {
        Write-Warning "File not found on disk: $Line"
        $Missing++
        continue
    }

    # Build destination path preserving structure
    $FullSourcePath  = [System.IO.Path]::GetFullPath($Line)
    $RelativePath    = $FullSourcePath.Substring(
        [System.IO.Path]::GetPathRoot($FullSourcePath).Length
    )
    $DestinationPath = Join-Path $DestinationRoot $RelativePath

    # Ensure destination directory exists
    $DestinationDir = Split-Path $DestinationPath -Parent
    if (-not (Test-Path $DestinationDir)) {
        New-Item -Path $DestinationDir -ItemType Directory -Force | Out-Null
    }

    # Copy, then delete source if copy succeeds
    try {
        Copy-Item -LiteralPath $FullSourcePath -Destination $DestinationPath -Force -ErrorAction Stop
        Remove-Item -LiteralPath $FullSourcePath -Force -ErrorAction Stop

        Write-Host "Moved: $FullSourcePath" -ForegroundColor Green
        $Copied++
        $Deleted++
    }
    catch {
        Write-Error "FAILED to move $FullSourcePath : $($_.Exception.Message)"
        $Failed++
    }
}

# ----------------------------
# Summary
# ----------------------------
Write-Host ""
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "Copied   : $Copied"
Write-Host "Deleted  : $Deleted"
Write-Host "Skipped  : $Skipped"
Write-Host "Missing  : $Missing"
Write-Host "Failed   : $Failed"
Write-Host "Output   : $DestinationRoot"
