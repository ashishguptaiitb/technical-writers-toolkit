<#
This script recursively scans the current folder for all .md files and calculates word count of each help article.

It generates a .csv output file that contains the relative path of .md files and their word counts.
#>

param (
    [string]$RootPath = (Get-Location).Path,
    [string]$OutputCsv = "md-word-count.csv"
)

$results = Get-ChildItem -Path $RootPath -Recurse -Filter *.md -File | ForEach-Object {

    $relativePath = $_.FullName.Substring($RootPath.Length).TrimStart('\','/')

    $content = Get-Content $_.FullName -Raw

    # Split on whitespace to count words
    $wordCount = ($content -split '\s+' | Where-Object { $_ -ne '' }).Count

    [PSCustomObject]@{
        RelativePath = $relativePath
        WordCount   = $wordCount
    }
}

$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
