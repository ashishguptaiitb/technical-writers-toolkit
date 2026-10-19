<#
.SYNOPSIS
    Recursively cleans MDX files and creates plain-text files suitable
    for search indexing.

.DESCRIPTION
    The script recursively processes .mdx files in the specified input
    folder and writes cleaned .txt files to the specified output folder.

    The following transformations are performed:

    - Removes YAML frontmatter.
    - Removes fenced code blocks.
    - Removes Markdown images.
    - Converts Markdown links to their visible link text.
    - Removes HTML/MDX tags while preserving their text content.
    - Removes Markdown heading markers.
    - Removes ordered and unordered list markers.
    - Removes Markdown table syntax and separator rows.
    - Removes bold, italic, and inline-code markers.
    - Removes horizontal rules.
    - Normalizes whitespace.
    - Preserves meaningful article text.

    The source MDX files are never modified.

    A CSV processing report and error log are generated.

.NOTES
    Compatible with Windows PowerShell 5.1.

.EXAMPLE
    .\Strip-Mdx.ps1 `
        -InputFolder "C:\Docs\source" `
        -OutputFolder "C:\Docs\search-build"

.EXAMPLE
    .\Strip-Mdx.ps1 `
        -InputFolder '"C:/Docs/source"' `
        -OutputFolder '"C:/Docs/search-build"' `
        -ReportPath "C:\Docs\search-build\processing-report.csv" `
        -LogPath "C:\Docs\search-build\processing-errors.log"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFolder,

    [Parameter(Mandatory = $true)]
    [string]$OutputFolder,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath
)

# ------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------

function Normalize-PathString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Remove surrounding quotation marks.
    $Path = $Path.Trim()

    if (($Path.StartsWith('"') -and $Path.EndsWith('"')) -or
        ($Path.StartsWith("'") -and $Path.EndsWith("'"))) {
        $Path = $Path.Substring(1, $Path.Length - 2)
    }

    # Normalize forward slashes to Windows backslashes.
    $Path = $Path -replace '/', '\'

    # Remove trailing slash unless the path is a root path.
    if ($Path.Length -gt 3) {
        $Path = $Path.TrimEnd('\')
    }

    return $Path
}

function Remove-MdxFrontmatter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Frontmatter must occur at the beginning of the file.
    # Supports:
    # ---
    # title: ...
    # ---
    #
    # Uses Singleline + Multiline behavior through (?s).

    $pattern = '(?s)\A\s*---\s*\r?\n.*?\r?\n---\s*\r?\n?'

    return [regex]::Replace(
        $Content,
        $pattern,
        '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
}

function Remove-FencedCodeBlocks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Removes fenced blocks beginning with ``` or ~~~.
    # The entire block, including its opening and closing fence,
    # is removed.

    $pattern = '(?ms)^[ \t]*(```|~~~).*?\r?\n[ \t]*\1[ \t]*(?:\r?\n|$)'

    return [regex]::Replace(
        $Content,
        $pattern,
        ''
    )
}

function Remove-MarkdownImages {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Removes:
    # ![alt text](image.png)
    # ![alt text](image.png "title")

    $pattern = '!\[[^\]]*\]\([^)]+\)'

    return [regex]::Replace(
        $Content,
        $pattern,
        ''
    )
}

function Convert-MarkdownLinks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Converts:
    # [visible text](url)
    #
    # into:
    # visible text

    $pattern = '\[([^\]]+)\]\([^)]+\)'

    return [regex]::Replace(
        $Content,
        $pattern,
        '$1'
    )
}

function Remove-MdxAndHtmlTags {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Removes opening, closing, and self-closing HTML/MDX tags.
    #
    # Examples:
    # <Note>
    # </Note>
    # <br />
    # <div class="x">
    #
    # Text between tags is preserved.

    $pattern = '<\/?[A-Za-z][^>]*?>'

    return [regex]::Replace(
        $Content,
        $pattern,
        ''
    )
}

function Remove-MarkdownHeadings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Converts:
    # ## Heading
    #
    # to:
    # Heading

    return [regex]::Replace(
        $Content,
        '(?m)^[ \t]{0,3}#{1,6}[ \t]+',
        ''
    )
}

function Remove-MarkdownListMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Unordered lists:
    # - item
    # * item
    # + item
    #
    # Ordered lists:
    # 1. item
    # 2. item

    $Content = [regex]::Replace(
        $Content,
        '(?m)^[ \t]*(?:[-*+])[ \t]+',
        ''
    )

    $Content = [regex]::Replace(
        $Content,
        '(?m)^[ \t]*\d+\.[ \t]+',
        ''
    )

    return $Content
}

