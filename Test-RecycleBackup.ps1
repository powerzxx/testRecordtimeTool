$ErrorActionPreference = 'Stop'
$originalAppData = $env:APPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RecorderRecycleTest-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$env:APPDATA = $testRoot
$script:recycledTestFiles = New-Object Collections.Generic.List[object]
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Restore-TestBackup($Receipt) {
    if (-not [IO.File]::Exists($Receipt.RecycledPath)) { return }
    Assert (-not [IO.File]::Exists($Receipt.OriginalPath)) 'Test restore would overwrite an existing file'
    $shell = New-Object -ComObject Shell.Application
    $bin = $shell.Namespace(10)
    $item = $null
    try {
        foreach ($candidate in $bin.Items()) {
            if ([string]::Equals($candidate.Path, $Receipt.RecycledPath, [StringComparison]::OrdinalIgnoreCase)) { $item = $candidate; break }
        }
        Assert ($null -ne $item) 'Native receipt not found in the visible Windows Recycle Bin'
        Assert ([string]::Equals([string]$item.ExtendedProperty('System.Recycle.DeletedFrom'), [IO.Path]::GetDirectoryName($Receipt.OriginalPath), [StringComparison]::OrdinalIgnoreCase)) 'Recycle Bin lost the original backup directory'
        $item.InvokeVerb('undelete')
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (-not [IO.File]::Exists($Receipt.OriginalPath) -and $watch.ElapsedMilliseconds -lt 10000) {
            [Windows.Forms.Application]::DoEvents()
            [Threading.Thread]::Sleep(50)
        }
        Assert ([IO.File]::Exists($Receipt.OriginalPath) -and -not [IO.File]::Exists($Receipt.RecycledPath)) 'Recycle Bin restore did not return the backup to its original path'
    }
    finally {
        if ($item) { [Runtime.InteropServices.Marshal]::ReleaseComObject($item) | Out-Null }
        if ($bin) { [Runtime.InteropServices.Marshal]::ReleaseComObject($bin) | Out-Null }
        [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
}
try {
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RecordTime.ps1'))
    $source = $source.Replace('[System.Windows.Forms.Application]::Run($form)', '').Replace('$PSScriptRoot', "'" + $PSScriptRoot.Replace("'", "''") + "'")
    . ([scriptblock]::Create($source))
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    foreach ($name in @('A', 'B')) {
        $nameInput.Text = $name; $addButton.PerformClick()
        Add-StepButton -Name $name | Out-Null
    }
    Sync-Steps
    $logDirectory = Join-Path $testRoot 'logs'
    [IO.Directory]::CreateDirectory($logDirectory) | Out-Null
    $script:activeLogPath = Join-Path $logDirectory '耳机操作记录.txt'
    [IO.File]::WriteAllText($script:activeLogPath, "--- 第 6 轮 ---`r`n10:11:12.345 入仓关盖`r`n10:11:14 开盖`r`n", (New-Object Text.UTF8Encoding($true)))
    Load-LogRows -Lines ([IO.File]::ReadAllLines($script:activeLogPath))
    Reset-StepProgress -Round 7
    Invoke-NextStep
    $bytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:activeLogPath))
    $pending = $script:pendingSteps[0]; $undo = $script:undoSpace
    $clearCode = (Get-Command Clear-LogWithBackup).ScriptBlock.ToString()
    $clearCode = [regex]::Replace($clearCode, '\[Windows.Forms.MessageBox\]::Show\([^\r\n]+?\)', '$script:testClearAnswer')
    Set-Item Function:Clear-LogWithBackup -Value ([scriptblock]::Create($clearCode))
    $script:testClearAnswer = 'No'
    Assert (-not (Clear-LogWithBackup) -and @(Get-ChildItem -LiteralPath $logDirectory -File).Count -eq 1) 'Cancelled clear created a backup'
    $script:testClearAnswer = 'Yes'
    $locked = [IO.File]::Open($script:activeLogPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $failed = $false
    try { Clear-LogWithBackup | Out-Null } catch { $failed = $true } finally { $locked.Dispose() }
    Assert ($failed -and $form.Enabled -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:activeLogPath)) -eq $bytes) 'Locked source was modified or form stayed disabled'
    Set-Item Function:Move-RecordBackupToRecycleBin -Value { param($Path) throw 'Simulated unavailable Recycle Bin' }
    $failed = $false
    try { Clear-LogWithBackup | Out-Null } catch { $failed = $true }
    Assert ($failed -and $form.Enabled -and $script:currentRound -eq 7 -and $script:pendingSteps[0] -eq $pending -and $script:undoSpace -eq $undo) 'Recycle failure changed execution state'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($script:activeLogPath)) -eq $bytes) 'Recycle failure cleared source'
    $failedCopies = @(Get-ChildItem -LiteralPath $logDirectory -Filter '耳机操作记录_*.txt')
    Assert ($failedCopies.Count -eq 1 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($failedCopies[0].FullName)) -eq $bytes) 'Recycle failure did not preserve the local copy'
    Set-Item Function:Move-RecordBackupToRecycleBin -Value { param($Path) return (Join-Path $testRoot 'not-in-recycle-bin.txt') }
    $failed = $false
    try { Clear-LogWithBackup | Out-Null } catch { $failed = $true }
    Assert ($failed -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:activeLogPath)) -eq $bytes) 'Unverified recycling was treated as success'
    Set-Item Function:Move-RecordBackupToRecycleBin -Value {
        param([string]$Path)
        Assert (-not $form.Enabled) 'Main form can accept input during clear'
        $foreignWriteBlocked = $false
        try { $writer = [IO.File]::Open($script:activeLogPath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite); $writer.Dispose() }
        catch { $foreignWriteBlocked = $true }
        Assert ($foreignWriteBlocked) 'Concurrent writer can change the log while its backup is recycled'
        $recycled = [RecorderRecycle.Backup]::MoveToRecycleBin($Path, $form.Handle)
        $script:recycledTestFiles.Add(@{ OriginalPath = $Path; RecycledPath = $recycled })
        return $recycled
    }
    Assert (Clear-LogWithBackup) 'Native Recycle Bin backup/clear failed'
    $receipt = $script:recycledTestFiles[0]
    Assert ([IO.Path]::GetFileName($receipt.OriginalPath) -match '^耳机操作记录_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}(_\d+)?\.txt$') 'Backup filename is not readable timestamped txt'
    Assert (-not [IO.File]::Exists($receipt.OriginalPath) -and [IO.File]::Exists($receipt.RecycledPath)) 'Backup remained beside the original instead of in the Recycle Bin'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($receipt.RecycledPath)) -eq $bytes) 'Recycled copy is not byte-identical, including BOM'
    Assert ([IO.File]::Exists($script:activeLogPath) -and [IO.File]::ReadAllBytes($script:activeLogPath).Length -eq 0 -and $script:currentRound -eq 1 -and $recordsPanel.Controls.Count -eq 0 -and $form.Enabled) 'Clear did not retain original file or reset progress'
    Assert ($configStatusLabel.Text.Contains('回收站')) 'Clear status does not tell user where the backup is'
    Invoke-NextStep
    $newLog = [IO.File]::ReadAllText($script:activeLogPath)
    Restore-TestBackup $receipt
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($receipt.OriginalPath)) -eq $bytes -and [IO.File]::ReadAllText($script:activeLogPath) -eq $newLog) 'Restore damaged backup or replaced the active log'
    # An empty log also keeps its path and produces a valid, restorable backup.
    [IO.File]::WriteAllText($script:activeLogPath, '')
    Assert (Clear-LogWithBackup) 'Empty log cannot be cleared'
    $emptyReceipt = $script:recycledTestFiles[1]
    Assert ([IO.File]::ReadAllBytes($emptyReceipt.RecycledPath).Length -eq 0) 'Empty backup gained unexpected bytes'
    Restore-TestBackup $emptyReceipt
    Write-Output 'PASS: real Windows recycling and restore, timestamped txt, exact bytes/BOM, original file retained, locked/unavailable/unverified failures, concurrent writer protection and empty log'
}
finally {
    # Restore only items created by this test; never empty the user's Recycle Bin.
    foreach ($receipt in $script:recycledTestFiles) { Restore-TestBackup $receipt }
    if ($form) { $form.Close(); $form.Dispose() }
    $env:APPDATA = $originalAppData
}
