# Relative links in HTML syntax, without a trailing slash, get inserted as it is in the published docs. Without a trailing slash, it redirects to github.io. The script looks for:
# Relative href links without trailing slash.
# Links with anchor that is, without hash (#) symbol.
# It excludes absolute links. There's another script to check for absolute links without trailing slashes.
# Parses only inside Markdown (.md) files.

param (
    [string]$RootPath = (Get-Location).Path,
    [string]$OutputCsv = "relative-links-without-trailing-slash.csv"
)

# Regex:
# - Matches <a href="...">
# - Excludes absolute URLs, protocol-relative URLs, and anchors
# - Captures only the href value
# - Ensures no trailing slash before optional quote/fragment
$pattern = '<a\s+href="(?<link>(?!https?:\/\/)(?!\/\/)(?!#)[^"#]*[^/"#])"'

$results = Get-ChildItem -Path $RootPath -Recurse -Filter *.md | ForEach-Object {
    $fullPath = $_.FullName
    $relativePath = $fullPath.Substring($RootPath.Length).TrimStart('\','/')

    Select-String -Path $fullPath -Pattern $pattern | ForEach-Object {
        foreach ($match in $_.Matches) {
            [PSCustomObject]@{
                RelativePath = $relativePath
                LineNumber   = $_.LineNumber
                Link         = $match.Groups['link'].Value
            }
        }
    }
}

$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

