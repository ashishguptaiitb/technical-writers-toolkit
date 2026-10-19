# ============================================================
# Copy files based on source and destination paths in a CSV
#
# CSV:
#   Column 1 = Source file path
#   Column 2 = Destination folder path
#
# Example:
#   C:\Source\file1.pdf,C:\Destination\Folder1
#   C:\Source\file2.png,C:\Destination\Folder2
# ============================================================

# Ask the user for the CSV file path
$CsvPath = Read-Host "Enter the path of the CSV file"

# Normalize quotation marks and slashes in the CSV path
$CsvPath = $CsvPath.Trim().Trim('"').Replace('/', '\')

# Validate the CSV path
if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
    Write-Host "CSV file not found: $CsvPath" -ForegroundColor Red
    exit
}

# Import the CSV
try {
    $Rows = Import-Csv -LiteralPath $CsvPath -ErrorAction Stop
}
catch {
    Write-Host "Unable to read the CSV file." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit
}

# Make sure the CSV contains at least two columns
if ($Rows.Count -eq 0) {
    Write-Host "The CSV file contains no data rows." -ForegroundColor Red
    exit
}

$ColumnNames = @($Rows[0].PSObject.Properties.Name)

if ($ColumnNames.Count -lt 2) {
    Write-Host "The CSV must contain at least two columns." -ForegroundColor Red
    exit
}

$SourceColumn = $ColumnNames[0]
$DestinationColumn = $ColumnNames[1]

# Ask whether existing files should be overwritten
$Overwrite = Read-Host "Overwrite existing files? (Y/N)"

$OverwriteExisting = $Overwrite -match '^(Y|y)$'

# Counters
$Total = $Rows.Count
$Current = 0
$Copied = 0
$Skipped = 0
$Failed = 0

Write-Host ""
Write-Host "Starting file copy..." -ForegroundColor Cyan
Write-Host "Total rows: $Total"
Write-Host ""

foreach ($Row in $Rows) {

    $Current++

    # Show progress
    $PercentComplete = [math]::Round(($Current / $Total) * 100, 0)

    Write-Progress `
        -Activity "Copying files" `
        -Status "Processing $Current of $Total" `
        -PercentComplete $PercentComplete

    # Read source and destination paths
    $SourcePath = [string]$Row.$SourceColumn
    $DestinationFolder = [string]$Row.$DestinationColumn

    # Normalize quotation marks and slashes
    $SourcePath = $SourcePath.Trim().Trim('"').Replace('/', '\')
    $DestinationFolder = $DestinationFolder.Trim().Trim('"').Replace('/', '\')

    # Skip rows with missing paths
    if ([string]::IsNullOrWhiteSpace($SourcePath) -or
        [string]::IsNullOrWhiteSpace($DestinationFolder)) {

        Write-Host "Skipped row $Current - source or destination path is empty." `
            -ForegroundColor Yellow

        $Skipped++
        continue
    }

    # Check whether the source file exists
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {

        Write-Host "Source file not found: $SourcePath" `
            -ForegroundColor Red

        $Failed++
        continue
    }

    try {
        # Create the destination folder if it does not exist
        if (-not (Test-Path -LiteralPath $DestinationFolder -PathType Container)) {
            New-Item -ItemType Directory `
                -Path $DestinationFolder `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        # Get the original filename
        $FileName = Split-Path -Path $SourcePath -Leaf

        # Build the complete destination path
        $DestinationPath = Join-Path -Path $DestinationFolder -ChildPath $FileName

        # Skip existing files unless overwrite is enabled
        if ((Test-Path -LiteralPath $DestinationPath -PathType Leaf) -and
            (-not $OverwriteExisting)) {

            Write-Host "Skipped - destination file already exists: $DestinationPath" `
                -ForegroundColor Yellow

            $Skipped++
            continue
        }

        # Copy the file
        Copy-Item `
            -LiteralPath $SourcePath `
            -Destination $DestinationPath `
            -Force:$OverwriteExisting `
            -ErrorAction Stop

        Write-Host "Copied: $SourcePath -> $DestinationPath" `
            -ForegroundColor Green

        $Copied++
    }
    catch {

        Write-Host "Failed to copy: $SourcePath" `
            -ForegroundColor Red

        Write-Host "Reason: $($_.Exception.Message)" `
            -ForegroundColor Red

        $Failed++
    }
}

# Complete the progress bar
Write-Progress `
    -Activity "Copying files" `
    -Status "Completed" `
    -PercentComplete 100 `
    -Completed

# Display summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Copy operation completed." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total rows : $Total"
Write-Host "Copied     : $Copied" -ForegroundColor Green
Write-Host "Skipped    : $Skipped" -ForegroundColor Yellow
Write-Host "Failed     : $Failed" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan