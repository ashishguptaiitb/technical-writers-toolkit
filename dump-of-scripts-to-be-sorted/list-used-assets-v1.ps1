<#
This script recursively scans all .mdx files in a folder path provided by me.
It finds referenced assets and creates a report of assets that we use in our docs.

Asset types scan and reporting is limited to these formats. To add more, add to the $Pattern list.
- .png
- .svg
- .jpg
- .jpeg
- .pdf
- .xlsx
- .gif
- .mp4

The report is a .csv file named 'list-of-used-assets.csv' in the user-provided root folder. It has 2 columns:
- MdxFile   : Root-relative path of the .mdx file itself.
- AssetPath : Root-relative paths of the assets referenced in each .mdx file.
#>

# Prompt for root folder
$RootFolder = Read-Host "Enter the root folder path"

# Remove surrounding double quotes if present
$RootFolder = $RootFolder.Trim('"')


if (-not (Test-Path $RootFolder)) {
    Write-Error "Folder does not exist."
    exit 1
}

$RootFolder = (Resolve-Path $RootFolder).Path


# Asset extensions to search for
$AssetExtensions = @(
    "png",
    "svg",
    "jpg",
    "jpeg",
    "pdf",
    "xlsx",
    "gif",
    "mp4"
)

# Regex to find asset references
$Pattern = '(?<path>[^"''()\s<>]+?\.(png|svg|jpg|jpeg|pdf|xlsx|gif|mp4))'

$Results = [System.Collections.Generic.List[Object]]::new()

# Find all MDX files
$MdxFiles = Get-ChildItem -Path $RootFolder -Recurse -File -Filter "*.mdx"

foreach ($File in $MdxFiles) {

    $RootFolder = (Resolve-Path $RootFolder).Path
}

foreach ($File in $MdxFiles) {

    $FullPath = (Resolve-Path $File.FullName).Path

    $RelativeMdxPath = $FullPath.Substring($RootFolder.Length).TrimStart('\','/')
    $RelativeMdxPath = $RelativeMdxPath -replace '\\', '/'

    $Content = Get-Content -LiteralPath $File.FullName -Raw

    $Matches = [regex]::Matches(
        $Content,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    foreach ($Match in $Matches) {

        $AssetPath = $Match.Groups["path"].Value

        $Results.Add([PSCustomObject]@{
            MdxFile   = $RelativeMdxPath
            AssetPath = $AssetPath
        })
    }
}

# Remove duplicates
$Results =
    $Results |
    Sort-Object MdxFile, AssetPath -Unique

# Output CSV
$CsvPath = Join-Path $RootFolder "list-of-used-assets.csv"

"MdxFile,AssetPath" | Set-Content -Path $CsvPath -Encoding UTF8

$Results |
    Sort-Object MdxFile, AssetPath |
    ForEach-Object {
        "$($_.MdxFile),$($_.AssetPath)"
    } |
    Add-Content -Path $CsvPath -Encoding UTF8

Write-Host ""
Write-Host "Report created:"
Write-Host $CsvPath
Write-Host ""
Write-Host "Total references found: $($Results.Count)"