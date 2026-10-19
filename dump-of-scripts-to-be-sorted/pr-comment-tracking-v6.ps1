<#
.SYNOPSIS
Retrieves GitHub PR review comments for a list of pull requests and exports
them to a consolidated TSV report.

.PREREQUISITES
- GitHub CLI (gh) installed and authenticated.
- ikawaha/gh-pr-comments extension installed.

Generate the PR list using:

gh pr list --state closed --label "PendingFixes" --json number --jq ".[].number" > pr_numbers.txt
#>

# Prompt for the PR list file.
$inputFile = Read-Host "Enter the path to the PR number text file"
$inputFile = $inputFile.Trim('"')

# Verify the input file exists.
if (-not (Test-Path $inputFile)) {
    Write-Host "Input file not found." -ForegroundColor Red
    exit 1
}

# Create the output file.
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path (Split-Path $inputFile -Parent) "PR_Comments_Report_$timestamp.tsv"

# Read PR numbers.
$prNumbers = Get-Content $inputFile |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { $_.Trim() }

$total = $prNumbers.Count
$count = 0

# Store output rows.
$rows = New-Object System.Collections.Generic.List[object]

foreach ($pr in $prNumbers) {

    $count++

    Write-Progress `
        -Activity "Retrieving PR comments" `
        -Status "Processing PR $pr ($count of $total)" `
        -PercentComplete (($count / $total) * 100)

    try {

        # Execute the extension.
        $jsonText = & gh pr-comments $pr --json 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("PR {0}: {1}" -f $pr, ($jsonText -join " "))
            continue
        }

        if (-not $jsonText) {
            continue
        }

        $json = $jsonText | ConvertFrom-Json

        if (-not $json.ReviewThreads) {
            continue
        }

        foreach ($thread in $json.ReviewThreads) {

            foreach ($comment in $thread.Comments) {

                # Normalize only free-text fields.
                $body = [string]$comment.Body
                $body = $body -replace "`r`n"," "
                $body = $body -replace "`r"," "
                $body = $body -replace "`n"," "
                $body = $body -replace "`t"," "

                $rows.Add([PSCustomObject]@{

                    PR_Number       = $pr

                    File_Path       = $thread.Path
                    Line            = $thread.Line
                    Start_Line      = $thread.StartLine
                    Diff_Side       = $thread.DiffSide

                    Thread_Resolved = $thread.IsResolved
                    Thread_Outdated = $thread.IsOutdated
                    Resolved_By     = $thread.ResolvedBy

                    Comment_ID      = $comment.ID
                    Database_ID     = $comment.DatabaseID

                    Author          = $comment.Author
                    State           = $comment.State

                    Created_At      = $comment.CreatedAt
                    Updated_At      = $comment.UpdatedAt

                    Comment         = $body

                    URL             = $comment.URL

                })

            }

        }

    }
    catch {

        Write-Warning ("PR {0}: {1}" -f $pr, $_.Exception.Message)

    }

}

Write-Progress -Activity "Retrieving PR comments" -Completed

# Export as TSV.
$rows |
    Export-Csv `
        -Path $outputFile `
        -Delimiter "`t" `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host ""
Write-Host "Completed successfully." -ForegroundColor Green
Write-Host "Report saved to:"
Write-Host $outputFile