# Provide full path of many files inside an input .txt file; add 1 path per row.
# This script copies all these files in a destination folder (provides its path as well).
# It preserves the folder hierarchy. It works for all file types.


$txtFilePath = Read-Host "Enter the path to your .txt file"
$destFolderPath = Read-Host "Enter the destination folder path"

$txtFilePath = $txtFilePath.Trim('"')
$destFolderPath = $destFolderPath.Trim('"')

if (-not (Test-Path -Path $txtFilePath)) {
    Write-Error "The input .txt file was not found."
    exit
}

# Ensure destination is an absolute path to avoid logic errors
$destFolderPath = (Resolve-Path $destFolderPath).Path

$fileList = Get-Content -Path $txtFilePath | Where-Object { $_.Trim() -ne "" }

foreach ($line in $fileList) {
    $sourcePath = $line.Trim().Trim('"')
    
    if (Test-Path -Path $sourcePath -PathType Leaf) {
        $fileItem = Get-Item -Path $sourcePath
        
        # FIX: Get the path WITHOUT the drive letter and colon
        # This turns "C:/Users/Files/abc.txt" into "Users/Files/abc.txt"
        $relativePath = $sourcePath -replace '^[a-zA-Z]:', ''
        $relativePath = $relativePath.TrimStart('\').TrimStart('/')

        # Combine safely
        $finalDestPath = Join-Path -Path $destFolderPath -ChildPath $relativePath
        $parentFolder = Split-Path -Path $finalDestPath -Parent

        # Create subfolders if needed
        if (-not (Test-Path -Path $parentFolder)) {
            # -Force handles nested creation (mkdir -p style)
            New-Item -ItemType Directory -Path $parentFolder -Force | Out-Null
        }

        Copy-Item -Path $sourcePath -Destination $finalDestPath -Force
        Write-Host "✅ Copied: $($fileItem.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "❌ FAILED: Check path -> $sourcePath" -ForegroundColor Red
    }
}