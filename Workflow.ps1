$script:undoSpace = $null
$script:lastStepTimestamp = $null
$script:lastLoggedRound = $null
$script:preferencesPath = Join-Path $script:settingsDirectory 'preferences.json'
$script:preferences = @{ Milliseconds = $false; ShowInterval = $false; LastDirectory = ''; LayoutTheme = 'Classic' }
$script:activeProfile = '默认方案'
$script:profiles = @{}
if ($savedNames -and $savedNames.PSObject.Properties.Name -contains 'Profiles') {
    foreach ($property in $savedNames.Profiles.PSObject.Properties) {
        $buttons = @($property.Value.Buttons | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) })
        $steps = @($property.Value.Steps | Where-Object { $_ -is [string] -and $_ -in $buttons })
        $script:profiles[$property.Name] = @{ Buttons = $buttons; Steps = $steps }
    }
    if ($script:profiles.ContainsKey([string]$savedNames.ActiveProfile)) {
        $script:activeProfile = [string]$savedNames.ActiveProfile
    }
}
$script:profiles[$script:activeProfile] = @{ Buttons = @($script:buttonNames); Steps = @($script:stepNames) }
if (Test-Path -LiteralPath $script:preferencesPath) {
    try {
        $savedPreferences = Get-Content -LiteralPath $script:preferencesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:preferences.Milliseconds = $savedPreferences.Milliseconds -eq $true
        $script:preferences.ShowInterval = $savedPreferences.ShowInterval -eq $true
        $script:preferences.LastDirectory = [string]$savedPreferences.LastDirectory
        if ($savedPreferences.LayoutTheme -in @('Classic', 'Workbench')) { $script:preferences.LayoutTheme = [string]$savedPreferences.LayoutTheme }
    }
    catch { $configStatusLabel.Text = '偏好设置读取失败，使用默认设置' }
}

function Save-WorkflowPreferences {
    Write-RecorderSettings -Path $script:preferencesPath -Json ($script:preferences | ConvertTo-Json)
}

function Get-ButtonConfiguration {
    $profiles = @{}
    foreach ($key in $script:profiles.Keys) { $profiles[$key] = $script:profiles[$key] }
    $profiles[$script:activeProfile] = @{ Buttons = @($script:buttonNames); Steps = @($script:stepNames) }
    return @{ Version = 3; Buttons = @($script:buttonNames); Steps = @($script:stepNames); ActiveProfile = $script:activeProfile; Profiles = $profiles }
}

function Refresh-ProfileList {
    $profileCombo.Items.Clear()
    foreach ($name in @($script:profiles.Keys | Sort-Object)) { $profileCombo.Items.Add($name) | Out-Null }
    $profileCombo.SelectedItem = $script:activeProfile
}

function Save-ProfileAs {
    param([string]$Name)
    $Name = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    if ($script:profiles.ContainsKey($Name) -and $Name -ne $script:activeProfile) {
        if ([Windows.Forms.MessageBox]::Show($form, ('覆盖方案【' + $Name + '】吗？'), '保存方案', 'YesNo', 'Question') -ne 'Yes') { return }
    }
    # Persist the old active profile before creating a new one.
    Save-ButtonConfig
    $previousName = $script:activeProfile
    try {
        $script:activeProfile = $Name
        Save-ButtonConfig
    }
    catch { $script:activeProfile = $previousName; throw }
    Refresh-ProfileList
}

function Switch-TestProfile {
    param([string]$Name)
    if ($Name -eq $script:activeProfile -or -not $script:profiles.ContainsKey($Name)) { return }
    Save-ButtonConfig
    $oldName = $script:activeProfile
    $oldButtons = @($script:buttonNames)
    $oldSteps = @($script:stepNames)
    try {
        $script:buttonNames = @($script:profiles[$Name].Buttons)
        $script:stepNames = @($script:profiles[$Name].Steps)
        $script:activeProfile = $Name
        Save-ButtonConfig
    }
    catch {
        $script:activeProfile = $oldName
        $script:buttonNames = $oldButtons
        $script:stepNames = $oldSteps
        Refresh-ProfileList
        throw
    }
    while ($stepPanel.Controls.Count -gt 0) { $stepPanel.Controls[0].Dispose() }
    while ($actionPanel.Controls.Count -gt 0) { $actionPanel.Controls[0].Dispose() }
    foreach ($name in $script:buttonNames) { Add-ActionButton -Name $name }
    foreach ($name in $script:stepNames) { Add-StepButton -Name $name | Out-Null }
    Reset-StepProgress
    $clearConfigButton.Enabled = $script:buttonNames.Count -gt 0
    Refresh-ProfileList
    $form.ActiveControl = $null
    $form.Focus() | Out-Null
    $configStatusLabel.Text = '已切换方案：' + $Name
}

