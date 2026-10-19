<#
  This script recursively scans MD files for regex-based matches and generates a CSV output.

  - Reads regex patterns from a text file (one regex per line).
  - Ignores blank lines and lines starting with '#'.
  - Matches every line in every MD file.
  - Outputs CSV with FilePath, LineNumber, Match.

  Use AllFiles parameter to scan all files or else the default scan is of .md files.

  - regex-library-to-scan-markdown-files-for-potential-secrets.txt in the same folder (or provide its path)
  
  Specify value of ModifiedWithinDays to limit the scan to recently updated files. For example, use it to scan only release-specific updates.

#>

param(
    [switch]$AllFiles,
    [int]$ModifiedWithinDays
)


# ---- Configuration ----
$RegexFile     = "regex-library-to-scan-markdown-files-for-potential-secrets.txt"
$DateStamp 	   = Get-Date -Format "MMddyyyy-HHmmss"
$OutputCsv     = "audit-report-for-potential-secrets-$DateStamp.csv"
$RootPath      = (Get-Location).Path
$ProgressEvery = 50


# ---- Validate regex file ----
if (-not (Test-Path $RegexFile)) {
    Write-Error "Regex library file not found: $RegexFile"
    exit 1
}

# ---- Load regex patterns ----
$Patterns = Get-Content $RegexFile |
    Where-Object {
        $_.Trim() -ne "" -and
        -not $_.Trim().StartsWith("#")
    }

if ($Patterns.Count -eq 0) {
    Write-Error "No usable regex patterns found in $RegexFile"
    exit 1
}

function Write-ScanProgressBar {
    param (
        [int]$Processed,
        [int]$Total
    )

    $BarWidth = 30
    $Percent  = [math]::Floor(($Processed / $Total) * 100)
    $Filled   = [math]::Floor(($Processed / $Total) * $BarWidth)
    $Empty    = $BarWidth - $Filled

    $Bar = (">" * $Filled) + ("-" * $Empty)

    # Choose color based on completion percentage
    if ($Percent -ge 80) {
        $Color = 'Green'
    }
    elseif ($Percent -ge 60) {
        $Color = 'Yellow'
    }
    else {
        $Color = 'Cyan'
    }

    $Message = "[SCAN] [$Bar] {0,4} / {1} files ({2}%)" -f $Processed, $Total, $Percent

    Write-Host "`r$Message" -NoNewline -ForegroundColor $Color
}


# ---- Select files to scan ----
if ($AllFiles) {
    Write-Host "Scanning ALL files recursively..."
    $Files = Get-ChildItem -Path $RootPath -Recurse -File
}
else {
    Write-Host "Scanning Markdown (.md) files recursively..."
    $Files = Get-ChildItem -Path $RootPath -Recurse -File -Filter "*.md"
}

# ---- Apply timestamp filter if requested ----
if ($PSBoundParameters.ContainsKey('ModifiedWithinDays')) {
    $CutoffDate = (Get-Date).AddDays(-$ModifiedWithinDays)

    Write-Host "Limiting scan to files modified in the last $ModifiedWithinDays days..."
    Write-Host "Cutoff timestamp: $CutoffDate"

    # MATERIALIZE the collection (this is the fix)
    $Files = @(
        $Files | Where-Object {
            $_.LastWriteTime -ge $CutoffDate
        }
    )
}

$TotalFiles = $Files.Count


# ---- Prepare results ----
$Results = @()
$Processed = 0

# ---- Scan files ----
foreach ($File in $Files) {

    $Processed++

    # Progress indicator
    if ($Processed % $ProgressEvery -eq 0 -or $Processed -eq $TotalFiles) {
        Write-ScanProgressBar -Processed $Processed -Total $TotalFiles
    }

    try {
        $Lines = Get-Content $File.FullName -ErrorAction Stop
    } catch {
        Write-Warning "Failed to read file: $($File.FullName)"
        continue
    }

    # Compute relative path
    $RelativePath = $File.FullName.Substring($RootPath.Length).TrimStart('\','/')

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $LineText = $Lines[$i]

        foreach ($Pattern in $Patterns) {
            try {
                $Matches = [regex]::Matches($LineText, $Pattern)
            } catch {
                Write-Warning "Invalid regex skipped: $Pattern"
                continue
            }

            foreach ($Match in $Matches) {
                $Results += [PSCustomObject]@{
                    FilePath   = $RelativePath
                    LineNumber = $i + 1
                    Match      = $Match.Value
                }
            }
        }
    }
}

# ---- Export CSV ----
if ($Results.Count -gt 0) {
    $Results |
        Sort-Object FilePath, LineNumber |
        Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

    Write-Host "Scan complete."
    Write-Host "Matches found: $($Results.Count)"
    Write-Host "Report written to: $OutputCsv"
} else {
    Write-Host "Scan complete. No matches found."
}
