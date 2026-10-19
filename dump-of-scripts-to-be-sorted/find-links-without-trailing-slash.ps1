# Recursively scan Markdown files for hyperlinks without trailing slash
# Supports:
# - Markdown links: [text](url)
# - HTML links: <a href="url">
# Outputs CSV with RelativePath, LineNumber, URL

$RootPath  = (Get-Location).Path
$OutputCsv = "links-without-trailing-slash.csv"
$Results   = @()

# Regex patterns
$MarkdownLinkPattern = '\[[^\]]*\]\((https?://[^\s\)#]+)(?<!/)\)'
$HtmlLinkPattern     = '<a\s+[^>]*href=["''](https?://[^"''\s>]+)(?<!/)["'']'

Get-ChildItem -Path $RootPath -Recurse -File -Filter "*.md" | ForEach-Object {

    $FullPath     = $_.FullName
    $RelativePath = $FullPath.Substring($RootPath.Length).TrimStart('\','/')
    $Lines        = Get-Content -LiteralPath $FullPath

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $Line = $Lines[$i]

        # Markdown links
        foreach ($Match in [regex]::Matches($Line, $MarkdownLinkPattern, 'IgnoreCase')) {
            $Results += [PSCustomObject]@{
                FilePath   = $RelativePath
                LineNumber = $i + 1
                URL        = $Match.Groups[1].Value
            }
        }

        # HTML href links
        foreach ($Match in [regex]::Matches($Line, $HtmlLinkPattern, 'IgnoreCase')) {
            $Results += [PSCustomObject]@{
                FilePath   = $RelativePath
                LineNumber = $i + 1
                URL        = $Match.Groups[1].Value
            }
        }
    }
}

# Export results
if ($Results.Count -gt 0) {
    $Results |
        Sort-Object FilePath, LineNumber |
        Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

    Write-Host "Scan complete. Results written to $OutputCsv"
} else {
    Write-Host "Scan complete. No hyperlinks without trailing slash found."
}
