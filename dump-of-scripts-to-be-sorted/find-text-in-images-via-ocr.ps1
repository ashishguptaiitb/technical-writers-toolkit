param (
    [Parameter(Mandatory = $true)]
    [string]$ImageRoot,

    [Parameter(Mandatory = $true)]
    [string]$WordListFile,

    [string]$OutputCsv = "ocr-matches-using-ps.csv",

    [string]$ImageMagickPath = "C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe"
)

$words = Get-Content $WordListFile | Where-Object { $_.Trim() -ne "" }
$patterns = $words | ForEach-Object { [regex]::Escape($_) }

$tesseractPath = "C:\Program Files\Tesseract-OCR\tesseract.exe"

$tempDir = Join-Path $env:TEMP "ocr-prep"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$results = foreach ($img in Get-ChildItem $ImageRoot -Recurse -Include *.png,*.jpg,*.jpeg,*.gif) {

    $relPath = $img.FullName.Substring($ImageRoot.Length).TrimStart('\','/')
    $prepImg = Join-Path $tempDir $img.Name

    & $ImageMagickPath $img.FullName `
        -resize 200% `
        -colorspace Gray `
        -contrast-stretch 0 `
        $prepImg

    $tsv = & $tesseractPath $prepImg stdout --psm 6 tsv 2>$null
    $lines = $tsv -split "`n" | Select-Object -Skip 1

    foreach ($line in $lines) {
        $cols = $line -split "`t"
        if ($cols.Count -lt 11) { continue }

        $text = $cols[11]
        $conf = $cols[10]

        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        foreach ($word in $words) {
            if ($text -match [regex]::Escape($word)) {
                [PSCustomObject]@{
                    ImagePath  = $relPath
                    MatchedKeyword      = $word
                    MatchedFullText    = $text
                    Confidence = $conf
                }
            }
        }
    }
}

$results | Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8
