# Using Git commit history, generate a list of recently updated files. 
# CSV output report contains: Relative file path, commit date (ISO format), GitHub ID (commit author username when available, fallback to author name), File type (extension without dot), and whether the file was Added, Modified, or Renamed.
# Remove duplicates and generate a unique list of files.

param (
    [int]$Days = 15,
    [string]$OutputCsv = "recently-updated-files.csv"
)

# Ensure we are inside a git repo
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "This directory is not a Git repository."
    exit 1
}

# Get commit log with name-status
$log = git log `
    --since="$Days days ago" `
    --pretty=format:"COMMIT|%H|%ad|%an" `
    --date=iso-strict `
    --name-status

$results = @{}
$currentCommitDate = $null
$currentAuthor = $null

foreach ($line in $log) {

    if ($line -like "COMMIT|*") {
        $parts = $line.Split("|")
        $currentCommitDate = $parts[2]
        $currentAuthor = $parts[3]
        continue
    }

    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    # name-status format: <status>\t<path> OR R100\t<old>\t<new>
    $parts = $line -split "`t"

    $status = $parts[0]
    $filePath = $null
    $changeType = $null

    if ($status -like "R*") {
        $filePath = $parts[2]
        $changeType = "Renamed"
    }
    elseif ($status -eq "A") {
        $filePath = $parts[1]
        $changeType = "Added"
    }
    elseif ($status -eq "M") {
        $filePath = $parts[1]
        $changeType = "Modified"
    }
    else {
        continue
    }

    # Keep only the most recent occurrence per file
    if (-not $results.ContainsKey($filePath)) {

        $extension = [System.IO.Path]::GetExtension($filePath)
        if ($extension.StartsWith(".")) {
            $extension = $extension.Substring(1)
        }

        $results[$filePath] = [PSCustomObject]@{
            FilePath   = $filePath
            CommitDate = $currentCommitDate
            Committer  = $currentAuthor
            FileType   = $extension
            ChangeType = $changeType
        }
    }
}

# Export to CSV
$results.Values |
    Sort-Object FilePath |
    Export-Csv -NoTypeInformation -Encoding UTF8 $OutputCsv

Write-Host "Audit CSV created: $OutputCsv"
