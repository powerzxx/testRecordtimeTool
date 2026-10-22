$ErrorActionPreference = 'Stop'
$originalAppData = $env:APPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RecorderWorkflowTest-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$env:APPDATA = $testRoot
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RecordTime.ps1'))
    $source = $source.Replace('[System.Windows.Forms.Application]::Run($form)', '')
    $source = $source.Replace('$PSScriptRoot', "'" + $PSScriptRoot.Replace("'", "''") + "'")
    . ([scriptblock]::Create($source))
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    $script:activeLogPath = Join-Path $testRoot 'rounds.txt'
    [IO.File]::WriteAllText($script:activeLogPath, '')
    $fileLabel.Text = $script:activeLogPath
    foreach ($name in @('A', 'B')) {
        $nameInput.Text = $name
        $addButton.PerformClick()
        Add-StepButton -Name $name | Out-Null
    }
    Sync-Steps
    Reset-StepProgress
    Assert ($stepStatus.Text -match '下一步：A') 'Next step name missing'
    Invoke-NextStep
    $lines = [IO.File]::ReadAllLines($script:activeLogPath)
    Assert ($lines.Count -eq 2 -and $lines[0] -eq '--- 第 1 轮 ---' -and $lines[1] -match ' A$') 'Round header or first record missing'
    Assert ($null -ne $script:undoSpace) 'Space undo not available'
    $editingRow = $recordsPanel.Controls[1]
    $editingRow.AccessibleDescription = 'Editing'
    Assert (-not (Undo-LastSpaceRecord) -and $null -ne $script:undoSpace) 'Undo should not discard a live editing draft'
    $editingRow.AccessibleDescription = ''
    Assert (Undo-LastSpaceRecord) 'Undo first record failed'
    Assert ([IO.File]::ReadAllBytes($script:activeLogPath).Length -eq 0 -and $script:currentRound -eq 1 -and $script:pendingSteps[0].Tag -eq 'A') 'Undo must remove first header and restore cursor'
    Invoke-NextStep
    $before = [IO.File]::ReadAllText($script:activeLogPath)
    Invoke-NextStep
    Assert ($script:currentRound -eq 2) 'Round did not advance'
    Assert (Undo-LastSpaceRecord) 'Undo across round boundary failed'
    Assert ($script:currentRound -eq 1 -and $script:pendingSteps[0].Tag -eq 'B' -and [IO.File]::ReadAllText($script:activeLogPath) -eq $before) 'Undo did not restore exact previous state'
    Invoke-NextStep
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WorkflowTestKeyboard {
 [DllImport("user32.dll")] public static extern bool GetKeyboardState(byte[] state);
 [DllImport("user32.dll")] public static extern bool SetKeyboardState(byte[] state);
}
'@
    $keyboardState = New-Object byte[] 256
    [WorkflowTestKeyboard]::GetKeyboardState($keyboardState) | Out-Null
    try {
        $ctrl = [byte[]]$keyboardState.Clone()
        $ctrl[17] = 128
        [WorkflowTestKeyboard]::SetKeyboardState($ctrl) | Out-Null
        $key = [Windows.Forms.Message]::Create($form.Handle, 0x100, [intptr]90, [intptr]0)
        Assert ($spaceFilter.PreFilterMessage([ref]$key)) 'Ctrl+Z not routed to undo'
        Assert ($script:currentRound -eq 1 -and $script:pendingSteps[0].Tag -eq 'B') 'Ctrl+Z did not undo boundary record'
        $key = [Windows.Forms.Message]::Create($nameInput.Handle, 0x100, [intptr]90, [intptr]0)
        Assert (-not $spaceFilter.PreFilterMessage([ref]$key)) 'Ctrl+Z in text input should remain native text undo'
    }
    finally { [WorkflowTestKeyboard]::SetKeyboardState($keyboardState) | Out-Null }
    Invoke-NextStep
    Invoke-NextStep
    $lines = [IO.File]::ReadAllLines($script:activeLogPath)
    Assert (@($lines | Where-Object { $_ -match '^--- 第' }).Count -eq 2) 'Round headers duplicated or missing'
    $redoRoundButton.PerformClick()
    Invoke-NextStep
    $lines = [IO.File]::ReadAllLines($script:activeLogPath)
    Assert (@($lines | Where-Object { $_ -match '^--- 第' }).Count -eq 2) 'Redo created unwanted marker'
    Assert (@($lines | Where-Object { $_ -match '重做|跳过|未完成' }).Count -eq 0) 'Excluded redo/skip markers added'
    [IO.File]::AppendAllText($script:activeLogPath, "external edit`r`n")
    Assert (-not (Undo-LastSpaceRecord)) 'Undo overwrote external changes'
    Assert ([IO.File]::ReadAllText($script:activeLogPath).Contains('external edit')) 'External edit lost'

    $script:activeLogPath = Join-Path $testRoot 'intervals.txt'
    $script:lastLoggedRound = $null
    Reset-StepProgress
    $intervalToggle.Checked = $true
    $millisecondToggle.Checked = $true
    $time = [datetime]::ParseExact('2026-10-21 10:00:00.100', 'yyyy-MM-dd HH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture)
    Assert (Write-ActionRecord -Name 'A' -Timestamp $time) 'Millisecond record failed'
    Assert (Write-ActionRecord -Name 'B' -Timestamp $time.AddMilliseconds(1250)) 'Interval record failed'
    $lines = [IO.File]::ReadAllLines($script:activeLogPath)
    Assert ($lines[-1] -match '^10:00:01\.350 B' -and $lines[-1].Contains('1.250')) 'Wrong precision or elapsed time'
    $current = $script:pendingSteps[0]
    $round = $script:currentRound
    $lastTime = $script:lastStepTimestamp
    $f8 = [Windows.Forms.Message]::Create($form.Handle, 0x100, [intptr]119, [intptr]0)
    Assert ($spaceFilter.PreFilterMessage([ref]$f8)) 'F8 not handled'
    Assert ($script:pendingSteps[0] -eq $current -and $script:currentRound -eq $round -and $script:lastStepTimestamp -eq $lastTime) 'Exception changed sequence or interval baseline'
    $lines = [IO.File]::ReadAllLines($script:activeLogPath)
    Assert ($lines[-1] -match '\[异常\]') 'Exception not saved immediately'
    $repeat = [Windows.Forms.Message]::Create($form.Handle, 0x100, [intptr]119, [intptr]0x40000000)
    $spaceFilter.PreFilterMessage([ref]$repeat) | Out-Null
    Assert ([IO.File]::ReadAllLines($script:activeLogPath).Count -eq $lines.Count) 'F8 repeated on hold'
    $row = $recordsPanel.Controls[$recordsPanel.Controls.Count - 1]
    # Refresh rows because this test switched files without a file dialog.
    Load-LogRows -Lines $lines
    $row = $recordsPanel.Controls[$recordsPanel.Controls.Count - 1]
    Assert (Save-EditedRecord -Row $row -Text '10:00:02.123 [异常] 断连') 'Millisecond exception edit failed'
    Assert ([IO.File]::ReadAllLines($script:activeLogPath)[-1] -eq '10:00:02.123 [异常] 断连') 'Exception explanation not saved'

    Save-ProfileAs -Name 'Connection'
    $nameInput.Text = 'C'
    $addButton.PerformClick()
    Add-StepButton -Name 'C' | Out-Null
    Sync-Steps
    $beforeSwitch = [IO.File]::ReadAllText($script:activeLogPath)
    Switch-TestProfile -Name '默认方案'
    Assert (($script:buttonNames -join ',') -eq 'A,B' -and ($script:stepNames -join ',') -eq 'A,B') 'Original profile was overwritten'
    Switch-TestProfile -Name 'Connection'
    Assert (($script:buttonNames -join ',') -eq 'A,B,C' -and ($script:stepNames -join ',') -eq 'A,B,C') 'Profile switch lost settings'
    Assert ($script:currentRound -eq 1 -and [IO.File]::ReadAllText($script:activeLogPath) -eq $beforeSwitch) 'Profile switch modified records'
    $saved = Get-Content $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($saved.ActiveProfile -eq 'Connection' -and $saved.Profiles.Connection.Steps.Count -eq 3) 'Profiles not persisted'
    $realSettingsPath = $script:settingsPath
    $script:settingsPath = $testRoot # An existing directory cannot be replaced as a settings file.
    $failed = $false
    try { Switch-TestProfile -Name '默认方案' }
    catch { $failed = $true }
    finally { $script:settingsPath = $realSettingsPath }
    Assert ($failed -and $script:activeProfile -eq 'Connection' -and $script:buttonNames.Count -eq 3) 'Failed profile save changed active configuration'

    $script:preferences.LastDirectory = $testRoot
    Save-WorkflowPreferences
    $savedPrefs = Get-Content $script:preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($savedPrefs.LastDirectory -eq $testRoot -and $savedPrefs.Milliseconds -and $savedPrefs.ShowInterval) 'Preferences or last directory not saved'
    $nameInput.Focus() | Out-Null
    Update-WorkflowStatus
    Assert ($workflowStatus.Text -match '正在输入按钮名称') 'Typing status missing'
    $form.ActiveControl = $null
    $form.Focus() | Out-Null
    Update-WorkflowStatus
    Assert ($workflowStatus.Text -match '可按空格测试' -and $openCurrentButton.Enabled -and $openFolderButton.Enabled) 'Ready/file controls missing'
    $path = $script:activeLogPath
    $script:activeLogPath = $null
    Update-WorkflowStatus
    Assert ($workflowStatus.Text -match '尚未选择记录文件' -and -not $openCurrentButton.Enabled) 'No-file status missing'
    $script:activeLogPath = $path
    Assert ((Get-CurrentLogOpenTarget) -eq $path -and (Get-CurrentLogOpenTarget -Folder) -eq $testRoot) 'File/folder open target incorrect'

    # Exercise backup/clear with a private recycle destination. The separate
    # Test-RecycleBackup script checks the real Windows Recycle Bin and restore.
    $script:testRecycleDirectory = Join-Path $testRoot 'recycled'
    [IO.Directory]::CreateDirectory($script:testRecycleDirectory) | Out-Null
    Set-Item Function:Move-RecordBackupToRecycleBin -Value {
        param([string]$Path)
        $destination = Join-Path $script:testRecycleDirectory ([IO.Path]::GetFileName($Path))
        [IO.File]::Move($Path, $destination)
        return $destination
    }
    $clearCode = (Get-Command Clear-LogWithBackup).ScriptBlock.ToString()
    $clearCode = [regex]::Replace($clearCode, "\[Windows.Forms.MessageBox\]::Show\([^\r\n]+?\)", '$script:testClearAnswer')
    Set-Item Function:Clear-LogWithBackup -Value ([scriptblock]::Create($clearCode))
    $script:testClearAnswer = 'No'
    $bytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
    Assert (-not (Clear-LogWithBackup) -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -eq $bytes) 'Cancelled clear changed records'
    $script:testClearAnswer = 'Yes'
    $lockedFile = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $failed = $false
    try { Clear-LogWithBackup | Out-Null }
    catch { $failed = $true }
    finally { $lockedFile.Dispose() }
    Assert ($failed -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -eq $bytes) 'Backup failure must leave source intact'
    Assert (Clear-LogWithBackup) 'Confirmed clear failed'
    $backups = @(Get-ChildItem -LiteralPath $script:testRecycleDirectory -Filter '*.txt')
    Assert ($backups.Count -eq 1 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($backups[0].FullName)) -eq $bytes) 'Backup not byte-identical'
    Assert ([IO.File]::ReadAllText($path) -eq '' -and $recordsPanel.Controls.Count -eq 0 -and $script:currentRound -eq 1) 'Clear did not reset file and progress'

    # Minimum dimensions keep the new toolbar and the sequence controls usable.
    $form.Size = $form.MinimumSize
    $areaSplit.SplitterDistance = $areaSplit.Panel1MinSize
    [Windows.Forms.Application]::DoEvents()
    Assert ($stepPanel.Height -gt 40 -and $actionPanel.Height -gt 40 -and $recordsPanel.Height -gt 100) 'Minimum layout collapsed a working area'
    Assert ($profileCombo.Bounds.Right -le $profileCombo.Parent.ClientSize.Width -and $openFolderButton.Bounds.Right -le $openFolderButton.Parent.ClientSize.Width) 'Workflow toolbar clipped at minimum width'
    Assert ($userGuideMenuItem.Visible -and $userGuideMenuItem.Bounds.Right -le $mainMenu.ClientSize.Width) 'User guide menu clipped at minimum width'
    Assert ($form.MainMenuStrip -eq $mainMenu -and $mainLayout.Top -ge $mainMenu.Bottom) 'Top menu overlaps the main layout'
    Assert ($openFolderButton.Parent.Controls.Count -eq 2 -and $mainLayout.RowCount -eq 2) 'Old guide button, shortcut buttons or hint row still present'
    $form.Size = New-Object Drawing.Size(1160, 840)
    $areaSplit.SplitterDistance = 400
    $fileLabel.Text = '当前文件：' + $path
    $nameInput.Text = ''
    $form.ActiveControl = $null
    $form.Focus() | Out-Null
    Invoke-NextStep
    Add-ExceptionRecord
    Update-WorkflowStatus
    $beforeGuide = [IO.File]::ReadAllText($path)
    $roundBeforeGuide = $script:currentRound
    $nextBeforeGuide = $script:pendingSteps[0]
    $guide = New-UserGuideDialog
    try {
        $guide.Show($form)
        [Windows.Forms.Application]::DoEvents()
        $topics = $guide.Controls.Find('GuideTopics', $true)[0]
        $content = $guide.Controls.Find('GuideContent', $true)[0]
        Assert ($topics.Items.Count -eq 8 -and $content.ReadOnly -and $content.Text.Contains('快速开始')) 'Guide failed to load'
        $topics.SelectedIndex = 4
        Assert ($content.Text.Contains('F8') -and $content.Text.Contains('Ctrl+Z')) 'Guide topic navigation failed'
        foreach ($keyCode in @(32, 119)) {
            $key = [Windows.Forms.Message]::Create($content.Handle, 0x100, [intptr]$keyCode, [intptr]0)
            Assert (-not $spaceFilter.PreFilterMessage([ref]$key)) 'Guide key unexpectedly triggered main window shortcut'
        }
        Assert ($guide.CancelButton.DialogResult -eq 'Cancel') 'Guide cannot close with Escape'
        $guide.Size = $guide.MinimumSize
        [Windows.Forms.Application]::DoEvents()
        Assert ($content.Width -gt 300 -and $content.Height -gt 250 -and $guide.CancelButton.Bottom -le $guide.CancelButton.Parent.ClientSize.Height) 'Guide minimum layout clipped'
        $guide.ClientSize = New-Object Drawing.Size(820, 560)
        $bitmap = New-Object Drawing.Bitmap($guide.Width, $guide.Height)
        $guide.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $guide.Width, $guide.Height)))
        $bitmap.Save((Join-Path $testRoot 'guide-preview.png'))
        $bitmap.Dispose()
    }
    finally { $guide.Close(); $guide.Dispose() }
    Assert ([IO.File]::ReadAllText($path) -eq $beforeGuide -and $script:currentRound -eq $roundBeforeGuide -and $script:pendingSteps[0] -eq $nextBeforeGuide) 'Guide changed records or progress'
    $bitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bitmap.Save((Join-Path $testRoot 'workflow-preview.png'))
    $bitmap.Dispose()

    # A fresh PowerShell process must restore both named profiles and preferences.
    $startupScript = Join-Path $testRoot 'reload.ps1'
    $reload = @'
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText('__ROOT__/RecordTime.ps1').Replace('$PSScriptRoot', "'__ROOT__'").Replace('[System.Windows.Forms.Application]::Run($form)', '')
. ([scriptblock]::Create($source))
if ($script:activeProfile -ne 'Connection' -or $script:buttonNames.Count -ne 3 -or -not $script:preferences.Milliseconds -or $script:preferences.LastDirectory -ne '__TEMP__') { throw 'Startup restore failed' }
[Windows.Forms.Application]::RemoveMessageFilter($spaceFilter)
$form.Dispose()
'@
    $reload = $reload.Replace('__ROOT__', $PSScriptRoot.Replace("'", "''")).Replace('__TEMP__', $testRoot.Replace("'", "''"))
    [IO.File]::WriteAllText($startupScript, $reload, (New-Object Text.UTF8Encoding($true)))
    & powershell -NoProfile -STA -ExecutionPolicy Bypass -File $startupScript
    Assert ($LASTEXITCODE -eq 0) 'New process did not restore workflow settings'
    Write-Output 'PASS: round markers, undo first/cross-round/external edits, exception shortcut/editing, millisecond intervals, profiles, preferences, status and clear backup'
    Write-Output ('Preview: ' + (Join-Path $testRoot 'workflow-preview.png'))
    Write-Output ('Guide preview: ' + (Join-Path $testRoot 'guide-preview.png'))
}
finally {
    if ($form) { $form.Close(); $form.Dispose() }
    $env:APPDATA = $originalAppData
}