function Remove-MarkdownTableSyntax {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $lines = $Content -split '\r?\n'
    $result = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {

        $trimmed = $line.Trim()

        # Remove Markdown table separator rows.
        #
        # Examples:
        # |------|------|
        # | :--- | ---: |
        #
        if ($trimmed -match '^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$') {
            continue
        }

        # For remaining table rows, remove the pipe delimiters.
        if ($trimmed -match '^\|.*\|$') {
            $cleanLine = $trimmed

            $cleanLine = $cleanLine -replace '^\|', ''
            $cleanLine = $cleanLine -replace '\|$', ''

            $cells = $cleanLine -split '\|'

            $cleanCells = foreach ($cell in $cells) {
                $cell.Trim()
            }

            $result.Add(($cleanCells -join ' '))
        }
        else {
            $result.Add($line)
        }
    }

    return ($result -join [Environment]::NewLine)
}

function Remove-MarkdownEmphasisMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Bold:
    # **text**
    # __text__

    $Content = $Content -replace '\*\*([^*]+)\*\*', '$1'
    $Content = $Content -replace '__([^_]+)__', '$1'

    # Italic:
    # *text*
    # _text_

    $Content = $Content -replace '(?<!\*)\*([^*\r\n]+)\*(?!\*)', '$1'
    $Content = $Content -replace '(?<!_)_([^_\r\n]+)_(?!_)', '$1'

    return $Content
}

function Remove-InlineCodeMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Keep the content but remove backticks.
    #
    # `streamId`
    #
    # becomes:
    #
    # streamId

    return $Content -replace '`([^`]+)`', '$1'
}

function Remove-HorizontalRules {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Removes Markdown horizontal rules:
    # ---
    # ***
    # ___

    return [regex]::Replace(
        $Content,
        '(?m)^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$',
        ''
    )
}

function Normalize-Whitespace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Normalize tabs.
    $Content = $Content -replace "`t", ' '

    # Collapse multiple spaces.
    $Content = $Content -replace '[ ]{2,}', ' '

    # Remove trailing spaces.
    $Content = [regex]::Replace(
        $Content,
        '(?m)[ \t]+$',
        ''
    )

    # Collapse 3+ consecutive blank lines to 2.
    $Content = [regex]::Replace(
        $Content,
        '(\r?\n){3,}',
        "`r`n`r`n"
    )

    return $Content.Trim()
}

function Clean-MdxContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # The order is important.

    $Content = Remove-MdxFrontmatter -Content $Content

    # Remove complete code blocks before processing Markdown syntax.
    $Content = Remove-FencedCodeBlocks -Content $Content

    # Images must be removed before ordinary Markdown links.
    $Content = Remove-MarkdownImages -Content $Content

    # Preserve link text, discard URLs.
    $Content = Convert-MarkdownLinks -Content $Content

    # Preserve text inside HTML/MDX components.
    $Content = Remove-MdxAndHtmlTags -Content $Content

    # Convert tables to plain text.
    $Content = Remove-MarkdownTableSyntax -Content $Content

    # Remove Markdown structure markers.
    $Content = Remove-MarkdownHeadings -Content $Content
    $Content = Remove-MarkdownListMarkers -Content $Content
    $Content = Remove-HorizontalRules -Content $Content

    # Remove formatting markers while preserving their contents.
    $Content = Remove-MarkdownEmphasisMarkers -Content $Content
    $Content = Remove-InlineCodeMarkers -Content $Content

    # Normalize resulting text.
    $Content = Normalize-Whitespace -Content $Content

    return $Content
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    Add-Content -LiteralPath $script:ResolvedLogPath `
        -Value "$timestamp`t$Message"
}

# ------------------------------------------------------------
# INITIALIZE PATHS
# ------------------------------------------------------------

try {
    $InputFolder = Normalize-PathString -Path $InputFolder
    $OutputFolder = Normalize-PathString -Path $OutputFolder

    if (-not (Test-Path -LiteralPath $InputFolder -PathType Container)) {
        throw "Input folder does not exist: $InputFolder"
    }

    # Resolve input path.
    $InputFolder = (Resolve-Path -LiteralPath $InputFolder).Path

    # Create output folder if required.
    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }

    $OutputFolder = (Resolve-Path -LiteralPath $OutputFolder).Path

    # Default report and log locations.
    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $ReportPath = Join-Path $OutputFolder 'mdx-processing-report.csv'
    }
    else {
        $ReportPath = Normalize-PathString -Path $ReportPath
    }

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Join-Path $OutputFolder 'mdx-processing-errors.log'
    }
    else {
        $LogPath = Normalize-PathString -Path $LogPath
    }

    $ReportDirectory = Split-Path -Parent $ReportPath
    $LogDirectory = Split-Path -Parent $LogPath

    if (-not [string]::IsNullOrWhiteSpace($ReportDirectory) -and
        -not (Test-Path -LiteralPath $ReportDirectory)) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($LogDirectory) -and
        -not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $script:ResolvedLogPath = $LogPath

    # Start a fresh log.
    if (Test-Path -LiteralPath $LogPath) {
        Remove-Item -LiteralPath $LogPath -Force
    }

    Write-Log "MDX cleaning process started."
    Write-Log "Input folder: $InputFolder"
    Write-Log "Output folder: $OutputFolder"
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

