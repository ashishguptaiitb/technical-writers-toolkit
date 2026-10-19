# One-liner command to find duplicate PNG, JPEG, and GIF images and create CSV log

Get-ChildItem -Path . -Include "*.jpg","*.jpeg","*.png","*.gif" -Recurse | 
    Get-FileHash -Algorithm SHA256 | 
    Group-Object Hash | 
    Where-Object Count -gt 1 | 
    ForEach-Object { 
        $_.Group | Select-Object @{Name="DuplicateGroup";Expression={$_.Hash.Substring(0,8)}}, Path, Hash, @{Name="SizeKB";Expression={(Get-Item $_.Path).Length / 1KB -as [int]}} 
    } | 
    Export-Csv -Path "duplicate_images_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" -NoTypeInformation

# Alternative: More detailed version with enhanced logging for PNG, JPEG, and GIF only
$ImageExtensions = @('*.jpg','*.jpeg','*.png','*.gif')
$OutputFile = "duplicate_images_detailed_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

Write-Host "Scanning for image files..." -ForegroundColor Green
$AllImages = Get-ChildItem -Path . -Include $ImageExtensions -Recurse -File

Write-Host "Found $($AllImages.Count) image files. Computing hashes..." -ForegroundColor Green
$HashedImages = $AllImages | ForEach-Object -Begin { $i = 0 } -Process {
    $i++
    if ($i % 50 -eq 0) { Write-Progress -Activity "Hashing images" -Status "$i of $($AllImages.Count)" -PercentComplete (($i / $AllImages.Count) * 100) }
    
    try {
        $hash = Get-FileHash -Path $_.FullName -Algorithm SHA256
        [PSCustomObject]@{
            FileName = $_.Name
            FullPath = $_.FullName
            RelativePath = Resolve-Path -Path $_.FullName -Relative
            Extension = $_.Extension.ToLower()
            SizeBytes = $_.Length
            SizeKB = [Math]::Round($_.Length / 1KB, 2)
            SizeMB = [Math]::Round($_.Length / 1MB, 2)
            CreatedDate = $_.CreationTime
            ModifiedDate = $_.LastWriteTime
            Hash = $hash.Hash
            Directory = $_.DirectoryName
        }
    }
    catch {
        Write-Warning "Could not hash file: $($_.FullName) - $_"
        $null
    }
} | Where-Object { $_ -ne $null }

Write-Progress -Activity "Hashing images" -Completed

Write-Host "Identifying duplicates..." -ForegroundColor Green
$DuplicateGroups = $HashedImages | Group-Object Hash | Where-Object Count -gt 1

if ($DuplicateGroups.Count -gt 0) {
    Write-Host "Found $($DuplicateGroups.Count) groups of duplicate images" -ForegroundColor Yellow
    
    $DuplicateReport = foreach ($Group in $DuplicateGroups) {
        $GroupId = $Group.Name.Substring(0,8)
        $TotalSize = ($Group.Group | Measure-Object SizeBytes -Sum).Sum
        $WastedSpace = $TotalSize - ($Group.Group | Sort-Object SizeBytes -Descending | Select-Object -First 1).SizeBytes
        
        foreach ($File in $Group.Group) {
            [PSCustomObject]@{
                DuplicateGroupID = $GroupId
                FileName = $File.FileName
                FullPath = $File.FullPath
                RelativePath = $File.RelativePath
                Extension = $File.Extension
                SizeKB = $File.SizeKB
                SizeMB = $File.SizeMB
                CreatedDate = $File.CreatedDate
                ModifiedDate = $File.ModifiedDate
                Hash = $File.Hash
                Directory = $File.Directory
                GroupCount = $Group.Count
                TotalGroupSizeKB = [Math]::Round($TotalSize / 1KB, 2)
                WastedSpaceKB = [Math]::Round($WastedSpace / 1KB, 2)
                RecommendedAction = if ($File.SizeBytes -eq ($Group.Group | Measure-Object SizeBytes -Maximum).Maximum) { "Keep (Largest)" } else { "Consider Deleting" }
            }
        }
    }
    
    # Export to CSV
    $DuplicateReport | Export-Csv -Path $OutputFile -NoTypeInformation
    Write-Host "Duplicate report saved to: $OutputFile" -ForegroundColor Green
    
    # Display summary
    $TotalDuplicates = ($DuplicateReport | Measure-Object).Count
    $TotalWastedSpace = ($DuplicateReport | Select-Object -Unique DuplicateGroupID, WastedSpaceKB | Measure-Object WastedSpaceKB -Sum).Sum
    
    Write-Host "`nSUMMARY:" -ForegroundColor Cyan
    Write-Host "Total duplicate files: $TotalDuplicates" -ForegroundColor White
    Write-Host "Duplicate groups: $($DuplicateGroups.Count)" -ForegroundColor White
    Write-Host "Wasted storage space: $([Math]::Round($TotalWastedSpace / 1024, 2)) MB" -ForegroundColor White
    
    # Show top duplicate groups
    Write-Host "`nTop 5 largest duplicate groups:" -ForegroundColor Cyan
    $DuplicateGroups | 
        Sort-Object @{Expression={($_.Group | Measure-Object SizeBytes -Sum).Sum}} -Descending | 
        Select-Object -First 5 | 
        ForEach-Object {
            $groupSize = [Math]::Round((($_.Group | Measure-Object SizeBytes -Sum).Sum) / 1MB, 2)
            $sampleFile = $_.Group | Select-Object -First 1
            Write-Host "  $($_.Count) copies of '$($sampleFile.FileName)' ($groupSize MB total)" -ForegroundColor Yellow
        }
} else {
    Write-Host "No duplicate images found!" -ForegroundColor Green
}

