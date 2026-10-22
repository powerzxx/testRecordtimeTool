$ErrorActionPreference = 'Stop'
$originalAppData = $env:APPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RecorderThemeTest-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$env:APPDATA = $testRoot
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Pump { [Windows.Forms.Application]::DoEvents() }
function Save-ThemePreview([string]$Name) {
    Pump
    $bitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
    try {
        $form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bitmap.Save((Join-Path $testRoot $Name))
    }
    finally { $bitmap.Dispose() }
}
try {
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RecordTime.ps1'))
    $source = $source.Replace('[System.Windows.Forms.Application]::Run($form)', '').Replace('$PSScriptRoot', "'" + $PSScriptRoot.Replace("'", "''") + "'")
    . ([scriptblock]::Create($source))
    $form.Show(); $form.Activate(); Pump
    Assert ($script:currentTheme -eq 'Classic' -and $classicThemeItem.Checked) 'Default layout should stay classic'
    foreach ($name in @('入仓关盖', '开盖', '回连', '出现关盖回连', '出现不跑log')) {
        $nameInput.Text = $name; $addButton.PerformClick()
    }
    foreach ($name in @('入仓关盖', '开盖', '回连')) { Add-StepButton -Name $name | Out-Null }
    Sync-Steps
    $script:activeLogPath = Join-Path $testRoot 'records.txt'
    [IO.File]::WriteAllText($script:activeLogPath, '')
    $fileLabel.Text = '当前文件：' + $script:activeLogPath
    Reset-StepProgress -Round 5
    Invoke-NextStep
    $originalStep = $script:pendingSteps[0]
    $originalRow = $recordsPanel.Controls[1]
    $originalUndo = $script:undoSpace
    $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:activeLogPath))
    $originalProfile = $script:activeProfile
    $classicAreaSplit.SplitterDistance = [int](($classicAreaSplit.ClientSize.Height - $classicAreaSplit.SplitterWidth) * 0.60)
    $classicRatio = $classicAreaSplit.SplitterDistance / ($classicAreaSplit.ClientSize.Height - $classicAreaSplit.SplitterWidth)
    $nameInput.Text = '尚未添加的按钮'; $nameInput.Focus() | Out-Null
    Set-LayoutTheme -Theme Workbench
    Pump
    Assert ($script:currentTheme -eq 'Workbench' -and $workbenchThemeItem.Checked -and -not $classicThemeItem.Checked) 'Workbench did not activate'
    Assert ($stepGroup.Parent -eq $workspaceSplit.Panel2 -and $recordsPanel.Parent -eq $workbenchRecords -and $addButton.Parent -eq $workbenchInput) 'Controls not moved to workbench'
    Assert ($nameInput.Text -eq '尚未添加的按钮' -and $nameInput.Focused) 'Switch discarded button input or focus'
    Assert ($recordsPanel.Controls[1] -eq $originalRow -and $script:pendingSteps[0] -eq $originalStep -and $script:currentRound -eq 5) 'Switch replaced stateful controls or reset progress'
    Assert ($script:undoSpace -eq $originalUndo -and $script:activeProfile -eq $originalProfile) 'Switch changed undo or profile'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($script:activeLogPath)) -eq $before) 'Switch wrote records'
    Assert ($mainMenu.Items.Count -eq 5 -and $themeClearConfigItem.Enabled -eq $clearConfigButton.Enabled) 'Workbench menus or enabled states incorrect'
    $themeTopmostItem.PerformClick(); Assert ($form.TopMost) 'Topmost menu not wired'
    $themeTopmostItem.PerformClick(); Assert (-not $form.TopMost) 'Topmost menu cannot turn off'
    $themeIntervalItem.PerformClick(); Assert ($intervalToggle.Checked -and $script:preferences.ShowInterval) 'Interval menu not saved'
    $themeMillisecondsItem.PerformClick(); Assert ($millisecondToggle.Checked -and $script:preferences.Milliseconds) 'Precision menu not saved'
    $realSelect = (Get-Command Select-LogFile).ScriptBlock
    Set-Item Function:Select-LogFile -Value { param($Mode) $script:testSelectedMode = $Mode }
    try {
        $themeOpenFileItem.PerformClick(); Assert ($script:testSelectedMode -eq 'Open') 'Hidden original open button broke menu routing'
        $themeNewFileItem.PerformClick(); Assert ($script:testSelectedMode -eq 'New') 'New file menu routing incorrect'
    }
    finally { Set-Item Function:Select-LogFile -Value $realSelect }
    $workbenchAreaSplit.SplitterDistance = 210
    $workspaceSplit.SplitterDistance = [int](($workspaceSplit.ClientSize.Width - $workspaceSplit.SplitterWidth) * 0.70)
    $workbenchRatio = $workbenchAreaSplit.SplitterDistance / ($workbenchAreaSplit.ClientSize.Height - $workbenchAreaSplit.SplitterWidth)
    $widthRatio = $workspaceSplit.SplitterDistance / ($workspaceSplit.ClientSize.Width - $workspaceSplit.SplitterWidth)
    Set-LayoutTheme -Theme Classic
    Pump
    Assert ($areaSplit -eq $classicAreaSplit -and $stepGroup.Parent -eq $layout -and $nameInput.Parent -eq $buttonToolbar -and $mainMenu.Items.Count -eq 2) 'Classic placement not restored'
    Assert ([Math]::Abs($script:splitRatio - $classicRatio) -lt 0.005) 'Classic splitter overwritten by workbench'
    Assert ($intervalToggle.Visible -and $intervalToggle.Checked -and $millisecondToggle.Checked) 'Settings not shared with classic layout'
    $originalRow.Controls['EditRecordButton'].Visible = $true
    $originalRow.Controls['EditRecordButton'].PerformClick()
    $editor = $originalRow.Controls['RecordEditInput']
    $editor.Text = '12:34:56 尚未保存的编辑'; $editor.Focus() | Out-Null
    $editor.Select(9, 3)
    Set-LayoutTheme -Theme Workbench
    Pump
    Assert ($editor.Text -eq '12:34:56 尚未保存的编辑' -and $editor.Focused -and $originalRow.AccessibleDescription -eq 'Editing') 'Switch discarded editing draft or focus'
    Assert ($editor.SelectionStart -eq 9 -and $editor.SelectionLength -eq 3) 'Switch changed editor selection'
    Assert ([Math]::Abs($script:splitRatio - $workbenchRatio) -lt 0.005 -and [Math]::Abs($script:workspaceRatio - $widthRatio) -lt 0.005) 'Workbench splitter positions not retained'
    Set-LayoutTheme -Theme Classic
    $originalRow.Controls['CancelRecordEditButton'].PerformClick()
    Assert (Undo-LastSpaceRecord) 'Theme switch invalidated space undo'
    Assert ($script:currentRound -eq 5 -and $script:pendingSteps[0].Tag -eq '入仓关盖' -and [IO.File]::ReadAllBytes($script:activeLogPath).Length -eq 0) 'Undo after theme switch restored wrong state'
    $realPrefs = $script:preferencesPath
    $script:preferencesPath = $testRoot
    $failed = $false
    try { Set-LayoutTheme -Theme Workbench }
    catch { $failed = $true }
    finally { $script:preferencesPath = $realPrefs }
    Assert ($failed -and $script:currentTheme -eq 'Classic' -and $script:preferences.LayoutTheme -eq 'Classic' -and $classicThemeItem.Checked) 'Failed preference write partially changed theme'
    Set-LayoutTheme -Theme Workbench
    $nameInput.Text = '新加入的操作'; $addButton.PerformClick()
    Add-StepButton -Name '新加入的操作' | Out-Null
    Sync-Steps
    Assert ($stepPanel.Controls[-1].Width -gt 200 -and $actionPanel.Controls[-1].FlatStyle -eq 'Flat') 'New buttons do not follow active theme'
    Set-LayoutTheme -Theme Classic
    Assert ($stepPanel.Controls[-1].AutoSize -and $stepPanel.Controls[-1].FlatStyle -eq 'Standard') 'New buttons cannot return to classic style'
    $nameInput.Text = ''; $form.ActiveControl = $null
    Save-ThemePreview 'classic.png'
    Set-LayoutTheme -Theme Workbench
    foreach ($size in @((New-Object Drawing.Size(1040, 720)), (New-Object Drawing.Size(1400, 940)))) {
        $form.Size = $size; Apply-SavedSplitter; Pump
        Assert ($addButton.Right -le $workbenchInput.ClientSize.Width -and $nameInput.Right -le $workbenchInput.ClientSize.Width) 'Workbench add controls clipped'
        Assert ($profileCombo.Right -le $profileBar.ClientSize.Width -and $saveProfile.Right -le $profileBar.ClientSize.Width) 'Workbench profile controls clipped'
        Assert ($stepPanel.Width -ge 240 -and $recordsPanel.Width -gt 500 -and $recordsPanel.Height -gt 100) 'Workbench working area collapsed'
        Assert ($fileLabel.Width -gt 400 -and $fileLabel.Right -le $workbenchRecords.ClientSize.Width) 'Current file label collapsed or clipped'
        Assert (-not $profileBar.HorizontalScroll.Visible) 'Profile toolbar has an unexpected horizontal scrollbar'
        Assert (-not $recordsPanel.HorizontalScroll.Visible -and -not $stepPanel.HorizontalScroll.Visible) 'Switch or resize left stale horizontal scrollbar'
    }
    $form.Size = New-Object Drawing.Size(1160, 840)
    Apply-SavedSplitter
    Invoke-NextStep
    Save-ThemePreview 'workbench.png'
    Save-WindowLayout
    $savedLayout = Get-Content $script:windowLayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($savedLayout.Themes.Classic.SplitRatio -gt 0 -and $savedLayout.Themes.Workbench.WorkspaceRatio -gt 0) 'Per-theme splitter settings not persisted'
    $reload = @'
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText('__ROOT__/RecordTime.ps1').Replace('$PSScriptRoot', "'__ROOT__'").Replace('[System.Windows.Forms.Application]::Run($form)', '')
. ([scriptblock]::Create($source))
$form.Show()
[Windows.Forms.Application]::DoEvents()
if ($script:currentTheme -ne 'Workbench' -or -not $workbenchThemeItem.Checked -or $stepGroup.Parent -ne $workspaceSplit.Panel2 -or $stepPanel.Controls.Count -ne 4 -or -not $themeMillisecondsItem.Checked -or $script:themeSplitters.Classic.SplitRatio -lt 0.5) { throw 'Theme startup restore failed' }
[Windows.Forms.Application]::RemoveMessageFilter($spaceFilter)
$form.Close(); $form.Dispose()
'@
    $reload = $reload.Replace('__ROOT__', $PSScriptRoot.Replace("'", "''"))
    $reloadPath = Join-Path $testRoot 'reload.ps1'
    [IO.File]::WriteAllText($reloadPath, $reload, (New-Object Text.UTF8Encoding($true)))
    & powershell -NoProfile -STA -ExecutionPolicy Bypass -File $reloadPath
    Assert ($LASTEXITCODE -eq 0) 'New process did not restore theme and per-layout settings'
    Write-Output 'PASS: live layout switch preserves rounds, control identity, file bytes, undo, input and editing drafts; menu actions, shared settings, failure handling, responsive layout and restart persistence'
    Write-Output ('Previews: ' + $testRoot)
}
finally {
    if ($form) { $form.Close(); $form.Dispose() }
    $env:APPDATA = $originalAppData
}
