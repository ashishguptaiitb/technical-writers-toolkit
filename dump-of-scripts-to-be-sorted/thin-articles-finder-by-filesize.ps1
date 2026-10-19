$MaxSizeBytes = 3KB
$RootPath = (Get-Location).Path

Get-ChildItem -Path $RootPath -Recurse -File -Filter *.md -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -lt $MaxSizeBytes } |
    Select-Object FullName |
    Sort-Object FullName |
    Export-Csv -Path ".\small-markdown-files.csv" -NoTypeInformation -Encoding UTF8
