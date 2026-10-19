# ============================================================
# Extract Frontmatter from MDX Files
# Compatible with Windows PowerShell 5.1
# ============================================================

# Prompt for the root folder
$RootFolder = Read-Host "Enter the root folder path containing the MDX files"

# Remove surrounding quotes if the user entered them
$RootFolder = $RootFolder.Trim().Trim('"')

# Normalize path
$RootFolder = [System.IO.Path]::GetFullPath($RootFolder)

# Validate root folder
if (-not (Test-Path -LiteralPath $RootFolder -PathType Container)) {
    Write-Host "The specified folder does not exist:" -ForegroundColor Red
    Write-Host $RootFolder
    exit 1
}

# Output CSV path
$OutputCsv = Join-Path $RootFolder "frontmatter-inventory.csv"

# ------------------------------------------------------------
# Get all MDX files recursively
# ------------------------------------------------------------

$MdxFiles = Get-ChildItem `
    -LiteralPath $RootFolder `
    -Filter "*.mdx" `
    -File `
    -Recurse

if ($MdxFiles.Count -eq 0) {
    Write-Host "No MDX files were found." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Found $($MdxFiles.Count) MDX files." -ForegroundColor Cyan
Write-Host "Extracting frontmatter..."
Write-Host ""

# ------------------------------------------------------------
# Storage
# ------------------------------------------------------------

$Records = @()

# Hashtable for case-insensitive field tracking
# Example:
#   title
#   Title
#   TITLE
# are treated as the same field.
$FieldNames = @{}

# ------------------------------------------------------------
# Process each MDX file
# ------------------------------------------------------------

$FileNumber = 0

foreach ($File in $MdxFiles) {

    $FileNumber++

    # Progress bar
    $PercentComplete = [math]::Round(
        ($FileNumber / $MdxFiles.Count) * 100,
        0
    )

    Write-Progress `
        -Activity "Extracting frontmatter" `
        -Status "$FileNumber of $($MdxFiles.Count): $($File.Name)" `
        -PercentComplete $PercentComplete

    # Root-relative path
    $RelativePath = $File.FullName.Substring($RootFolder.Length).TrimStart('\')

    # Convert Windows backslashes to forward slashes
    $RelativePath = $RelativePath -replace '\\', '/'

    # Read file as a single string
    $Content = Get-Content `
        -LiteralPath $File.FullName `
        -Raw `
        -Encoding UTF8

    # --------------------------------------------------------
    # Check for YAML frontmatter
    #
    # Expected structure:
    #
    # ---
    # title: Example
    # sidebarTitle: Example
    # ---
    # --------------------------------------------------------

    $FrontmatterMatch = [regex]::Match(
        $Content,
        '(?ms)^\s*---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|$)'
    )

    # Create record
    $Record = [ordered]@{}

    # File path is always the first column
    $Record["FilePath"] = $RelativePath

    if ($FrontmatterMatch.Success) {

        $Frontmatter = $FrontmatterMatch.Groups[1].Value

        # ----------------------------------------------------
        # Parse individual frontmatter lines
        #
        # This intentionally handles simple key: value
        # frontmatter fields.
        # ----------------------------------------------------

        foreach ($Line in ($Frontmatter -split '\r?\n')) {

            # Ignore empty lines
            if ([string]::IsNullOrWhiteSpace($Line)) {
                continue
            }

            # Ignore YAML comments
            if ($Line.TrimStart().StartsWith("#")) {
                continue
            }

            # Match:
            # key: value
            #
            # The key may contain letters, numbers,
            # underscores, or hyphens.
            $FieldMatch = [regex]::Match(
                $Line,
                '^\s*([A-Za-z0-9_-]+)\s*:\s*(.*)$'
            )

            if (-not $FieldMatch.Success) {
                continue
            }

            $OriginalFieldName = $FieldMatch.Groups[1].Value
            $FieldValue = $FieldMatch.Groups[2].Value.Trim()

            # ------------------------------------------------
            # Case-insensitive field name handling
            #
            # title, Title and TITLE are considered the same
            # field.
            # ------------------------------------------------

            $FieldKey = $OriginalFieldName.ToLowerInvariant()

            if (-not $FieldNames.ContainsKey($FieldKey)) {

                # Preserve casing from the first occurrence
                $FieldNames[$FieldKey] = $OriginalFieldName
            }

            # Use the canonical field name for this record
            $CanonicalFieldName = $FieldNames[$FieldKey]

            # Remove matching surrounding quotes
            if (
                $FieldValue.Length -ge 2 -and
                (
                    (
                        $FieldValue.StartsWith('"') -and
                        $FieldValue.EndsWith('"')
                    ) -or
                    (
                        $FieldValue.StartsWith("'") -and
                        $FieldValue.EndsWith("'")
                    )
                )
            ) {
                $FieldValue = $FieldValue.Substring(
                    1,
                    $FieldValue.Length - 2
                )
            }

            $Record[$CanonicalFieldName] = $FieldValue
        }
    }

    $Records += [PSCustomObject]$Record
}

# Complete progress bar
Write-Progress `
    -Activity "Extracting frontmatter" `
    -Completed

# ------------------------------------------------------------
# Build a consistent set of CSV columns
# ------------------------------------------------------------

# FilePath should always be first
$Columns = @("FilePath")

# Add frontmatter fields in the order they were first discovered
foreach ($FieldKey in $FieldNames.Keys) {
    $Columns += $FieldNames[$FieldKey]
}

# ------------------------------------------------------------
# Ensure every record has every column
# ------------------------------------------------------------

$NormalizedRecords = foreach ($Record in $Records) {

    $NewRecord = [ordered]@{}

    foreach ($Column in $Columns) {

        if ($Record.PSObject.Properties.Name -contains $Column) {
            $NewRecord[$Column] = $Record.$Column
        }
        else {
            $NewRecord[$Column] = ""
        }
    }

    [PSCustomObject]$NewRecord
}

# ------------------------------------------------------------
# Export CSV
# ------------------------------------------------------------

$NormalizedRecords |
    Export-Csv `
        -LiteralPath $OutputCsv `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

Write-Host ""
Write-Host "Completed." -ForegroundColor Green
Write-Host ""
Write-Host "MDX files processed : $($MdxFiles.Count)"
Write-Host "Frontmatter fields  : $($FieldNames.Count)"
Write-Host "CSV output          : $OutputCsv"
Write-Host ""