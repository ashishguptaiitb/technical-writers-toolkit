# Prereq script to bulk delete unused assets. From just the filenames, this script generates full local path. Another script will be fed a list of full paths for bulk deletion. See unused image script logic on why we have only filenames and not relative paths.
# Our flow: We start with a flat list of filenames with extension. It contains unique and duplicate names.
# Duplicate names handling: If 2 assets or screenshots are named the same in different folders, then we triage and delete it manually. This script doesn't search the folder structure for full path for assets that have duplicate names. Only the filename with extension of such assets is listed in the output as-is.
# For unique filenames, output .txt file contains full path if asset is found. Otherwise, filenames are reported as not found.
# Before bulk deletion we must clean up the output of this script to remove duplicate and not found filenames.
#
# Inputs required:
# 	-RootFolderPath is the docs repo path.
#	-FileListPath is the .txt flat list of just the filename.ext from unused asset script.
#

param(
    [Parameter(Mandatory = $true)]
    [string]$RootFolderPath,

    [Parameter(Mandatory = $true)]
    [string]$FileListPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "full-file-paths-of-unused-assets-with-duplicate-handling.txt"
)

# ----------------------------
# Validate inputs
# ----------------------------
if (-not (Test-Path $RootFolderPath)) {
    Write-Error "Root folder does not exist: $RootFolderPath"
    exit 1
}

if (-not (Test-Path $FileListPath)) {
    Write-Error "File list does not exist: $FileListPath"
    exit 1
}

# ----------------------------
# Read and normalize filenames
# ----------------------------
$FileNames = Get-Content $FileListPath |
             Where-Object { $_.Trim() -ne "" } |
             ForEach-Object { $_.Trim() }

if ($FileNames.Count -eq 0) {
    Write-Error "File list is empty."
    exit 1
}

# ----------------------------
# Identify duplicates
# ----------------------------
$NameCounts = $FileNames |
              Group-Object |
              ForEach-Object {
                  [PSCustomObject]@{
                      Name  = $_.Name
                      Count = $_.Count
                  }
              }

$DuplicateNames = $NameCounts |
                  Where-Object { $_.Count -gt 1 } |
                  Select-Object -ExpandProperty Name

Write-Host "Total filenames in list : $($FileNames.Count)"
Write-Host "Duplicate filenames     : $($DuplicateNames.Count)"
Write-Host "Unique filenames        : $($NameCounts.Count - $DuplicateNames.Count)"

# ----------------------------
# Process filenames
# ----------------------------
$Results = @()

foreach ($FileName in $NameCounts.Name) {

    # Case 1: duplicate filename in flat list
    if ($DuplicateNames -contains $FileName) {
        $Results += "DUPLICATE: $FileName"
        continue
    }

    # Case 2: unique filename — search filesystem
    Write-Host "Searching for: $FileName"

    $Matches = Get-ChildItem `
        -Path $RootFolderPath `
        -Recurse `
        -File `
        -Filter $FileName `
        -ErrorAction SilentlyContinue

    if ($Matches.Count -gt 0) {
        foreach ($Match in $Matches) {
            $Results += $Match.FullName
        }
    }
    else {
        $Results += "NOT FOUND: $FileName"
    }
}

# ----------------------------
# Write output
# ----------------------------
$Results | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host "Done. Results written to $OutputFile"
