Get-ChildItem -File | ForEach-Object {

    $oldName = $_.Name

    # Match YYYY-MM-DD- at the beginning of the filename
    if ($oldName -match '^\d{4}-\d{2}-\d{2}-(.+)$') {
        $newName = $matches[1]

        Rename-Item -Path $_.FullName -NewName $newName
    }
}
