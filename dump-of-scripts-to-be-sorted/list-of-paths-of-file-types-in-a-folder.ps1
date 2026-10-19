# ============================================================
# Windows PowerShell 5.x script. Recursively list root-relative path of files with the extn. listed below. Output txt has 1 path per row using using forward slashes.
# ============================================================
# Customize the file extensions to include.
# Include the leading dot.

$FileExtensions = @(
    ".png",
    ".pdf",
    ".jpg",
    ".svg",
    ".gif"
)

# Ask for the folder to scan.
$RootPath = Read-Host "Enter the folder path"

# Remove surrounding double quotes, if the user entered them.
$RootPath = $RootPath.Trim().Trim('"')

# Convert to an absolute, normalized path.
try {
    $RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
}
catch {
    Write-Error "The specified folder does not exist: $RootPath"
    exit 1
}

# Define the output file.
$OutputFile = Join-Path $RootPath "list-of-relative-paths-of-file-types.txt"

Write-Progress -Activity "Scanning files" -Status "Searching for matching files..." -PercentComplete 0

# Recursively find files and filter by extension.
$Files = Get-ChildItem -LiteralPath $RootPath -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        $FileExtensions -contains $_.Extension.ToLowerInvariant()
    }

Write-Progress -Activity "Scanning files" -Status "Creating relative paths..." -PercentComplete 75

# Convert each file path to a root-relative path and use forward slashes.
$RelativePaths = foreach ($File in $Files) {
    $RelativePath = $File.FullName.Substring($RootPath.Length).TrimStart('\')
    $RelativePath.Replace('\', '/')
}

# Sort the output for easier reading.
$RelativePaths = $RelativePaths | Sort-Object

Write-Progress -Activity "Scanning files" -Status "Writing output..." -PercentComplete 90

# Write the paths to the output text file.
$RelativePaths | Set-Content -LiteralPath $OutputFile -Encoding UTF8

Write-Progress -Activity "Scanning files" -Completed

Write-Host ""
Write-Host "Scan complete."
Write-Host "Files found: $($RelativePaths.Count)"
Write-Host "Output: $OutputFile"