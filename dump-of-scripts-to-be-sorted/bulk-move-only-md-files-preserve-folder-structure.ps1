# PowerShell script to move Markdown files while preserving folder structure from Source folder to Destination folder.
# Use command line to run this PS script and provide arguments as -SourcePath <folder path containing MD files> and -DestinationPath <folder path to copy the MD files to>.

param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationPath
)

# Validate source path exists
if (-not (Test-Path -Path $SourcePath)) {
    Write-Error "Source path does not exist: $SourcePath"
    exit 1
}

# Create destination path if it doesn't exist
if (-not (Test-Path -Path $DestinationPath)) {
    New-Item -ItemType Directory -Path $DestinationPath -Force
    Write-Host "Created destination directory: $DestinationPath" -ForegroundColor Green
}

# Get all Markdown files recursively
$markdownFiles = Get-ChildItem -Path $SourcePath -Filter "*.md" -Recurse -File

Write-Host "Found $($markdownFiles.Count) Markdown files to move" -ForegroundColor Cyan

foreach ($file in $markdownFiles) {
    # Calculate relative path from source
    $relativePath = $file.DirectoryName.Substring($SourcePath.Length)
    
    # Remove leading backslash if present
    if ($relativePath.StartsWith('\') -or $relativePath.StartsWith('/')) {
        $relativePath = $relativePath.Substring(1)
    }
    
    # Create destination directory path
    $destinationDir = if ([string]::IsNullOrEmpty($relativePath)) {
        $DestinationPath
    } else {
        Join-Path -Path $DestinationPath -ChildPath $relativePath
    }
    
    # Create destination directory if it doesn't exist
    if (-not (Test-Path -Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        Write-Host "Created directory: $destinationDir" -ForegroundColor Yellow
    }
    
    # Move the file
    $destinationFile = Join-Path -Path $destinationDir -ChildPath $file.Name
    
    try {
        Move-Item -Path $file.FullName -Destination $destinationFile -Force
        Write-Host "Moved: $($file.FullName) -> $destinationFile" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to move $($file.FullName): $($_.Exception.Message)"
    }
}

Write-Host "`nOperation completed. Moved $($markdownFiles.Count) Markdown files." -ForegroundColor Cyan