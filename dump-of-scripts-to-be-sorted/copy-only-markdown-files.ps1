# Define your paths here
$sourceDir = "C:\Users\Ashish.Gupta\Documents\GitHub\v2docs\ai-for-process"
$destDir   = "C:\Users\Ashish.Gupta\Documents\GitHub\_ai4p-mds"

# Create the destination directory if it doesn't exist
if (!(Test-Path -Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir | Out-Null
}

# Find all .md files in the source and its subfolders
$mdFiles = Get-ChildItem -Path $sourceDir -Filter *.md -Recurse

foreach ($file in $mdFiles) {
    # Calculate the relative path to maintain hierarchy
    $relativePath = $file.FullName.Replace($sourceDir, "")
    $destinationPath = Join-Path -Path $destDir -ChildPath $relativePath
    
    # Get the directory name for the destination file
    $targetFolder = Split-Path -Path $destinationPath
    
    # Create the folder structure in the destination if missing
    if (!(Test-Path -Path $targetFolder)) {
        New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    }

    # Copy the file
    Write-Host "Copying: $($file.Name) to $targetFolder" -ForegroundColor Gray
    Copy-Item -Path $file.FullName -Destination $destinationPath -Force
}

Write-Host "`nAll Markdown files migrated successfully!" -ForegroundColor Green