# PowerShell script to create a flat list of digital assets available in a folder and all its subdirectories.
# Create list of digital assets available in the repo. Check for specific file formats only. Listed under $fileExtensions.
# Output of this script is fed into another script to check for unused assets.
#
# Only file names are listed and not the folder path. Since assets used in MD files have relative links and do not include folder path. When finding unused assets, we only look for file names used in the MD files.
#
# Sample run: .\list_repo_assets_filenames.ps1 -FolderPath "folder" -OutputFile assets-listing.txt
# Sample run: .\list_repo_assets_filenames.ps1 -FolderPath "C:\Users\Ashish.Gupta\Documents\GitHub\xo-docsinternal-fork\docs\xo" -OutputFile xo-total-assests.txt

param(
    [Parameter(Mandatory=$true)]
    [string]$FolderPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Sort = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$RemoveDuplicates = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$GroupByExtension = $false
)

# Define file extensions to search for
$fileExtensions = @("*.png", "*.svg", "*.jpg", "*.jpeg", "*.pdf", "*.xlsx", "*.gif", "*.mp4")

# Validate folder path exists
if (-not (Test-Path -Path $FolderPath)) {
    Write-Error "Folder path does not exist: $FolderPath"
    exit 1
}

Write-Host "Scanning for files with extensions: $($fileExtensions -join ', ')" -ForegroundColor Cyan
Write-Host "Folder: $FolderPath" -ForegroundColor White

# Get all files matching the specified extensions recursively
$allFiles = @()
foreach ($extension in $fileExtensions) {
    $files = Get-ChildItem -Path $FolderPath -Filter $extension -Recurse -File
    $allFiles += $files
}

if ($allFiles.Count -eq 0) {
    Write-Host "No files found matching the specified extensions." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($allFiles.Count) files total" -ForegroundColor Green

# Group files by extension for summary
$fileGroups = $allFiles | Group-Object Extension | Sort-Object Name
Write-Host "`nFile breakdown by extension:" -ForegroundColor Yellow
foreach ($group in $fileGroups) {
    Write-Host "  $($group.Name.ToUpper()): $($group.Count) files" -ForegroundColor White
}

# Extract just the filenames (without paths)
$filenames = $allFiles | ForEach-Object { $_.Name }

# Remove duplicates if requested
if ($RemoveDuplicates) {
    $originalCount = $filenames.Count
    $filenames = $filenames | Sort-Object -Unique
    $duplicatesRemoved = $originalCount - $filenames.Count
    if ($duplicatesRemoved -gt 0) {
        Write-Host "Removed $duplicatesRemoved duplicate filename(s)" -ForegroundColor Yellow
    }
}

# Sort filenames if requested
if ($Sort) {
    $filenames = $filenames | Sort-Object
}

# Output to console
if ($GroupByExtension) {
    Write-Host "`nFilenames grouped by extension:" -ForegroundColor Cyan
    $groupedFiles = $allFiles | Group-Object Extension | Sort-Object Name
    foreach ($group in $groupedFiles) {
        Write-Host "`n$($group.Name.ToUpper()) Files:" -ForegroundColor Yellow
        $groupFilenames = $group.Group | ForEach-Object { $_.Name }
        if ($Sort) {
            $groupFilenames = $groupFilenames | Sort-Object
        }
        $groupFilenames | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    }
} else {
    Write-Host "`nAll Filenames:" -ForegroundColor Cyan
    $filenames | ForEach-Object { Write-Host $_ -ForegroundColor White }
}

# Output to file if specified
if (-not [string]::IsNullOrEmpty($OutputFile)) {
    try {
        # Create header for the output file
        $header = @(
            "# Multiple File Types List",
            "# Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "# Source folder: $FolderPath",
            "# Extensions searched: $($fileExtensions -join ', ')",
            "# Total files: $($filenames.Count)",
            "#",
            ""
        )
        
        if ($GroupByExtension) {
            # Group files by extension in output
            $output = $header
            $groupedFiles = $allFiles | Group-Object Extension | Sort-Object Name
            foreach ($group in $groupedFiles) {
                $output += "`n# $($group.Name.ToUpper()) Files ($($group.Count)):"
                $groupFilenames = $group.Group | ForEach-Object { $_.Name }
                if ($Sort) {
                    $groupFilenames = $groupFilenames | Sort-Object
                }
                $output += $groupFilenames
                $output += ""
            }
        } else {
            $output = $header + $filenames
        }
        
        $output | Out-File -FilePath $OutputFile -Encoding UTF8
        
        Write-Host "`nFilenames saved to: $OutputFile" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to write output file: $($_.Exception.Message)"
    }
}

Write-Host "`nTotal filenames listed: $($filenames.Count)" -ForegroundColor Cyan