# Define your paths here
$SearchKeyword = "!!!"
$DestinationFolder = "C:\Users\Ashish.Gupta\Documents\GitHub\_ai4w-mds"
$SourceFolder = "C:\Users\Ashish.Gupta\Documents\GitHub\v2docs\ai-for-work"

Get-ChildItem -Path $SourceFolder -Recurse -Filter *.md -File | ForEach-Object {

    $filePath = $_.FullName

    # Read file content
    $content = Get-Content $filePath -Raw

    # Copy only if keyword is found (case-insensitive)
    if ($content -match [regex]::Escape($SearchKeyword)) {

        $relativePath = $filePath.Substring($SourceFolder.Length).TrimStart('\','/')
        $targetPath = Join-Path $DestinationFolder $relativePath
        $targetDir  = Split-Path $targetPath -Parent

        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Copy-Item -Path $filePath -Destination $targetPath -Force
    }
}