function Get-RecordBackupDigest {
    param([string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($algorithm.ComputeHash($stream)) }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Move-RecordBackupToRecycleBin {
    param([string]$Path)
    return [RecorderRecycle.Backup]::MoveToRecycleBin($Path, $form.Handle)
}

function New-RecordBackupInRecycleBin {
    param([IO.FileStream]$Source, [string]$OriginalPath)
    $directory = [IO.Path]::GetDirectoryName($OriginalPath)
    $baseName = [IO.Path]::GetFileNameWithoutExtension($OriginalPath)
    if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = '记录备份' }
    $stem = $baseName + '_' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff')
    $number = 0
    do {
        $suffix = if ($number -eq 0) { '' } else { '_' + $number }
        $path = Join-Path $directory ($stem + $suffix + '.txt')
        $number++
    } while ([IO.File]::Exists($path))
    # CreateNew prevents overwriting an unrelated file on a naming collision.
    $backup = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $Source.Position = 0; $Source.CopyTo($backup); $backup.Flush($true) }
    finally { $backup.Dispose() }
    $digest = Get-RecordBackupDigest -Path $path
    $recycledPath = Move-RecordBackupToRecycleBin -Path $path
    if ([IO.File]::Exists($path) -or -not [IO.File]::Exists($recycledPath) -or (Get-RecordBackupDigest -Path $recycledPath) -ne $digest) {
        throw '无法确认完整备份已进入回收站，原记录未清空。'
    }
    return @{ Name = [IO.Path]::GetFileName($path); OriginalPath = $path; RecycledPath = $recycledPath }
}
