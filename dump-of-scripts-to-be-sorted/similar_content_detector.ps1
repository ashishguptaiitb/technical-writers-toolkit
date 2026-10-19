#Requires -Version 5.0
<#
.SYNOPSIS
    Finds duplicate or overlapping content in Markdown files within a repository.

.DESCRIPTION
    This script analyzes Markdown files to identify pairs with overlapping content above a specified threshold.
    It preprocesses content to remove metadata, formatting, and focuses on meaningful text comparison.

.PARAMETER RepositoryPath
    Path to the repository containing Markdown files

.PARAMETER SimilarityThreshold
    Minimum similarity threshold (0.0-1.0) for reporting duplicates. Default is 0.2 (20%)

.PARAMETER Method
    Detection method: 'Basic' for simple comparison, 'Shingle' for advanced n-gram analysis

.PARAMETER OutputFile
    Optional output file for detailed report

.PARAMETER ShingleSize
    Size of text shingles for shingle method (default: 5)

.PARAMETER IncludeSubdirectories
    Include subdirectories in search (default: true)

.EXAMPLE
    .\Find-MarkdownDuplicates.ps1 -RepositoryPath "C:\MyRepo" -SimilarityThreshold 0.2 -OutputFile "duplicates.md"

.EXAMPLE
    .\Find-MarkdownDuplicates.ps1 -RepositoryPath "." -Method Shingle -SimilarityThreshold 0.15
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$RepositoryPath,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(0.0, 1.0)]
    [double]$SimilarityThreshold = 0.2,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Basic', 'Shingle')]
    [string]$Method = 'Basic',
    
    [Parameter(Mandatory = $false)]
    [string]$OutputFile,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(2, 10)]
    [int]$ShingleSize = 5,
    
    [Parameter(Mandatory = $false)]
    [bool]$IncludeSubdirectories = $true
)

# Class to represent file similarity results
class FileSimilarity {
    [string]$File1Path
    [string]$File2Path
    [double]$SimilarityScore
    [int]$File1WordCount
    [int]$File2WordCount
    [int]$CommonSentences
    [double]$OverlapPercentage
    
    FileSimilarity([string]$file1, [string]$file2, [double]$similarity) {
        $this.File1Path = $file1
        $this.File2Path = $file2
        $this.SimilarityScore = $similarity
    }
}

# Function to extract and clean content from Markdown files
function Get-CleanedMarkdownContent {
    param([string]$FilePath)
    
    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not read file: $FilePath"
        return ""
    }
    
    if ([string]::IsNullOrWhiteSpace($content)) {
        return ""
    }
    
    # Remove YAML frontmatter
    $content = $content -replace '(?s)^---\s*\r?\n.*?\r?\n---\s*\r?\n', ''
    
    # Remove HTML comments
    $content = $content -replace '(?s)<!--.*?-->', ''
    
    # Remove code blocks (keep inline code)
    $content = $content -replace '(?s)```.*?```', ''
    
    # Remove images but keep alt text
    $content = $content -replace '!\[([^\]]*)\]\([^\)]*\)', '$1'
    
    # Remove links but keep link text
    $content = $content -replace '\[([^\]]*)\]\([^\)]*\)', '$1'
    
    # Remove Markdown formatting
    $content = $content -replace '[#*_`]', ''
    
    # Remove extra whitespace and normalize
    $content = ($content -replace '\s+', ' ').Trim().ToLower()
    
    return $content
}

# Function to calculate similarity using Levenshtein-based approach
function Get-ContentSimilarity {
    param(
        [string]$Content1,
        [string]$Content2
    )
    
    if ([string]::IsNullOrWhiteSpace($Content1) -or [string]::IsNullOrWhiteSpace($Content2)) {
        return 0.0
    }
    
    # Simple similarity calculation using common words
    $words1 = $Content1 -split '\s+' | Where-Object { $_.Length -gt 2 }
    $words2 = $Content2 -split '\s+' | Where-Object { $_.Length -gt 2 }
    
    if ($words1.Count -eq 0 -or $words2.Count -eq 0) {
        return 0.0
    }
    
    # Create hashtables for faster lookup
    $set1 = @{}
    $words1 | ForEach-Object { $set1[$_] = $true }
    
    $set2 = @{}
    $words2 | ForEach-Object { $set2[$_] = $true }
    
    # Count common words
    $commonWords = 0
    foreach ($word in $set1.Keys) {
        if ($set2.ContainsKey($word)) {
            $commonWords++
        }
    }
    
    # Calculate Jaccard similarity
    $totalUniqueWords = $set1.Count + $set2.Count - $commonWords
    if ($totalUniqueWords -eq 0) {
        return 0.0
    }
    
    return [double]$commonWords / $totalUniqueWords
}