function Clear-UndoSpace {
    $script:undoSpace = $null
}

function Get-SequenceSnapshot {
    return @{
        Round = $script:currentRound; Pending = @($script:pendingSteps)
        Completed = @($script:completedSteps); Started = $script:roundStarted
        Order = @($script:stepOrder); LastTimestamp = $script:lastStepTimestamp
        LastRound = $script:lastLoggedRound
    }
}

function Undo-LastSpaceRecord {
    if ($null -eq $script:undoSpace) { return $false }
    if (@($recordsPanel.Controls | Where-Object { $_.AccessibleDescription -eq 'Editing' }).Count -gt 0) {
        $configStatusLabel.Text = '请先保存或取消正在编辑的记录，再撤销空格'
        return $false
    }
    $undo = $script:undoSpace
    if ($script:activeLogPath -ne $undo.Path -or
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($undo.Path)) -ne $undo.Expected) {
        Clear-UndoSpace
        $configStatusLabel.Text = '记录文件已变化，未撤销；请重新检查记录'
        return $false
    }
    [IO.File]::WriteAllBytes($undo.Path, $undo.Before)
    $state = $undo.State
    $script:currentRound = $state.Round
    $script:pendingSteps = @($state.Pending)
    $script:completedSteps = @($state.Completed)
    $script:roundStarted = $state.Started
    $script:stepOrder = @($state.Order)
    $script:lastStepTimestamp = $state.LastTimestamp
    $script:lastLoggedRound = $state.LastRound
    Clear-UndoSpace
    Clear-UndoDelete
    Load-LogRows -Lines ([IO.File]::ReadAllLines($undo.Path, [Text.Encoding]::UTF8))
    Update-StepDisplay
    $configStatusLabel.Text = '已撤销上一次空格记录，轮次和步骤已恢复'
    return $true
}

function Write-WorkflowRecord {
    param([string]$Name, [datetime]$Timestamp, [int]$RoundNumber, [hashtable]$Snapshot, [switch]$Exception)
    if ([string]::IsNullOrWhiteSpace($script:activeLogPath)) { return $false }
    try {
        $before = [byte[]]@(if ([IO.File]::Exists($script:activeLogPath)) { [IO.File]::ReadAllBytes($script:activeLogPath) })
        $oldText = if ($before.Length -gt 0) { [IO.File]::ReadAllText($script:activeLogPath, [Text.Encoding]::UTF8) } else { '' }
        $format = if ($script:preferences.Milliseconds) { 'HH:mm:ss.fff' } else { 'HH:mm:ss' }
        $entry = '{0} {1}' -f $Timestamp.ToString($format), $Name
        if (-not $Exception -and $script:preferences.ShowInterval -and $null -ne $script:lastStepTimestamp) {
            $seconds = ($Timestamp - $script:lastStepTimestamp).TotalSeconds
            $interval = if ($seconds -lt 0) { '系统时间已回拨' } else { '{0:0.000} 秒' -f $seconds }
            $entry += ' [距上一步 ' + $interval + ']'
        }
        $lines = @()
        if ($script:lastLoggedRound -ne $RoundNumber) { $lines += '--- 第 {0} 轮 ---' -f $RoundNumber }
        $lines += $entry
        $prefix = if ($oldText.Length -gt 0 -and -not $oldText.EndsWith("`n")) { [Environment]::NewLine } else { '' }
        $append = $prefix + ($lines -join [Environment]::NewLine) + [Environment]::NewLine
        [IO.File]::AppendAllText($script:activeLogPath, $append, (New-Object Text.UTF8Encoding($false)))
        Clear-UndoDelete
        Clear-UndoSpace
        if ($null -ne $Snapshot) {
            $script:undoSpace = @{
                Path = $script:activeLogPath; Before = [byte[]]$before; State = $Snapshot
                Expected = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:activeLogPath))
            }
        }
        $script:lastLoggedRound = $RoundNumber
        if (-not $Exception) { $script:lastStepTimestamp = $Timestamp }
        foreach ($row in $recordsPanel.Controls) {
            $row.BackColor = [Drawing.Color]::White
            $row.Controls['RecordText'].BackColor = [Drawing.Color]::White
        }
        foreach ($line in $lines) { Add-LogRow -Text $line -Highlight ($line -eq $entry) }
        if ($soundToggle.Checked) { [System.Media.SystemSounds]::Beep.Play() }
        return $true
    }
    catch {
        [Windows.Forms.MessageBox]::Show($form, "写入记录失败：$($_.Exception.Message)", '记录失败', 'OK', 'Error') | Out-Null
        return $false
    }
}

