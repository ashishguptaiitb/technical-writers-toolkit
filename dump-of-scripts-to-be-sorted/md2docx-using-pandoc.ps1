# Combines all Markdown .md files in a folder into one single .docx
# Uses pandoc which must be installed and added to the env path.
# For titles, it picks only from the YAML style front-matter, appearing after the word 'title: '. These titles are converted to H1 headings in .docx.

$outputName = "MasterDocument.docx"
$tempDir = Join-Path $env:TEMP "md-pandoc-with-titles"

New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$mdFiles = Get-ChildItem -Filter *.md | Sort-Object Name

if ($mdFiles.Count -eq 0) {
    Write-Host "No .md files found to combine." -ForegroundColor Yellow
    return
}

Write-Host "Processing $($mdFiles.Count) Markdown files..." -ForegroundColor Cyan

$tempFiles = foreach ($file in $mdFiles) {

    $content = Get-Content $file.FullName -Raw

	# Extract title from YAML front matter (multiline-safe)
	if ($content -match '(?ms)^---\s*\n.*?^title:\s*"?(.+?)"?\s*$.*?^---\s*\n') {
		$title = $matches[1].Trim()
		$content = $content -replace '(?ms)^---\s*\n.*?^---\s*\n', ''
	}


    $tempFile = Join-Path $tempDir $file.Name

    if ($title) {
        "# $title`r`n`r`n$content" | Set-Content -Encoding UTF8 $tempFile
    } else {
        $content | Set-Content -Encoding UTF8 $tempFile
    }

    $tempFile
}

Write-Host "Generating $outputName..." -ForegroundColor Cyan

pandoc $tempFiles -o $outputName

Write-Host "Success! Titles from front matter are included." -ForegroundColor Green
