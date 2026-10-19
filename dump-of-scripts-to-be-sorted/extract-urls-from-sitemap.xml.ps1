$sitemapUrl = "https://docs.kore.ai/sitemap.xml"

# Fetch sitemap
[xml]$sitemap = Invoke-WebRequest -Uri $sitemapUrl

# Extract URLs
$urls = $sitemap.urlset.url.loc

# Save to file
$urls | Out-File -FilePath "kore_sitemap_urls.txt"

Write-Output "Saved $($urls.Count) URLs to kore_sitemap_urls.txt"