function Add-ExceptionRecord {
    if ([string]::IsNullOrWhiteSpace($script:activeLogPath)) {
        $configStatusLabel.Text = '请先打开或新建记录文件'
        return
    }
    if (Write-WorkflowRecord -Name '[异常] 待补充说明' -Timestamp (Get-Date) -RoundNumber $script:currentRound -Exception) {
        $configStatusLabel.Text = '异常时间已记录；稍后可在该行点击【编辑】补充说明'
    }
}

function Clear-LogWithBackup {
    if ([string]::IsNullOrWhiteSpace($script:activeLogPath)) { return $false }
    if ([Windows.Forms.MessageBox]::Show($form, '确定清空当前记录吗？清空前会生成带时间的 .txt 备份并送入回收站，可在回收站中右键还原。', '清空记录', 'YesNo', 'Warning') -ne 'Yes') { return $false }
    $wasEnabled = $form.Enabled
    $source = $null
    try {
        $form.Enabled = $false
        $path = [IO.Path]::GetFullPath($script:activeLogPath)
        # Keep the source locked against writes until its recycled copy is verified.
        $source = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
        $backup = New-RecordBackupInRecycleBin -Source $source -OriginalPath $path
        $source.SetLength(0)
        $source.Flush($true)
    }
    finally {
        if ($source) { $source.Dispose() }
        $form.Enabled = $wasEnabled
    }
    Clear-UndoDelete
    Clear-UndoSpace
    $script:lastLoggedRound = $null
    Load-LogRows -Lines @()
    Reset-StepProgress
    $configStatusLabel.Text = '记录已清空，备份已放入回收站：' + $backup.Name
    $inputHint.SetToolTip($configStatusLabel, ('在回收站中找到“' + $backup.Name + '”，右键还原。原位置：' + [IO.Path]::GetDirectoryName($backup.OriginalPath)))
    return $true
}

function Open-CurrentLogLocation {
    param([switch]$Folder)
    if ([string]::IsNullOrWhiteSpace($script:activeLogPath)) { return }
    $target = Get-CurrentLogOpenTarget -Folder:$Folder
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $target
    $start.UseShellExecute = $true
    Open-RecorderExternalWindow -StartInfo $start
}

function Get-CurrentLogOpenTarget {
    param([switch]$Folder)
    $target = if ($Folder) { [IO.Path]::GetDirectoryName($script:activeLogPath) } else { $script:activeLogPath }
    if (-not (Test-Path -LiteralPath $target)) { throw '文件或目录已不存在' }
    return $target
}

function Update-WorkflowStatus {
    if (-not $workflowStatus) { return }
    $hasFile = -not [string]::IsNullOrWhiteSpace($script:activeLogPath)
    $openCurrentButton.Enabled = $hasFile
    $openFolderButton.Enabled = $hasFile
    $clearRecordsButton.Enabled = $hasFile
    $focus = $form.ActiveControl
    while ($focus -is [Windows.Forms.ContainerControl] -and $focus.ActiveControl) { $focus = $focus.ActiveControl }
    $workflowStatus.Text = if ($nameInput.Focused) { '正在输入按钮名称' }
        elseif ($focus -is [Windows.Forms.TextBoxBase]) { '正在编辑记录' }
        elseif (-not $hasFile) { '尚未选择记录文件' }
        elseif ($profileCombo.Focused) { '正在选择测试方案' }
        elseif ($stepPanel.Controls.Count -eq 0) { '尚无测试步骤' }
        else { '可按空格测试' }
}

