# Accept a text file as input to InputFileList. It contains a list of Markdown file names - one filename per row. No relative paths - just a flat list of .md file names. These are MD source files from docs URLs or can be from a file listing.
# Accept  a folder name from me as input to RootFolder. 
# Traverse this folder recursively, looking for that Markdown file. Stop at first MD file. Read it to count the instances of .png in it while being case-insensitive.
# Create a CSV that contains the name of Markdown file and no. of .png instances in the MD file.

param (
    [Parameter(Mandatory = $true)]
    [string]$InputFileList,   # Text file with one Markdown filename per line

    [Parameter(Mandatory = $true)]
    [string]$RootFolder,      # Folder to search recursively

    [string]$OutputCsv = "md-png-count.csv"
)

# Read markdown filenames (ignore empty lines)
$mdFiles = Get-Content $InputFileList | Where-Object { $_.Trim() -ne "" }

$results = foreach ($mdFileName in $mdFiles) {

    # Find the markdown file recursively
    $foundFile = Get-ChildItem -Path $RootFolder -Recurse -Filter $mdFileName -File -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($foundFile) {
        # Read file content as raw text
        $content = Get-Content $foundFile.FullName -Raw

        # Count occurrences of ".png" (case-insensitive)
        $pngCount = ([regex]::Matches($content, '\.png', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    }
    else {
        # File not found
        $pngCount = 0
    }

    [PSCustomObject]@{
        MarkdownFile = $mdFileName
        PngCount     = $pngCount
    }
}

# Export to CSV
$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