# Function to calculate similarity using shingle method
function Get-ShingleSimilarity {
    param(
        [string]$Content1,
        [string]$Content2,
        [int]$ShingleSize = 5
    )
    
    if ([string]::IsNullOrWhiteSpace($Content1) -or [string]::IsNullOrWhiteSpace($Content2)) {
        return 0.0
    }
    
    function Get-Shingles($content, $size) {
        $words = $content -split '\s+' | Where-Object { $_.Length -gt 0 }
        if ($words.Count -lt $size) {
            return @()
        }
        
        $shingles = @{}
        for ($i = 0; $i -le $words.Count - $size; $i++) {
            $shingle = ($words[$i..($i + $size - 1)] -join ' ')
            $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($shingle))
            $hashString = [BitConverter]::ToString($hash) -replace '-', ''
            $shingles[$hashString] = $true
        }
        return $shingles.Keys
    }
    
    $shingles1 = Get-Shingles $Content1 $ShingleSize
    $shingles2 = Get-Shingles $Content2 $ShingleSize
    
    if ($shingles1.Count -eq 0 -or $shingles2.Count -eq 0) {
        return 0.0
    }
    
    # Create hashtables for intersection calculation
    $set1 = @{}
    $shingles1 | ForEach-Object { $set1[$_] = $true }
    
    $intersection = 0
    foreach ($shingle in $shingles2) {
        if ($set1.ContainsKey($shingle)) {
            $intersection++
        }
    }
    
    # Jaccard similarity: intersection / union
    $union = $shingles1.Count + $shingles2.Count - $intersection
    return if ($union -eq 0) { 0.0 } else { [double]$intersection / $union }
}

# Function to analyze detailed overlap between two files
function Get-DetailedOverlapAnalysis {
    param(
        [string]$FilePath1,
        [string]$FilePath2
    )
    
    $content1 = Get-CleanedMarkdownContent -FilePath $FilePath1
    $content2 = Get-CleanedMarkdownContent -FilePath $FilePath2
    
    # Split into sentences for detailed analysis
    $sentences1 = $content1 -split '[.!?]+' | Where-Object { $_.Trim().Length -gt 20 }
    $sentences2 = $content2 -split '[.!?]+' | Where-Object { $_.Trim().Length -gt 20 }
    
    $commonSentences = 0
    foreach ($s1 in $sentences1) {
        foreach ($s2 in $sentences2) {
            $similarity = Get-ContentSimilarity -Content1 $s1.Trim() -Content2 $s2.Trim()
            if ($similarity -gt 0.8) {
                $commonSentences++
                break
            }
        }
    }
    
    $overlapPercentage = if ($sentences1.Count -gt 0 -and $sentences2.Count -gt 0) {
        [double]$commonSentences / [Math]::Min($sentences1.Count, $sentences2.Count) * 100
    } else { 0.0 }
    
    return @{
        File1WordCount = ($content1 -split '\s+').Count
        File2WordCount = ($content2 -split '\s+').Count
        CommonSentences = $commonSentences
        OverlapPercentage = $overlapPercentage
    }
}

# Function to find all Markdown files
function Get-MarkdownFiles {
    param([string]$Path, [bool]$Recurse = $true)
    
    $searchParams = @{
        Path = $Path
        Filter = "*.md"
        File = $true
    }
    
    if ($Recurse) {
        $searchParams.Recurse = $true
    }
    
    $mdFiles = @(Get-ChildItem @searchParams)
    
    # Also search for .markdown files
    $searchParams.Filter = "*.markdown"
    $markdownFiles = @(Get-ChildItem @searchParams)
    
    return $mdFiles + $markdownFiles
}

