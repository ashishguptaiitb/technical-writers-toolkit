---
title: Check links within repo
description: Offline, automated link check for root-relative cross-linking within articles. No external, absolute urls checked.
---

How it works, content governance use case, prerequisites, and limitations:

* Generate two files and compare. One file contains list of articles that are linked from all article and the other file contains a list of articles that exist in the repository. A diff between the two lists gives the broken links to help articles that don't exist in the repo.
* Links to .mdx files must be root-relative and not relative. That is, format `[link text](/path/to/file/from/repo/root)` and not `[link text](../../relative/path/from/individual/file)`.
* Works offline with minor manual intervention. Checking is automated.
* Future scope - expand beyond .mdx file checks to also check for validity of anchors. It's a bit tricky as some special characters in headings get converted to a `-` in the URL anchors and some aren't. Mintlify-specific conversion of heading names to anchor needs to be checked first.

## How to check links

1. Use PowerShell script [catalog-interlinking-of-mdx-files.ps1](/links/catalog-interlinking-of-mdx-files.ps1) from this repo. Read comments for how to run it. It generates `all-links-to-mdx-files.csv` file as output. The CSV contains these columns: `"SourceFile","SourceRelativePath","LinkedRootPath","Anchor"`.

   ![](/images/links/catalog-interlinking-of-mdx-files1.png)

   ![](/images/links/catalog-interlinking-of-mdx-files2.png)

1. Import this .csv file in a spreadsheet and copy just the third column in a separate worksheet. It contains list of all files that are linked from any article in the repo. Some .mdx files contain multiple incoming links. Remove duplicate rows using AI tool or spreadsheet function. I use `UNIQUE` function in Google Sheets.

   ![](/images/links/catalog-interlinking-of-mdx-files3.png)

1. Create a separate list of all files in the repo. On Windows, use `dir *.mdx /s/b > list-of-all-mdx-files-in-repo.txt` command. In this file, find-replace the first part of the local filesystem path to match the pattern of the root-relative path in the above .csv file. For example, in .csv a script-generated file path is `/agent-platform/getting-started`, but the command-generated local file path is `C:\Users\Ashish.Gupta\Documents\GitHub\v2docs\agent-platform\getting-started.mdx`. I deleted `C:\Users\Ashish.Gupta\Documents\GitHub\v2docs` from the entire .txt file. Also, find-replace the slashes--`\` with `/`.

1. Compare the two lists of files to find the differences. The linked files that don't exist in the repo are the broken links. Do one of the following:

  * Use another PS script [tbd](/link/tbd) to compare the two files.
  * Use a spreadsheet program to compare two columns containing both the lists of file paths for unique values. Sort the column of linked file paths.

   ![](/images/links/catalog-interlinking-of-mdx-files4.png)

1. Save the list of references to the files in a separate .txt file. This is a list of root-relative paths of .mdx files that don't exist in the repo but are used in some .mdx files.

1. Use PS script [tbd](/link/tbd) to generate a CSV list of non-existent files and the .mdx files containing these links. Edit the latter articles to remove or replace the broken links.
