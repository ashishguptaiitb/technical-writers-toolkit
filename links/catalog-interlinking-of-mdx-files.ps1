# =====================================================================
# Extract all root-relative MDX links from a documentation repository
# Compatible with Windows PowerShell 5.1
# =====================================================================

# Prompt for the repository root folder.
# Accepts the path with or without surrounding quotation marks.
$RepoRoot = Read-Host "Enter repository root folder"

# Remove leading/trailing whitespace and enclosing double quotes (if present)
$RepoRoot = $RepoRoot.Trim().Trim('"')

if (!(Test-Path -LiteralPath $RepoRoot))
{
    Write-Host "Folder not found."
    exit
}

$IgnoredFolders = @(
    "drafts",
    "assets",
    "custom-css",
    ".claude",
    ".vscode",
    ".git",
    ".github",
    "snippets"
)

$output = @()

$files = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.mdx -File |
Where-Object {

    $full = $_.FullName.ToLower()

    $ignore = $false

    foreach($folder in $IgnoredFolders)
    {
        if($full -match "\\$([regex]::Escape($folder.ToLower()))\\")
        {
            $ignore = $true
            break
        }
    }

    -not $ignore
}

foreach($file in $files)
{
    Write-Host "Scanning $($file.FullName)"

    $text = Get-Content -LiteralPath $file.FullName -Raw

    # Markdown links
    $matches = [regex]::Matches(
        $text,
        '\[[^\]]+\]\((/[^)\s#]+(?:/[^)\s#]*)*)(?:#([^)\s]+))?\)'
    )

    foreach($m in $matches)
    {
        $rootPath = $m.Groups[1].Value
        $anchor = $m.Groups[2].Value

        # Keep only links that point to MDX articles
        # Ignore image folders and files with extensions

        $leaf = Split-Path $rootPath -Leaf

        if ($leaf -match '\.')
        {
            continue
        }

        $relative = $file.FullName.Substring($RepoRoot.Length).TrimStart('\')

        $output += [PSCustomObject]@{
            SourceFile         = $file.Name
            SourceRelativePath = $relative
            LinkedRootPath     = $rootPath
            Anchor             = $anchor
        }
    }
}

$outFile = Join-Path -Path $RepoRoot -ChildPath "all-links-to-mdx-files.csv"

$output |
Sort-Object SourceRelativePath, LinkedRootPath |
Export-Csv $outFile -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Finished."
Write-Host "CSV written to:"
Write-Host $outFile
Write-Host ""
Write-Host "Total links found: $($output.Count)"