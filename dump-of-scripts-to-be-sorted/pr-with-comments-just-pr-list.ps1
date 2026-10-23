
$repo = "koredotcom/docs-v2"
$output = ".\prs-with-any-comments.txt"
$tempDir = Join-Path $env:TEMP "gh-pr-comments"
$allNumbers = @()

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Retrieve inline review comments
Write-Progress -Activity "Fetching PR comments" -Status "Inline review comments" -PercentComplete 20
$inlineFile = Join-Path $tempDir "inline.json"

gh api --paginate "repos/$repo/pulls/comments?per_page=100" --slurp > $inlineFile
if ($LASTEXITCODE -ne 0) {
    throw "Failed to retrieve inline review comments."
}

$inlineData = Get-Content $inlineFile -Raw | ConvertFrom-Json
foreach ($page in $inlineData) {
    foreach ($comment in $page) {
        if ($comment.pull_request_url -match '/pulls/(\d+)$') {
            $allNumbers += [int]$Matches[1]
        }
    }
}

# Retrieve general PR conversation comments
Write-Progress -Activity "Fetching PR comments" -Status "Conversation comments" -PercentComplete 50
$conversationFile = Join-Path $tempDir "conversation.json"

gh api --paginate "repos/$repo/issues/comments?per_page=100" --slurp > $conversationFile
if ($LASTEXITCODE -ne 0) {
    throw "Failed to retrieve conversation comments."
}

$conversationData = Get-Content $conversationFile -Raw | ConvertFrom-Json
foreach ($page in $conversationData) {
    foreach ($comment in $page) {
        if ($comment.issue_url -match '/issues/(\d+)$') {
            $allNumbers += [int]$Matches[1]
        }
    }
}

# Retrieve all PRs, then fetch reviews for each PR
Write-Progress -Activity "Fetching PR comments" -Status "Pull request reviews" -PercentComplete 70
$prsFile = Join-Path $tempDir "pulls.json"

gh api --paginate "repos/$repo/pulls?state=all&per_page=100" --slurp > $prsFile
if ($LASTEXITCODE -ne 0) {
    throw "Failed to retrieve pull requests."
}

$prPages = Get-Content $prsFile -Raw | ConvertFrom-Json
$prs = @()
foreach ($page in $prPages) {
    $prs += $page
}

$total = $prs.Count
$index = 0

foreach ($pr in $prs) {
    $index++
    $percent = if ($total -gt 0) { [int](70 + (30 * $index / $total)) } else { 100 }

    Write-Progress -Activity "Fetching PR comments" `
        -Status "Checking reviews for PR $($pr.number) ($index of $total)" `
        -PercentComplete $percent

    $reviews = gh api --paginate "repos/$repo/pulls/$($pr.number)/reviews?per_page=100" 2>$null
    if ($LASTEXITCODE -ne 0) {
        continue
    }

    try {
        $reviewData = $reviews | ConvertFrom-Json
        foreach ($review in $reviewData) {
            if (-not [string]::IsNullOrWhiteSpace($review.body)) {
                $allNumbers += [int]$pr.number
                break
            }
        }
    } catch {
        Write-Verbose "Could not parse reviews for PR $($pr.number)."
    }
}

# Save unique PR numbers
$uniqueNumbers = @($allNumbers | Sort-Object -Unique)
$uniqueNumbers | Set-Content -Path $output -Encoding UTF8

Write-Progress -Activity "Fetching PR comments" -Completed
Write-Host "Unique PRs with comments or review bodies: $($uniqueNumbers.Count)"
Write-Host "Output file: $output"
