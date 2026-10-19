# Provide a list of files in a .txt file. It must contain full file path, file name, and its extension. Only 1 entry per row. This script will delete all the files listed in the input .txt file.


param(
    [Parameter(Mandatory = $true)]
    [string]$FileListPath,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIfOnly
)

# Validate input
if (-not (Test-Path $FileListPath)) {
    Write-Error "Input file does not exist: $FileListPath"
    exit 1
}

# Read file paths (ignore empty lines)
$FilePaths = Get-Content $FileListPath |
             Where-Object { $_.Trim() -ne "" }

Write-Host "Files listed for deletion: $($FilePaths.Count)" -ForegroundColor Cyan

$Deleted = 0
$Missing = 0
$Failed  = 0

foreach ($Path in $FilePaths) {

    $Path = $Path.Trim()

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "NOT FOUND: $Path"
        $Missing++
        continue
    }

    try {
        if ($WhatIfOnly) {
            Write-Host "[WHATIF] Would delete: $Path" -ForegroundColor Yellow
        }
        else {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            Write-Host "DELETED: $Path" -ForegroundColor Green
            $Deleted++
        }
    }
    catch {
        Write-Error "FAILED to delete $Path : $($_.Exception.Message)"
        $Failed++
    }
}

Write-Host ""
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "Deleted : $Deleted"
Write-Host "Missing : $Missing"
Write-Host "Failed  : $Failed"