# Main function to find duplicate pairs
function Find-DuplicatePairs {
    param(
        [string]$RepoPath,
        [double]$Threshold,
        [string]$DetectionMethod,
        [int]$ShingleSize
    )
    
    Write-Host "Searching for Markdown files..." -ForegroundColor Green
    $markdownFiles = Get-MarkdownFiles -Path $RepoPath -Recurse $IncludeSubdirectories
    
    if ($markdownFiles.Count -eq 0) {
        Write-Warning "No Markdown files found in the specified path."
        return @()
    }
    
    Write-Host "Found $($markdownFiles.Count) Markdown files. Analyzing content..." -ForegroundColor Green
    
    $duplicates = @()
    $totalComparisons = [Math]::Floor($markdownFiles.Count * ($markdownFiles.Count - 1) / 2)
    $currentComparison = 0
    
    # Progress tracking
    $progressActivity = "Analyzing duplicate content"
    
    for ($i = 0; $i -lt $markdownFiles.Count; $i++) {
        $file1 = $markdownFiles[$i]
        $content1 = Get-CleanedMarkdownContent -FilePath $file1.FullName
        
        # Skip very short files
        if ($content1.Length -lt 100) {
            continue
        }
        
        for ($j = $i + 1; $j -lt $markdownFiles.Count; $j++) {
            $currentComparison++
            
            # Update progress every 10 comparisons
            if ($currentComparison % 10 -eq 0) {
                $percentComplete = [Math]::Floor(($currentComparison / $totalComparisons) * 100)
                Write-Progress -Activity $progressActivity -Status "Comparing files..." -PercentComplete $percentComplete
            }
            
            $file2 = $markdownFiles[$j]
            $content2 = Get-CleanedMarkdownContent -FilePath $file2.FullName
            
            # Skip very short files
            if ($content2.Length -lt 100) {
                continue
            }
            
            # Calculate similarity based on method
            $similarity = if ($DetectionMethod -eq 'Shingle') {
                Get-ShingleSimilarity -Content1 $content1 -Content2 $content2 -ShingleSize $ShingleSize
            } else {
                Get-ContentSimilarity -Content1 $content1 -Content2 $content2
            }
            
            if ($similarity -ge $Threshold) {
                $fileSim = [FileSimilarity]::new($file1.FullName, $file2.FullName, $similarity)
                
                # Add detailed analysis
                $detailAnalysis = Get-DetailedOverlapAnalysis -FilePath1 $file1.FullName -FilePath2 $file2.FullName
                $fileSim.File1WordCount = $detailAnalysis.File1WordCount
                $fileSim.File2WordCount = $detailAnalysis.File2WordCount
                $fileSim.CommonSentences = $detailAnalysis.CommonSentences
                $fileSim.OverlapPercentage = $detailAnalysis.OverlapPercentage
                
                $duplicates += $fileSim
            }
        }
    }
    
    Write-Progress -Activity $progressActivity -Completed
    
    # Sort by similarity score (highest first)
    return $duplicates | Sort-Object SimilarityScore -Descending
}

