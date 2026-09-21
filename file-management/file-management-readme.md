---
title: File management in a docs repo
description: Various file management JTBDs in a doc GitHub repository.
---

| Script | Use case | Remarks |
|:-------|:---------|:--------|
| [report-existence-of-file-from-full-filepaths](/file-management/report-existence-of-file-from-full-filepaths.ps1) | Verify if files exist on filesystem at a given path or not. Useful to check if sources (not destinations) of redirects exist in repo or not. If a file exists then redirect not required. |  |
| [copy-files-across-folders-preserve-folder-structure](/file-management/copy-files-across-folders-preserve-folder-structure.ps1) | Find list of unused assets, offending files, archival candidates, etc. in a repo and move those to an archive folder outside GitHub repo. Preserve folder structure for later findability and audits. |  |
