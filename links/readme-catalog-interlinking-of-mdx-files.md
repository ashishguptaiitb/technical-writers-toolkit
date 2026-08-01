---
title: Check links within repo
description: Offline, automated link check for root-relative cross-linking within articles. No external, absolute urls checked.
---

How it works, content governance use case, prerequisites, and limitations:

* Generate two files and compare - one contains 
* In each article, check links
* Links to .mdx files must be root-relative and not relative. That is, format `[link text](/path/to/file/from/repo/root)` and not `[link text](../../relative/path/from/individual/file)`.
* Works offline with minor manual intervention. Checking is automated.
* Future scope - expand beyond .mdx file checks for 

## How to check 

1. Use PowerShell script [catalog-interlinking-of-mdx-files.ps1](/links/catalog-interlinking-of-mdx-files.ps1) from this repo. Read comments for how to run it. It generates `all-links-to-mdx-files.csv` file as output. The CSV contains these columns: `"SourceFile","SourceRelativePath","LinkedRootPath","Anchor"`.

   ![](/images/links/catalog-interlinking-of-mdx-files1.png)

   ![](/images/links/catalog-interlinking-of-mdx-files2.png)

1. Import this .csv in a spreadsheet and copy just the third column in a separate worksheet. It contains list of all files that are linked from any article in the repo. Some .mdx files contain multiple incoming links. Remove duplicate rows using AI tool or spreadsheet function.

1. Create a separate list of all files in the repo. On Windows, use `dir /s/b > list-of-all-mdx-files-in-repo.txt` command. In this file, find-replace the first part of the local filesystem path to match the pattern of the root-relative path in the above .csv file.

1. Use another PS script [tbd](/link/tbd) to compare the two files - one containing list of .mdx files in the repo and another containing list of links to .mdx files. All mismatches are reported and those are broken links.
