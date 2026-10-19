# ============================================================
# MDX Used Assets Scanner
# PowerShell 5 compatible
# ============================================================

# Ask for the root folder containing the MDX files.
$RootPath = Read-Host "Enter the root folder path"

# ------------------------------------------------------------
# Normalize the input folder path:
# - Remove surrounding double quotes if supplied.
# - Resolve the path to its full filesystem path.
# The filesystem path itself remains Windows-native because
# PowerShell uses it to access files.
# ------------------------------------------------------------
$RootPath = $RootPath.Trim()
$RootPath = $RootPath.Trim('"')

try {
    $RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
}
catch {
    Write-Error "The specified folder path does not exist or cannot be accessed."
    exit 1
}

# ------------------------------------------------------------
# Folders to skip while recursively scanning.
# Folder-name matching is case-insensitive.
# ------------------------------------------------------------
$IgnoreFolders = @(
    'drafts'
    'assets'
    'custom-css'
    '.claude'
    '.vscode'
    '.git'
    '.github'
)

# ------------------------------------------------------------
# Asset file extensions to extract from Markdown references.
# Add or remove extensions here as required.
# ------------------------------------------------------------
$AssetExtensions = @(
    'jpg'
    'pdf'
    'gif'
    'png'
    'svg'
)

# Create a case-insensitive lookup pattern for the extensions.
$ExtensionPattern = ($AssetExtensions -join '|')

# ------------------------------------------------------------
# Find all MDX files while excluding files located under
# any of the configured ignored folder names.
# ------------------------------------------------------------
Write-Host "`nScanning MDX files..." -ForegroundColor Cyan

$MdxFiles = Get-ChildItem `
    -LiteralPath $RootPath `
    -Filter '*.mdx' `
    -File `
    -Recurse `
    -ErrorAction SilentlyContinue |
    Where-Object {

        # Convert the filesystem path to forward slashes
        # for path processing within the script.
        $RelativePath = $_.FullName.Substring($RootPath.Length)
        $RelativePath = $RelativePath -replace '\\', '/'
        $RelativePath = $RelativePath.TrimStart('/')

        $PathParts = $RelativePath -split '/'

        $ShouldIgnore = $false

        foreach ($Folder in $IgnoreFolders) {
            if ($PathParts -contains $Folder) {
                $ShouldIgnore = $true
                break
            }
        }

        -not $ShouldIgnore
    }

Write-Host "Found $($MdxFiles.Count) MDX files.`n"

# ------------------------------------------------------------
# Store extracted results here.
# Each row contains:
#   MDX filename
#   Asset path
# ------------------------------------------------------------
$Results = New-Object System.Collections.Generic.List[Object]

$TotalFiles = $MdxFiles.Count
$CurrentFile = 0

foreach ($MdxFile in $MdxFiles) {

    $CurrentFile++

    # Display scan progress.
    $PercentComplete = if ($TotalFiles -gt 0) {
        [int](($CurrentFile / $TotalFiles) * 100)
    }
    else {
        100
    }

    Write-Progress `
        -Activity "Scanning MDX files" `
        -Status "$CurrentFile of $TotalFiles - $($MdxFile.Name)" `
        -PercentComplete $PercentComplete

    try {
        $Content = Get-Content `
            -LiteralPath $MdxFile.FullName `
            -Raw `
            -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not read: $($MdxFile.FullName)"
        continue
    }

    # --------------------------------------------------------
    # Extract Markdown image/link references only.
    #
    # Supported examples:
    #   ![Alt text](/images/example.png)
    #   [Download PDF](/docs/example.pdf)
    #
    # Asset paths must begin with "/".
    # --------------------------------------------------------
    $MarkdownPattern = "(?:!\[[^\]]*\]|\[[^\]]*\])\(\s*[<]?(/[^\)\s>]+)[>]?\s*\)"

    $Matches = [regex]::Matches(
        $Content,
        $MarkdownPattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    foreach ($Match in $Matches) {

        # Keep the extracted asset path in forward-slash format.
        $AssetPath = $Match.Groups[1].Value

        # Remove query strings and URL fragments.
        $AssetPath = $AssetPath -replace '[?#].*$', ''

        # Ensure forward slashes are used throughout.
        $AssetPath = $AssetPath -replace '\\', '/'

        # ----------------------------------------------------
        # Check whether the referenced path ends with one of
        # the configured asset extensions.
        # ----------------------------------------------------
        if ($AssetPath -match "\.($ExtensionPattern)$") {

            # Get the MDX file's root-relative path.
            $MdxRelativePath = $MdxFile.FullName.Substring($RootPath.Length)

            # Use forward slashes in the CSV.
            $MdxRelativePath = $MdxRelativePath -replace '\\', '/'
            $MdxRelativePath = $MdxRelativePath.TrimStart('/')

            $Results.Add(
                [PSCustomObject]@{
                    'MDX Filename' = $MdxRelativePath
                    'Asset Path'   = $AssetPath
                }
            )
        }
    }
}

Write-Progress -Activity "Scanning MDX files" -Completed

# ------------------------------------------------------------
# Remove duplicate MDX/asset combinations.
# ------------------------------------------------------------
$Results = $Results |
    Sort-Object 'MDX Filename', 'Asset Path' -Unique

# ------------------------------------------------------------
# Generate the timestamped CSV filename.
# ------------------------------------------------------------
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$OutputPath = Join-Path `
    -Path $RootPath `
    -ChildPath "used-assets_$Timestamp.csv"

# ------------------------------------------------------------
# Write the CSV report.
# ------------------------------------------------------------
$Results |
    Export-Csv `
        -LiteralPath $OutputPath `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host "`nScan complete." -ForegroundColor Green
Write-Host "MDX files scanned : $($MdxFiles.Count)"
Write-Host "Asset references  : $($Results.Count)"
Write-Host "CSV report        : $OutputPath" -ForegroundColor Cyan