# Bonus: PowerShell function for ongoing duplicate detection
function Find-DuplicateImages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Path = ".",
        
        [Parameter(Mandatory=$false)]
        [string[]]$Extensions = @('jpg','jpeg','png','gif'),
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('SHA1','SHA256','MD5')]
        [string]$Algorithm = 'SHA256',
        
        [Parameter(Mandatory=$false)]
        [string]$OutputFile,
        
        [Parameter(Mandatory=$false)]
        [switch]$DeleteDuplicates,
        
        [Parameter(Mandatory=$false)]
        [switch]$InteractiveMode
    )
    
    $ExtensionPatterns = $Extensions | ForEach-Object { "*.$_" }
    
    Write-Host "Scanning for images in: $Path" -ForegroundColor Green
    $Images = Get-ChildItem -Path $Path -Include $ExtensionPatterns -Recurse -File
    
    if ($Images.Count -eq 0) {
        Write-Warning "No image files found!"
        return
    }
    
    Write-Host "Found $($Images.Count) images. Computing $Algorithm hashes..." -ForegroundColor Green
    
    $HashedImages = $Images | ForEach-Object -Begin { $counter = 0 } -Process {
        $counter++
        Write-Progress -Activity "Hashing" -Status $_.Name -PercentComplete (($counter / $Images.Count) * 100)
        
        try {
            $hash = Get-FileHash -Path $_.FullName -Algorithm $Algorithm
            [PSCustomObject]@{
                File = $_
                Hash = $hash.Hash
                Path = $_.FullName
                Name = $_.Name
                Size = $_.Length
            }
        }
        catch {
            Write-Warning "Failed to hash: $($_.FullName)"
            $null
        }
    } | Where-Object { $null -ne $_ }
    
    Write-Progress -Activity "Hashing" -Completed
    
    $Duplicates = $HashedImages | Group-Object Hash | Where-Object Count -gt 1
    
    if ($Duplicates.Count -eq 0) {
        Write-Host "No duplicates found!" -ForegroundColor Green
        return
    }
    
    Write-Host "Found $($Duplicates.Count) groups of duplicates" -ForegroundColor Yellow
    
    $Report = foreach ($Group in $Duplicates) {
        foreach ($Item in $Group.Group) {
            [PSCustomObject]@{
                GroupHash = $Group.Name.Substring(0,8)
                FileName = $Item.Name
                FullPath = $Item.Path
                SizeKB = [Math]::Round($Item.Size / 1KB, 2)
                DuplicateCount = $Group.Count
            }
        }
    }
    
    if ($OutputFile) {
        $Report | Export-Csv -Path $OutputFile -NoTypeInformation
        Write-Host "Report saved to: $OutputFile" -ForegroundColor Green
    }
    
    if ($InteractiveMode) {
        foreach ($Group in $Duplicates) {
            Write-Host "`nFound $($Group.Count) identical copies:" -ForegroundColor Cyan
            $Group.Group | ForEach-Object { Write-Host "  $($_.Path)" }
            
            $choice = Read-Host "Delete duplicates? (y/N/s=skip group)"
            if ($choice -eq 'y') {
                $Group.Group | Select-Object -Skip 1 | ForEach-Object {
                    Remove-Item -Path $_.Path -Force
                    Write-Host "Deleted: $($_.Path)" -ForegroundColor Red
                }
            } elseif ($choice -eq 's') {
                continue
            }
        }
    } elseif ($DeleteDuplicates) {
        $DeletedCount = 0
        foreach ($Group in $Duplicates) {
            # Keep the first file, delete the rest
            $Group.Group | Select-Object -Skip 1 | ForEach-Object {
                Remove-Item -Path $_.Path -Force
                $DeletedCount++
                Write-Host "Deleted: $($_.Path)" -ForegroundColor Red
            }
        }
        Write-Host "Deleted $DeletedCount duplicate files" -ForegroundColor Yellow
    }
    
    return $Report
}

# Usage examples:
<#
# Basic usage - scan current directory
Find-DuplicateImages

# Scan specific path with output file
Find-DuplicateImages -Path "C:\Pictures" -OutputFile "duplicates.csv"

# Interactive mode for selective deletion
Find-DuplicateImages -InteractiveMode

# Automatic deletion (BE CAREFUL!)
Find-DuplicateImages -DeleteDuplicates -OutputFile "deleted_files.csv"

# Custom extensions and algorithm
Find-DuplicateImages -Extensions @('png','jpg') -Algorithm MD5
#>

# Quick command to just list PNG, JPEG, and GIF duplicates without detailed analysis
# Get-ChildItem -Include "*.jpg","*.jpeg","*.png","*.gif" -Recurse | Get-FileHash | Group-Object Hash | Where-Object Count -gt 1 | ForEach-Object { "Duplicate group ($($_.Count) files):"; $_.Group.Path; "" }

# Command to find PNG, JPEG, and GIF duplicates and move them to a separate folder
<#
$DuplicateFolder = ".\Duplicates_$(Get-Date -Format 'yyyyMMdd')"
New-Item -ItemType Directory -Path $DuplicateFolder -Force | Out-Null

Get-ChildItem -Include "*.jpg","*.jpeg","*.png","*.gif" -Recurse | 
    Get-FileHash | 
    Group-Object Hash | 
    Where-Object Count -gt 1 | 
    ForEach-Object { 
        $_.Group | Select-Object -Skip 1 | ForEach-Object {
            $newName = Join-Path $DuplicateFolder (Split-Path $_.Path -Leaf)
            Move-Item $_.Path $newName
            Write-Host "Moved duplicate: $($_.Path) -> $newName"
        }
    }
#>