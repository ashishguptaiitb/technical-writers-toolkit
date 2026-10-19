# Script: Extract all Markdown headings (H1–H6) from files
# Recursively scans from current folder
# Outputs:
#   1. CSV file (for analysis)
#   2. Markdown TOC file with clickable links (for structural review)

$outputCsv = "Markdown_All_Headings.csv"
$outputToc = "Markdown_TOC.md"
$results = @()
$tocLines = @()

# Regex: match lines starting with 1–6 hash marks followed by a space and text
$pattern = '^(#{1,6})\s+(.*)'

function Get-MarkdownAnchor {
    param([string]$heading)

    # GitHub-style slug:
    # - lowercase
    # - remove anything not alphanumeric, space, or hyphen
    # - spaces -> hyphens
    $anchor = $heading.ToLower()
    $anchor = $anchor -replace '[^\w\s-]', ''
    $anchor = $anchor -replace '\s+', '-'
    return $anchor
}

Get-ChildItem -Path . -Recurse -Filter *.md -File | ForEach-Object {
    $file = $_.FullName
    $relativePath = Resolve-Path -Relative $file

    # Add file path as a top-level entry in the TOC
    $tocLines += "# File: $relativePath"
    $tocLines += ""

    $lineNum = 0
    Get-Content -LiteralPath $file | ForEach-Object {
        $lineNum++
        if ($_ -match $pattern) {
            $hashes  = $matches[1]
            $heading = $matches[2].Trim()
            $level   = $hashes.Length  # number of # = heading level (1–6)

            # Markdown-style outline string
            $outline = ('#' * $level) + ' ' + $heading

            # Anchor for clickable link
            $anchor = Get-MarkdownAnchor $heading
            $link   = "$relativePath#$anchor"

            # TOC entry as clickable link
            $tocEntry = ('#' * $level) + " [$heading]($link)"

            # Store result for CSV
            $results += [PSCustomObject]@{
                FilePath = $file
                Level    = $level
                Line     = $lineNum
                Heading  = $heading
                Outline  = $outline
            }

            # Add to Markdown TOC
            $tocLines += $tocEntry
        }
    }

    $tocLines += "" # blank line after each file
}

# Sort results by file path then line number
$results |
    Sort-Object FilePath, Line |
    Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8 -Force

# Write TOC markdown file
$tocLines | Set-Content -Path $outputToc -Encoding UTF8

Write-Host "✅ Done."
Write-Host "CSV saved to: $outputCsv"
Write-Host "Markdown TOC saved to: $outputToc (with clickable links)"
