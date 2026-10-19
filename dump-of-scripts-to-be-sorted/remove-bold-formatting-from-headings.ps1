# Parses all .md files in a folder - provide value of RootFolder when executing.
# Removes any bold formatting in the headings.
# Std. .md syntax expected -- headings start with # and bold uses **.
# Preserves UTF-8 encoding to prevent typographic characters getting caught in the cross-fire!
# No reporting - review all changes in GitHub PR.

param (
    [Parameter(Mandatory = $true)]
    [string]$RootFolder
)

$utf8Bom = New-Object System.Text.UTF8Encoding($true)

Get-ChildItem -Path $RootFolder -Recurse -Filter *.md -File | ForEach-Object {

    $filePath = $_.FullName
    $lines = [System.IO.File]::ReadAllLines($filePath, $utf8Bom)

    $changed = $false
    $updatedLines = foreach ($line in $lines) {

        # Match Markdown headings only
        if ($line -match '^(#+\s+)(.*)$') {
            $prefix = $matches[1]
            $headingText = $matches[2]

            $cleanHeading = $headingText -replace '\*\*(.*?)\*\*', '$1'

            if ($cleanHeading -ne $headingText) {
                $changed = $true
            }

            $prefix + $cleanHeading
        }
        else {
            $line
        }
    }

    if ($changed) {
        [System.IO.File]::WriteAllLines($filePath, $updatedLines, $utf8Bom)
    }
}