# Function to generate detailed report
function New-DuplicateContentReport {
    param(
        [array]$Duplicates,
        [string]$RepoPath,
        [double]$Threshold,
        [string]$OutputPath
    )
    
    $reportLines = @()
    $reportLines += "# Duplicate Content Analysis Report"
    $reportLines += ""
    $reportLines += "**Repository:** $RepoPath"
    $reportLines += "**Analysis Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $reportLines += "**Similarity Threshold:** $($Threshold * 100)%"
    $reportLines += "**Total Duplicates Found:** $($Duplicates.Count)"
    $reportLines += ""
    
    # Categorize by similarity level
    $highSimilarity = $Duplicates | Where-Object { $_.SimilarityScore -ge 0.7 }
    $mediumSimilarity = $Duplicates | Where-Object { $_.SimilarityScore -ge 0.4 -and $_.SimilarityScore -lt 0.7 }
    $lowSimilarity = $Duplicates | Where-Object { $_.SimilarityScore -lt 0.4 }
    
    $reportLines += "## Summary by Similarity Level"
    $reportLines += ""
    $reportLines += "- **High similarity (70%+):** $($highSimilarity.Count) pairs"
    $reportLines += "- **Medium similarity (40-69%):** $($mediumSimilarity.Count) pairs"
    $reportLines += "- **Low similarity (20-39%):** $($lowSimilarity.Count) pairs"
    $reportLines += ""
    $reportLines += "## Detailed Results"
    $reportLines += ""
    
    foreach ($duplicate in $Duplicates) {
        $relPath1 = (Resolve-Path -Path $duplicate.File1Path -Relative) -replace '\\', '/'
        $relPath2 = (Resolve-Path -Path $duplicate.File2Path -Relative) -replace '\\', '/'
        
        $reportLines += "### Similarity: $($duplicate.SimilarityScore.ToString('P1'))"
        $reportLines += ""
        $reportLines += "- **File 1:** ``$relPath1``"
        $reportLines += "- **File 2:** ``$relPath2``"
        $reportLines += "- **File 1 length:** $($duplicate.File1WordCount) words"
        $reportLines += "- **File 2 length:** $($duplicate.File2WordCount) words"
        $reportLines += "- **Common sentences:** $($duplicate.CommonSentences)"
        $reportLines += "- **Estimated overlap:** $($duplicate.OverlapPercentage.ToString('F1'))%"
        $reportLines += ""
    }
    
    $reportContent = $reportLines -join "`n"
    
    if ($OutputPath) {
        try {
            Set-Content -Path $OutputPath -Value $reportContent -Encoding UTF8
            Write-Host "Report saved to: $OutputPath" -ForegroundColor Green
        }
        catch {
            Write-Error "Could not save report to $OutputPath`: $_"
            Write-Host $reportContent
        }
    } else {
        Write-Host $reportContent
    }
}

# Main execution
try {
    Write-Host "Starting duplicate content analysis..." -ForegroundColor Cyan
    Write-Host "Repository: $RepositoryPath" -ForegroundColor Yellow
    Write-Host "Method: $Method" -ForegroundColor Yellow
    Write-Host "Threshold: $($SimilarityThreshold * 100)%" -ForegroundColor Yellow
    Write-Host ""
    
    $duplicates = Find-DuplicatePairs -RepoPath $RepositoryPath -Threshold $SimilarityThreshold -DetectionMethod $Method -ShingleSize $ShingleSize
    
    if ($duplicates.Count -gt 0) {
        Write-Host "Found $($duplicates.Count) pairs of similar files:" -ForegroundColor Green
        New-DuplicateContentReport -Duplicates $duplicates -RepoPath $RepositoryPath -Threshold $SimilarityThreshold -OutputPath $OutputFile
    } else {
        Write-Host "No duplicate content found above the threshold." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "An error occurred during analysis: $_"
    exit 1
}

# Additional utility functions for quick checks
<#
.SYNOPSIS
Quick PowerShell one-liners for basic duplicate detection:

# Find exact duplicate files by hash
Get-ChildItem -Path . -Filter "*.md" -Recurse | Get-FileHash | Group-Object Hash | Where-Object Count -gt 1

# Find files with similar sizes (within 5% difference)
Get-ChildItem -Path . -Filter "*.md" -Recurse | 
    Select-Object Name, FullName, Length | 
    Sort-Object Length | 
    ForEach-Object -Begin { $prev = $null } -Process {
        if ($prev -and $_.Length -gt 0 -and $prev.Length -gt 0) {
            $diff = [Math]::Abs($_.Length - $prev.Length) / $prev.Length
            if ($diff -le 0.05) {
                Write-Output "Similar sizes: $($prev.Name) ($($prev.Length)) vs $($_.Name) ($($_.Length))"
            }
        }
        $prev = $_
    }

# Find files with identical line counts
Get-ChildItem -Path . -Filter "*.md" -Recurse | 
    ForEach-Object { 
        [PSCustomObject]@{
            File = $_.FullName
            Lines = (Get-Content $_.FullName | Measure-Object).Count
        }
    } | 
    Group-Object Lines | 
    Where-Object Count -gt 1 | 
    ForEach-Object { 
        Write-Output "Files with $($_.Name) lines:"
        $_.Group.File
    }
#>