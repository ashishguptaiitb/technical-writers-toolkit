# Find top-level headings for SEO and UX perspective.
# Processes all .md and .mdx files recursively under the input folder - value of RootFolder.
# Record in .csv format the following:
# Relative file path of .md and .mdx files, h1, h2 and h3, and first sentence in each heading.
# If YAML-styled frontmatter is present then use title from there -- goes into the title column in the report. 
# If frontmatter is not present, only then it looks for heading after '#' symbol. Title and Heading are added to separate columns in the .csv report but they both mean the same thing.
# It parses all single hash symbols so code snippets that use '#' may return more than one H1 per article.
# Extract first 100 words or content till the next heading.
# If no content found then reports it as 'not available'.

param (
    [Parameter(Mandatory = $true)]
    [string]$RootFolder,

    [string]$OutputCsv = "md-headings-overview.csv"
)

# Get all .md and .mdx files recursively
$files = Get-ChildItem -Path $RootFolder -Recurse -Include *.md, *.mdx -File

$results = foreach ($file in $files) {

    $relativePath = $file.FullName.Substring($RootFolder.Length).TrimStart('\','/')
    $content = Get-Content $file.FullName -Raw
    $lines   = $content -split "`r?`n"

    # ------------------------------------
    # Resolve page title (exactly once)
    # ------------------------------------
    $pageTitle = 'not available'
    $hasFrontMatter = $false

    # Detect YAML front matter block
    if ($content -match '(?ms)^---\s*\r?\n.*?\r?\n---\s*\r?\n') {
        $hasFrontMatter = $true

        # Extract title ONLY from front matter
        if ($content -match '(?ms)^---\s*\r?\n.*?^title:\s*"?(.+?)"?\s*$.*?\r?\n---') {
            $pageTitle = $matches[1].Trim()
        }
    }

    # Fallback: first H1 ONLY if front matter does NOT exist
    if (-not $hasFrontMatter) {
        foreach ($line in $lines) {
            if ($line -match '^#\s+(.*)$') {
                $pageTitle = $matches[1].Trim()
                break
            }
        }
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {

        # Match H1, H2, H3 headings
        if ($lines[$i] -match '^(#{1,3})\s+(.*)$') {

            $headingLevel = "H$($matches[1].Length)"
            $headingText  = $matches[2].Trim()
            $overviewText = 'not available'
            $wordBuffer   = @()

            # Collect first 100 words under heading
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $line = $lines[$j].Trim()

                if ($line -match '^#{1,3}\s+') {
                    break
                }

                if ($line -ne '') {
                    foreach ($word in ($line -split '\s+')) {
                        $wordBuffer += $word
                        if ($wordBuffer.Count -ge 100) { break }
                    }
                }

                if ($wordBuffer.Count -ge 100) { break }
            }

            if ($wordBuffer.Count -gt 0) {
                $overviewText = ($wordBuffer[0..([Math]::Min(99, $wordBuffer.Count - 1))] -join ' ')
            }

            [PSCustomObject]@{
                RelativePath = $relativePath
                PageTitle    = $pageTitle
                HeadingLevel = $headingLevel
                Heading      = $headingText
                Overview     = $overviewText
            }
        }
    }
}

$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8