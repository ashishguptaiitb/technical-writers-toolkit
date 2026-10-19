<#
.SYNOPSIS
  Lists Markdown files recursively from the current folder.
  Displays file name, folder path, and an aggregated summary.

.DESCRIPTION
  For each Markdown file found in the current directory (recursively):
    - Shows file name
    - Shows the folder path the file resides in
  At the end, prints an aggregated summary:
    - Folder path
    - Total number of Markdown files (including subfolders)

.EXAMPLE
  Run directly in PowerShell:
    .\list-markdown-files.ps1

  To export CSVs:
    .\list-markdown-files.ps1 -OutputCsv ".\MarkdownReport.csv"
#>

param(
    [string]$OutputCsv = ""
)

# --- Use current working directory ---
$RootPath = (Get-Location).Path
Write-Host "Scanning current folder recursively: $RootPath"

# --- Get all Markdown files recursively ---
$mdFiles = Get-ChildItem -Path $RootPath -Recurse -File -Include *.md, *.markdown -ErrorAction SilentlyContinue

if (-not $mdFiles -or $mdFiles.Count -eq 0) {
    Write-Host "No Markdown files found in $RootPath" -ForegroundColor Yellow
    exit 0
}

# --- Identify folders containing Markdown files ---
$foldersWithMd = $mdFiles | Select-Object -ExpandProperty DirectoryName -Unique

# --- Compute Markdown file counts (including subfolders) per folder ---
$folderCounts = @{}
foreach ($folder in $foldersWithMd) {
    try {
        $count = (Get-ChildItem -Path $folder -Recurse -File -Include *.md, *.markdown -ErrorAction SilentlyContinue | Measure-Object).Count
    } catch {
        $count = 0
    }
    $folderCounts[$folder] = $count
}

# --- Build per-file results (only two columns now) ---
$results = @()
foreach ($f in $mdFiles) {
    $results += [PSCustomObject]@{
        FileName   = $f.Name
        FolderPath = $f.DirectoryName
    }
}

# --- Display per-file results ---
Write-Host "`nPer-file results:" -ForegroundColor Cyan
$results | Sort-Object FolderPath, FileName | Format-Table -AutoSize

# --- Build aggregated summary ---
$summary = $folderCounts.GetEnumerator() |
    ForEach-Object { [PSCustomObject]@{ FolderPath = $_.Key; TotalMarkdownFiles = $_.Value } } |
    Sort-Object FolderPath

Write-Host "`nAggregated summary (folder -> total markdown files including subfolders):" -ForegroundColor Cyan
$summary | Format-Table -AutoSize

# --- Export CSVs if requested ---
if ($OutputCsv) {
    # Resolve output path
    if ([System.IO.Path]::IsPathRooted($OutputCsv)) {
        $outPath = $OutputCsv
    } else {
        $outPath = Join-Path -Path (Get-Location).Path -ChildPath $OutputCsv
    }

    try {
        $results | Sort-Object FolderPath, FileName | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8 -Force
        Write-Host "`nPer-file CSV written to: $outPath" -ForegroundColor Green

        $summaryDir  = [System.IO.Path]::GetDirectoryName($outPath)
        if ([string]::IsNullOrEmpty($summaryDir)) { $summaryDir = (Get-Location).Path }
        $summaryBase = [System.IO.Path]::GetFileNameWithoutExtension($outPath)
        $summaryPath = Join-Path -Path $summaryDir -ChildPath ($summaryBase + "_summary.csv")

        $summary | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8 -Force
        Write-Host "Summary CSV written to: $summaryPath" -ForegroundColor Green
    } catch {
        Write-Host "Warning: failed to write CSV(s): $_" -ForegroundColor Yellow
    }
}

Write-Host "`nDone. Total Markdown files scanned: $($mdFiles.Count). Total folders with Markdown files: $($foldersWithMd.Count)." -ForegroundColor Green
