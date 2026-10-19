# Find top-level headings for SEO and UX perspective.
# Processes all .md files recursively under the input folder - value of RootFolder.
# Record in .csv format
# Relative file path of .md file, h1, h2 and h3, and first sentence in each heading.
# Extract first para till full stop if it exists. If not, then report as non available.

param (
    [Parameter(Mandatory = $true)]
    [string]$RootFolder,

    [string]$OutputCsv = "md-headings-first-sentence.csv"
)

# Get all Markdown files recursively
$mdFiles = Get-ChildItem -Path $RootFolder -Recurse -Filter *.md -File

$results = foreach ($file in $mdFiles) {

    $relativePath = $file.FullName.Substring($RootFolder.Length).TrimStart('\','/')
    $lines = Get-Content $file.FullName

    for ($i = 0; $i -lt $lines.Count; $i++) {

        # Match title (#), H2 (##), or H3 (###)
        if ($lines[$i] -match '^(#{1,3})\s+(.*)$') {

            $hashes      = $matches[1]
            $headingText = $matches[2].Trim()
            $headingLevel = "H$($hashes.Length)"
            $firstSentence = 'not available'

            # Look for the first non-empty line after the heading
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $nextLine = $lines[$j].Trim()

                # Stop if another heading is encountered
                if ($nextLine -match '^#{1,3}\s+') {
                    break
                }

                if ($nextLine -ne '') {
                    # Extract first sentence (up to first period)
                    if ($nextLine -match '^(.*?\.)') {
                        $firstSentence = $matches[1].Trim()
                    }
                    else {
                        $firstSentence = $nextLine
                    }
                    break
                }
            }

            [PSCustomObject]@{
                RelativePath  = $relativePath
                HeadingLevel  = $headingLevel
                Heading       = $headingText
                FirstSentence = $firstSentence
            }
        }
    }
}

# Export report
$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
