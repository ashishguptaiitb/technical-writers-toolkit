param (
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "url_status_output.csv"
)

# Validate input file
if (!(Test-Path $InputFile)) {
    Write-Error "Input file not found: $InputFile"
    exit 1
}

# Read URLs
$urls = Get-Content $InputFile | Where-Object { $_.Trim() -ne "" }

$results = @()

foreach ($url in $urls) {
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head -MaximumRedirection 5 -ErrorAction Stop

        $statusCode = $response.StatusCode
        $statusDescription = $response.StatusDescription
    }
    catch {
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $statusDescription = $_.Exception.Response.StatusDescription
        }
        else {
            $statusCode = "ERROR"
            $statusDescription = $_.Exception.Message
        }
    }

    $results += [PSCustomObject]@{
        URL                = $url
        StatusCode         = $statusCode
        StatusDescription  = $statusDescription
    }
}

# Export to CSV
$results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

Write-Output "Output written to $OutputFile"