# ------------------------------------------------------------
# FIND MDX FILES
# ------------------------------------------------------------

try {
    $MdxFiles = @(
        Get-ChildItem `
            -LiteralPath $InputFolder `
            -Filter '*.mdx' `
            -File `
            -Recurse `
            -ErrorAction Stop
    )
}
catch {
    Write-Log "Failed to enumerate MDX files. Error: $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 1
}

$totalFiles = $MdxFiles.Count

if ($totalFiles -eq 0) {
    Write-Log "No MDX files found."
    Write-Warning "No .mdx files were found in: $InputFolder"
    exit 0
}

Write-Log "MDX files found: $totalFiles"

# ------------------------------------------------------------
# PROCESS FILES
# ------------------------------------------------------------

$ReportRows = New-Object System.Collections.Generic.List[object]

$processed = 0
$succeeded = 0
$failed = 0

foreach ($MdxFile in $MdxFiles) {

    $processed++

    $percent = [math]::Round(($processed / $totalFiles) * 100, 0)

    Write-Progress `
        -Activity "Cleaning MDX files" `
        -Status "Processing $processed of $totalFiles : $($MdxFile.Name)" `
        -PercentComplete $percent

    $status = 'Success'
    $errorMessage = ''
    $txtPath = ''
    $characterCount = 0

    try {

        # Calculate path relative to input root.
        $relativePath = $MdxFile.FullName.Substring(
            $InputFolder.Length
        ).TrimStart('\')

        # Preserve directory structure but change extension to .txt.
        $relativeDirectory = Split-Path -Parent $relativePath

        $txtFileName = [System.IO.Path]::GetFileNameWithoutExtension(
            $MdxFile.Name
        ) + '.txt'

        if ([string]::IsNullOrWhiteSpace($relativeDirectory)) {
            $outputDirectory = $OutputFolder
        }
        else {
            $outputDirectory = Join-Path `
                $OutputFolder `
                $relativeDirectory
        }

        if (-not (Test-Path -LiteralPath $outputDirectory)) {
            New-Item `
                -ItemType Directory `
                -Path $outputDirectory `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        $txtPath = Join-Path $outputDirectory $txtFileName

        # Read MDX as UTF-8.
        $content = [System.IO.File]::ReadAllText(
            $MdxFile.FullName,
            [System.Text.Encoding]::UTF8
        )

        # Clean content.
        $cleanContent = Clean-MdxContent -Content $content

        $characterCount = $cleanContent.Length

        # Write UTF-8 without BOM.
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        [System.IO.File]::WriteAllText(
            $txtPath,
            $cleanContent,
            $utf8NoBom
        )

        $succeeded++

        Write-Log "SUCCESS: $($MdxFile.FullName) -> $txtPath"

    }
    catch {

        $status = 'Failed'
        $failed++

        $errorMessage = $_.Exception.Message

        Write-Log "FAILED: $($MdxFile.FullName)"
        Write-Log "ERROR: $errorMessage"
    }

    $ReportRows.Add(
        [PSCustomObject]@{
            Status          = $status
            MDXPath         = $MdxFile.FullName
            TXTPath         = $txtPath
            RelativePath    = $relativePath
            FileName        = $MdxFile.Name
            CharacterCount  = $characterCount
            Error           = $errorMessage
        }
    )
}

Write-Progress `
    -Activity "Cleaning MDX files" `
    -Status "Completed" `
    -PercentComplete 100 `
    -Completed

# ------------------------------------------------------------
# WRITE REPORT
# ------------------------------------------------------------

try {

    $ReportRows |
        Export-Csv `
            -LiteralPath $ReportPath `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Force

    Write-Log "CSV report created: $ReportPath"
}
catch {

    Write-Log "FAILED: Could not create CSV report."
    Write-Log "ERROR: $($_.Exception.Message)"

    Write-Error "Could not create CSV report: $($_.Exception.Message)"
}

Write-Log "Processing completed."
Write-Log "Total files: $totalFiles"
Write-Log "Successful: $succeeded"
Write-Log "Failed: $failed"

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------

Write-Host ''
Write-Host '============================================='
Write-Host 'MDX cleaning completed'
Write-Host '============================================='
Write-Host "Input folder : $InputFolder"
Write-Host "Output folder: $OutputFolder"
Write-Host "Total files  : $totalFiles"
Write-Host "Successful   : $succeeded"
Write-Host "Failed       : $failed"
Write-Host "Report       : $ReportPath"
Write-Host "Error log    : $LogPath"
Write-Host '============================================='