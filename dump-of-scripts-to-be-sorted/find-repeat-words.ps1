# Script: Find repeated words in Markdown files
# Recursively scans from current folder
# Reports file, line number, and the repeated word(s)

$pattern = '\b(\w+)\s+\1\b'   # regex for repeated words (case-insensitive)

Get-ChildItem -Path . -Recurse -Filter *.md -File | ForEach-Object {
    $file = $_.FullName
    $lineNum = 0
    Get-Content -LiteralPath $file | ForEach-Object {
        $lineNum++
        if ($_ -match $pattern) {
            [PSCustomObject]@{
                File   = $file
                Line   = $lineNum
                Text   = $_.Trim()
                Repeat = $matches[0]
            }
        }
    }
} | Export-Csv -Path "RepeatedWords.csv" -NoTypeInformation -Encoding UTF8 -Force

Write-Host "✅ Done. Results saved to RepeatedWords.csv"
