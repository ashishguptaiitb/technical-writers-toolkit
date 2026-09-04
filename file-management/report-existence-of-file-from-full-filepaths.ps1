<#
This script reads a .txt file that contains one full file path per line and checks whether each file exists on the disk. The script reports only the files that exist.

This is useful to find redirect sources that do exist and hence shouldn't be redirected.

Run the script and enter the full path to the input .txt file when prompted.
#>

# Prompt for the input .txt file path
$inputFile = Read-Host "Enter the full path to the .txt file"

# Validate the input file exists
if (-not (Test-Path -Path $inputFile -PathType Leaf)) {
    Write-Host "Input file does not exist: $inputFile"
    exit 1
}

# Read all file paths from the text file
$filePaths = Get-Content -Path $inputFile

# Store existing files
$existingFiles = @()

# Check each file path
foreach ($filePath in $filePaths) {

    # Skip empty lines
    if ([string]::IsNullOrWhiteSpace($filePath)) {
        continue
    }

    # Validate file existence
    if (Test-Path -Path $filePath -PathType Leaf) {
        $existingFiles += $filePath
    }
}

# Report results
if ($existingFiles.Count -eq 0) {
    Write-Host "No files were found."
}
else {
    Write-Host "Files that exist:`n"

    $existingFiles | ForEach-Object {
        Write-Host $_
    }
}