function Initialize-Workflow {
    $toolbar.RowCount = 4
    $toolbar.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 38))) | Out-Null
    $toolbar.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 38))) | Out-Null
    $layout.RowStyles[0].Height = 164
    $areaSplit.Panel1MinSize = 300
    $form.MinimumSize = New-Object Drawing.Size(1040, 720)
    $form.Size = New-Object Drawing.Size(1160, 840)

    $script:profileBar = New-Object Windows.Forms.FlowLayoutPanel
    $profileBar.Dock = 'Fill'; $profileBar.WrapContents = $false; $profileBar.AutoScroll = $true
    $profileBar.Margin = New-Object Windows.Forms.Padding(0)
    $label = New-Object Windows.Forms.Label
    $label.Text = '测试方案'; $label.AutoSize = $true; $label.Margin = New-Object Windows.Forms.Padding(0, 8, 6, 0)
    $script:profileCombo = New-Object Windows.Forms.ComboBox
    $profileCombo.DropDownStyle = 'DropDownList'; $profileCombo.Width = 150
    $script:saveProfile = New-Object Windows.Forms.Button
    $saveProfile.Text = '另存方案'; $saveProfile.AutoSize = $true
    $script:intervalToggle = New-Object Windows.Forms.CheckBox
    $intervalToggle.Text = '记录间隔'; $intervalToggle.AutoSize = $true; $intervalToggle.Checked = $script:preferences.ShowInterval
    $script:millisecondToggle = New-Object Windows.Forms.CheckBox
    $millisecondToggle.Text = '毫秒时间'; $millisecondToggle.AutoSize = $true; $millisecondToggle.Checked = $script:preferences.Milliseconds
    $profileBar.Controls.AddRange(@($label, $profileCombo, $saveProfile, $intervalToggle, $millisecondToggle))
    $toolbar.Controls.Add($profileBar, 0, 2)

    $quickBar = New-Object Windows.Forms.FlowLayoutPanel
    $quickBar.Dock = 'Fill'; $quickBar.WrapContents = $false; $quickBar.AutoScroll = $true
    $quickBar.Margin = New-Object Windows.Forms.Padding(0)
    $script:openCurrentButton = New-Object Windows.Forms.Button
    $openCurrentButton.Text = '查看当前文件'; $openCurrentButton.AutoSize = $true
    $script:openFolderButton = New-Object Windows.Forms.Button
    $openFolderButton.Text = '打开文件夹'; $openFolderButton.AutoSize = $true
    $quickBar.Controls.AddRange(@($openCurrentButton, $openFolderButton))
    $toolbar.Controls.Add($quickBar, 0, 3)

    $script:mainMenu = New-Object Windows.Forms.MenuStrip
    $mainMenu.Font = $form.Font
    $mainMenu.Dock = 'Top'
    $script:userGuideMenuItem = New-Object Windows.Forms.ToolStripMenuItem('使用说明')
    $mainMenu.Items.Add($userGuideMenuItem) | Out-Null
    $form.MainMenuStrip = $mainMenu
    $form.Controls.Add($mainMenu)

    $script:workflowStatus = New-Object Windows.Forms.Label
    $workflowStatus.Dock = 'Fill'; $workflowStatus.TextAlign = 'MiddleLeft'; $workflowStatus.AutoEllipsis = $true
    $workflowStatus.ForeColor = [Drawing.Color]::DarkSlateBlue
    $mainLayout.Controls.Add($workflowStatus, 0, 1)
    $stepFooter.Height = 126
    $stepFooter.RowStyles[0].Height = 54

    Refresh-ProfileList
    $profileCombo.Add_SelectionChangeCommitted({
        try { Switch-TestProfile -Name ([string]$profileCombo.SelectedItem) }
        catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '切换方案失败') | Out-Null }
    })
    $saveProfile.Add_Click({
        $name = Show-RecorderInputDialog -Prompt '输入方案名称：' -Title '另存测试方案' -DefaultText $script:activeProfile
        try { Save-ProfileAs -Name $name }
        catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '保存方案失败') | Out-Null }
    })
    $preferenceChanged = {
        $script:preferences.ShowInterval = $intervalToggle.Checked
        $script:preferences.Milliseconds = $millisecondToggle.Checked
        try { Save-WorkflowPreferences }
        catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '偏好保存失败') | Out-Null }
    }
    $intervalToggle.Add_CheckedChanged($preferenceChanged)
    $millisecondToggle.Add_CheckedChanged($preferenceChanged)
    $userGuideMenuItem.Add_Click({ Show-UserGuide })
    $script:openCurrentAction = {
        try { Open-CurrentLogLocation }
        catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '打开失败') | Out-Null }
    }
    $openCurrentButton.Add_Click($script:openCurrentAction)
    $script:openFolderAction = {
        try { Open-CurrentLogLocation -Folder }
        catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '打开失败') | Out-Null }
    }
    $openFolderButton.Add_Click($script:openFolderAction)
    $spaceFilter.Add_ExceptionPressed({ Add-ExceptionRecord })
    $spaceFilter.Add_UndoPressed({
        try { Undo-LastSpaceRecord | Out-Null }
        catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '撤销失败') | Out-Null }
    })
    $script:workflowTimer = New-Object Windows.Forms.Timer
    $workflowTimer.Interval = 200
    $workflowTimer.Add_Tick({ Update-WorkflowStatus; Update-RecorderWindowActivation })
    $workflowTimer.Start()
    $form.Add_FormClosed({ $workflowTimer.Stop(); $workflowTimer.Dispose() })
    Update-WorkflowStatus
}
