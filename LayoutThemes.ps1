# Both layouts reparent the same controls; execution and editing state stay alive.
$script:currentTheme = 'Classic'
$script:themeSplitters = @{ Classic = @{ SplitRatio = 0.46 }; Workbench = @{ SplitRatio = 0.33; WorkspaceRatio = 0.72 } }
$script:themePresentations = @{}
$script:buttonPresentations = @{}

function Get-ThemePresentation {
    param([Windows.Forms.Control]$Control)
    $state = @{ Control = $Control; Parent = $Control.Parent; Index = $Control.Parent.Controls.GetChildIndex($Control); Properties = @{} }
    foreach ($property in @('Dock', 'AutoSize', 'Size', 'Margin', 'Padding', 'BackColor', 'ForeColor', 'AutoEllipsis', 'TextAlign', 'FlatStyle')) {
        if ($Control.PSObject.Properties.Name -contains $property) { $state.Properties[$property] = $Control.$property }
    }
    if ($Control.Parent -is [Windows.Forms.TableLayoutPanel]) {
        $state.Row = $Control.Parent.GetRow($Control); $state.Column = $Control.Parent.GetColumn($Control)
        $state.RowSpan = $Control.Parent.GetRowSpan($Control); $state.ColumnSpan = $Control.Parent.GetColumnSpan($Control)
    }
    return $state
}

function Restore-ThemePresentation {
    param([hashtable]$State, [switch]$Placement)
    $control = $State.Control
    if ($Placement) {
        if ($State.Parent -is [Windows.Forms.TableLayoutPanel]) {
            $State.Parent.Controls.Add($control, $State.Column, $State.Row)
            $State.Parent.SetRowSpan($control, $State.RowSpan); $State.Parent.SetColumnSpan($control, $State.ColumnSpan)
        }
        else {
            $State.Parent.Controls.Add($control)
            $State.Parent.Controls.SetChildIndex($control, [Math]::Min($State.Index, $State.Parent.Controls.Count - 1))
        }
    }
    foreach ($property in @('AutoSize', 'Dock', 'Size', 'Margin', 'Padding', 'BackColor', 'ForeColor', 'AutoEllipsis', 'TextAlign', 'FlatStyle')) {
        if ($State.Properties.ContainsKey($property)) { $control.$property = $State.Properties[$property] }
    }
}

function Set-ThemeButtonStyle {
    param([Windows.Forms.Button]$Button, [switch]$Primary, [switch]$Danger)
    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderColor = [Drawing.ColorTranslator]::FromHtml('#CAD5E2')
    $Button.BackColor = [Drawing.ColorTranslator]::FromHtml('#F8FAFD')
    $Button.ForeColor = [Drawing.ColorTranslator]::FromHtml('#182C44')
    if ($Primary) {
        $Button.BackColor = [Drawing.ColorTranslator]::FromHtml('#1674E8')
        $Button.ForeColor = [Drawing.Color]::White
        $Button.FlatAppearance.BorderColor = $Button.BackColor
    }
    if ($Danger) {
        $Button.BackColor = [Drawing.ColorTranslator]::FromHtml('#FFF6F6')
        $Button.ForeColor = [Drawing.Color]::Firebrick
        $Button.FlatAppearance.BorderColor = [Drawing.ColorTranslator]::FromHtml('#E6B9B9')
    }
}

function Update-ThemeButton {
    param([Windows.Forms.Button]$Button)
    if (-not $script:buttonPresentations.ContainsKey($Button)) {
        $script:buttonPresentations[$Button] = Get-ThemePresentation $Button
    }
    if ($script:currentTheme -eq 'Workbench') { Set-ThemeButtonStyle $Button }
}

function Sync-ThemeStepWidths {
    if ($script:currentTheme -ne 'Workbench') { return }
    foreach ($button in $stepPanel.Controls) {
        $button.AutoSize = $false; $button.Width = [Math]::Max(85, $stepPanel.ClientSize.Width - 30)
        $button.Height = 44; $button.AutoEllipsis = $true
    }
}

function Update-ThemeRecordRow {
    param([Windows.Forms.TableLayoutPanel]$Row)
    if ($Row.ColumnStyles.Count -lt 5) { return }
    $Row.ColumnStyles[3].SizeType = if ($script:currentTheme -eq 'Workbench') { 'Absolute' } else { 'Percent' }
    $Row.ColumnStyles[3].Width = if ($script:currentTheme -eq 'Workbench') { 0 } else { 100 }
}

function Refresh-ThemeScrollPanels {
    if ($script:themeScrollRefreshing -or $script:changingTheme -or $form.IsDisposed) { return }
    $script:themeScrollRefreshing = $true
    try {
        foreach ($panel in @($recordsPanel, $stepPanel, $profileBar, $actionPanel)) {
            $position = $panel.AutoScrollPosition
            # Reset stale FlowLayoutPanel extents after a narrower layout.
            $panel.AutoScroll = $false; $panel.AutoScroll = $true
            $panel.AutoScrollPosition = New-Object Drawing.Point(-$position.X, -$position.Y)
        }
    }
    finally { $script:themeScrollRefreshing = $false }
}

function Request-ThemeScrollRefresh {
    if (-not $form.IsHandleCreated -or $form.IsDisposed -or $script:themeScrollQueued -or $script:themeScrollRefreshing -or $script:changingTheme) { return }
    $script:themeScrollQueued = $true
    $form.BeginInvoke([Action]{ $script:themeScrollQueued = $false; Refresh-ThemeScrollPanels }) | Out-Null
}

function New-ThemeGroup {
    param([string]$Title)
    $group = New-Object Windows.Forms.GroupBox
    $group.Text = $Title; $group.Dock = 'Fill'
    $group.Padding = New-Object Windows.Forms.Padding(10)
    $group.ForeColor = [Drawing.ColorTranslator]::FromHtml('#185799'); $group.BackColor = [Drawing.Color]::White
    return $group
}

function New-ThemeMenuAction {
    param([Windows.Forms.Button]$Source, [scriptblock]$Action)
    $item = New-Object Windows.Forms.ToolStripMenuItem($Source.Text)
    $item.Enabled = $Source.Enabled; $item.ForeColor = $Source.ForeColor
    $item.Add_Click($Action)
    $Source.Add_EnabledChanged({ $item.Enabled = $Source.Enabled }.GetNewClosure())
    return $item
}

function New-ThemeMenuToggle {
    param([Windows.Forms.CheckBox]$Source)
    $item = New-Object Windows.Forms.ToolStripMenuItem($Source.Text)
    $item.CheckOnClick = $true; $item.Checked = $Source.Checked
    $item.Add_CheckedChanged({ $Source.Checked = $item.Checked }.GetNewClosure())
    $Source.Add_CheckedChanged({ $item.Checked = $Source.Checked }.GetNewClosure())
    return $item
}

function Initialize-WorkbenchShell {
    $script:workspaceSplit = New-Object Windows.Forms.SplitContainer
    $workspaceSplit.Size = New-Object Drawing.Size(1100, 720)
    $workspaceSplit.Dock = 'Fill'; $workspaceSplit.Margin = New-Object Windows.Forms.Padding(0)
    $workspaceSplit.SplitterWidth = 8; $workspaceSplit.SplitterDistance = 780
    $workspaceSplit.Panel1MinSize = 600; $workspaceSplit.Panel2MinSize = 280
    $workspaceSplit.BackColor = [Drawing.ColorTranslator]::FromHtml('#DFE7F1')
    $workspaceSplit.Panel1.BackColor = [Drawing.ColorTranslator]::FromHtml('#F0F4F9')
    $workspaceSplit.Panel2.BackColor = $workspaceSplit.Panel1.BackColor
    $workspaceSplit.AccessibleName = '工作区与测试步骤分隔线'
    $script:workbenchLeft = New-Object Windows.Forms.TableLayoutPanel
    $workbenchLeft.Dock = 'Fill'; $workbenchLeft.ColumnCount = 1; $workbenchLeft.RowCount = 2
    $workbenchLeft.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
    $workbenchLeft.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 66))) | Out-Null
    $workbenchLeft.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100))) | Out-Null
    $workspaceSplit.Panel1.Controls.Add($workbenchLeft)
    $script:workbenchAreaSplit = New-Object Windows.Forms.SplitContainer
    $workbenchAreaSplit.Size = New-Object Drawing.Size(780, 600)
    $workbenchAreaSplit.Orientation = 'Horizontal'; $workbenchAreaSplit.Dock = 'Fill'
    $workbenchAreaSplit.Margin = New-Object Windows.Forms.Padding(0)
    $workbenchAreaSplit.SplitterWidth = 8; $workbenchAreaSplit.SplitterDistance = 200
    $workbenchAreaSplit.Panel1MinSize = 140; $workbenchAreaSplit.Panel2MinSize = 160
    $workbenchAreaSplit.BackColor = $workspaceSplit.BackColor
    $workbenchAreaSplit.AccessibleName = '操作按钮与记录区分隔线'
    $workbenchLeft.Controls.Add($workbenchAreaSplit, 0, 1)
    $group = New-ThemeGroup '操作按钮'
    $workbenchAreaSplit.Panel1.Controls.Add($group)
    $script:workbenchActions = New-Object Windows.Forms.TableLayoutPanel
    $workbenchActions.Dock = 'Fill'; $workbenchActions.ColumnCount = 1; $workbenchActions.RowCount = 2
    $workbenchActions.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
    $workbenchActions.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 46))) | Out-Null
    $workbenchActions.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100))) | Out-Null
    $workbenchActions.ForeColor = [Drawing.Color]::Black; $group.Controls.Add($workbenchActions)
    $script:workbenchInput = New-Object Windows.Forms.TableLayoutPanel
    $workbenchInput.Dock = 'Fill'; $workbenchInput.ColumnCount = 3; $workbenchInput.RowCount = 1
    $workbenchInput.Margin = New-Object Windows.Forms.Padding(0)
    foreach ($style in @((New-Object Windows.Forms.ColumnStyle('Absolute', 100)), (New-Object Windows.Forms.ColumnStyle('Percent', 100)), (New-Object Windows.Forms.ColumnStyle('Absolute', 120)))) { $workbenchInput.ColumnStyles.Add($style) | Out-Null }
    $workbenchInput.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100))) | Out-Null
    $workbenchActions.Controls.Add($workbenchInput, 0, 0)
    $group = New-ThemeGroup '操作记录'
    $workbenchAreaSplit.Panel2.Controls.Add($group)
    $script:workbenchRecords = New-Object Windows.Forms.TableLayoutPanel
    $workbenchRecords.Dock = 'Fill'; $workbenchRecords.ColumnCount = 2; $workbenchRecords.RowCount = 2
    $workbenchRecords.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
    $workbenchRecords.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 0))) | Out-Null
    $workbenchRecords.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100))) | Out-Null
    $workbenchRecords.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 36))) | Out-Null
    $workbenchRecords.ForeColor = [Drawing.Color]::Black; $group.Controls.Add($workbenchRecords)
    $undoDeleteButton.Add_VisibleChanged({
        $workbenchRecords.ColumnStyles[1].Width = if ($undoDeleteButton.Visible) { 106 } else { 0 }
    })

    $script:workbenchFileMenu = New-Object Windows.Forms.ToolStripMenuItem('文件(&F)')
    $script:themeOpenFileItem = New-ThemeMenuAction $selectFileButton $script:selectFileAction
    $script:themeNewFileItem = New-ThemeMenuAction $newFileButton $script:newFileAction
    $script:themeClearRecordsItem = New-ThemeMenuAction $clearRecordsButton $script:clearRecordsAction
    $workbenchFileMenu.DropDownItems.AddRange(@($themeOpenFileItem, $themeNewFileItem, (New-Object Windows.Forms.ToolStripSeparator), (New-ThemeMenuAction $openCurrentButton $script:openCurrentAction), (New-ThemeMenuAction $openFolderButton $script:openFolderAction), (New-Object Windows.Forms.ToolStripSeparator), $themeClearRecordsItem))
    $script:workbenchProfileMenu = New-Object Windows.Forms.ToolStripMenuItem('方案(&P)')
    $workbenchProfileMenu.Add_DropDownOpening({
        foreach ($item in @($workbenchProfileMenu.DropDownItems)) { $item.Dispose() }
        foreach ($name in @($script:profiles.Keys | Sort-Object)) {
            $item = New-Object Windows.Forms.ToolStripMenuItem($name)
            $item.Checked = $name -eq $script:activeProfile; $item.Tag = $name
            $item.Add_Click({
                param($sender, $eventArgs)
                try { Switch-TestProfile -Name ([string]$sender.Tag) }
                catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '切换方案失败') | Out-Null }
            })
            $workbenchProfileMenu.DropDownItems.Add($item) | Out-Null
        }
        $workbenchProfileMenu.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator)) | Out-Null
        $item = New-Object Windows.Forms.ToolStripMenuItem('另存方案')
        $item.Add_Click({ $saveProfile.PerformClick() }); $workbenchProfileMenu.DropDownItems.Add($item) | Out-Null
    })
    $script:workbenchButtonMenu = New-Object Windows.Forms.ToolStripMenuItem('按钮管理(&B)')
    $script:themeSaveConfigItem = New-ThemeMenuAction $saveConfigButton $script:saveConfigAction
    $script:themeClearConfigItem = New-ThemeMenuAction $clearConfigButton $script:clearConfigAction
    $workbenchButtonMenu.DropDownItems.AddRange(@($themeSaveConfigItem, $themeClearConfigItem))
    $script:themeTopmostItem = New-ThemeMenuToggle $topMostToggle
    $script:themeSoundItem = New-ThemeMenuToggle $soundToggle
    $script:themeIntervalItem = New-ThemeMenuToggle $intervalToggle
    $script:themeMillisecondsItem = New-ThemeMenuToggle $millisecondToggle
}

function Set-WorkbenchPresentation {
    $form.BackColor = [Drawing.ColorTranslator]::FromHtml('#F0F4F9')
    $mainLayout.ColumnStyles.Clear(); $mainLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
    $mainLayout.Controls.Remove($classicAreaSplit); $mainLayout.Controls.Add($workspaceSplit, 0, 0)
    $script:areaSplit = $workbenchAreaSplit
    $workbenchLeft.Controls.Add($profileBar, 0, 0)
    $profileBar.Padding = New-Object Windows.Forms.Padding(8, 10, 4, 4)
    $profileBar.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 8)
    $profileBar.BackColor = [Drawing.Color]::White
    $profileCombo.Width = 170
    $intervalToggle.Visible = $false; $millisecondToggle.Visible = $false
    $profileBar.Controls.Add($configStatusLabel)
    $configStatusLabel.AutoSize = $false; $configStatusLabel.AutoEllipsis = $true
    $configStatusLabel.Size = New-Object Drawing.Size(190, 28)
    $configStatusLabel.Margin = New-Object Windows.Forms.Padding(10, 8, 0, 0)
    $configStatusLabel.ForeColor = [Drawing.ColorTranslator]::FromHtml('#1674E8')
    $configStatusLabel.BackColor = [Drawing.Color]::White
    $workbenchInput.Controls.Add($nameLabel, 0, 0)
    $workbenchInput.Controls.Add($nameInput, 1, 0)
    $workbenchInput.Controls.Add($addButton, 2, 0)
    $nameLabel.Dock = 'Fill'; $nameLabel.AutoSize = $false; $nameLabel.TextAlign = 'MiddleLeft'
    $nameLabel.Margin = New-Object Windows.Forms.Padding(0)
    $nameLabel.BackColor = [Drawing.Color]::White
    $nameInput.Dock = 'Fill'; $nameInput.Margin = New-Object Windows.Forms.Padding(0, 6, 12, 0)
    $addButton.AutoSize = $false; $addButton.Dock = 'Fill'; $addButton.Margin = New-Object Windows.Forms.Padding(0, 1, 0, 7)
    $workbenchActions.Controls.Add($actionPanel, 0, 1)
    $actionPanel.Padding = New-Object Windows.Forms.Padding(0, 4, 0, 0)
    $actionPanel.BackColor = [Drawing.Color]::White
    $workbenchRecords.Controls.Add($recordsPanel, 0, 0); $workbenchRecords.SetColumnSpan($recordsPanel, 2)
    $recordsPanel.BorderStyle = 'None'
    $workbenchRecords.Controls.Add($fileLabel, 0, 1); $workbenchRecords.Controls.Add($undoDeleteButton, 1, 1)
    $fileLabel.BackColor = [Drawing.ColorTranslator]::FromHtml('#F0F5FC')
    $fileLabel.ForeColor = [Drawing.Color]::Black
    $workspaceSplit.Panel2.Controls.Add($stepGroup)
    $stepGroup.Padding = New-Object Windows.Forms.Padding(10); $stepGroup.BackColor = [Drawing.Color]::White
    $stepGroup.ForeColor = [Drawing.ColorTranslator]::FromHtml('#185799')
    $stepPanel.BackColor = [Drawing.Color]::White; $stepPanel.ForeColor = [Drawing.Color]::Black
    $stepFooter.Height = 176; $stepFooter.RowStyles[0].Height = 72
    $stepStatus.BackColor = [Drawing.ColorTranslator]::FromHtml('#F0F5FC')
    $stepStatus.ForeColor = [Drawing.ColorTranslator]::FromHtml('#182C44')
    Set-ThemeButtonStyle $addButton -Primary
    Set-ThemeButtonStyle $saveProfile
    Set-ThemeButtonStyle $redoRoundButton
    Set-ThemeButtonStyle $nextRoundButton -Primary
    Set-ThemeButtonStyle $restartButton
    Set-ThemeButtonStyle $clearStepsButton -Danger
    foreach ($button in @($actionPanel.Controls) + @($stepPanel.Controls)) { Update-ThemeButton $button }
    $mainMenu.Items.Insert(0, $workbenchFileMenu)
    $mainMenu.Items.Insert(1, $workbenchProfileMenu)
    $mainMenu.Items.Insert(2, $workbenchButtonMenu)
    $settingsMenu.DropDownItems.Insert(0, $themeTopmostItem)
    $settingsMenu.DropDownItems.Insert(1, $themeSoundItem)
    $settingsMenu.DropDownItems.Insert(2, $themeIntervalItem)
    $settingsMenu.DropDownItems.Insert(3, $themeMillisecondsItem)
}

function Set-ClassicPresentation {
    $mainLayout.Controls.Remove($workspaceSplit)
    $script:areaSplit = $classicAreaSplit
    $mainLayout.Controls.Add($classicAreaSplit, 0, 0)
    foreach ($control in $script:themeMovableControls) { Restore-ThemePresentation $script:themePresentations[$control] -Placement }
    foreach ($control in $script:themeStyledControls) { Restore-ThemePresentation $script:themePresentations[$control] }
    foreach ($button in @($actionPanel.Controls) + @($stepPanel.Controls)) {
        if ($script:buttonPresentations.ContainsKey($button)) { Restore-ThemePresentation $script:buttonPresentations[$button] }
    }
    $form.BackColor = $script:classicBackground
    $profileCombo.Width = 150
    $intervalToggle.Visible = $true; $millisecondToggle.Visible = $true
    $recordsPanel.BorderStyle = 'FixedSingle'
    $stepFooter.Height = 126; $stepFooter.RowStyles[0].Height = 54
    foreach ($item in @($workbenchFileMenu, $workbenchProfileMenu, $workbenchButtonMenu)) { $mainMenu.Items.Remove($item) }
    foreach ($item in @($themeTopmostItem, $themeSoundItem, $themeIntervalItem, $themeMillisecondsItem)) { $settingsMenu.DropDownItems.Remove($item) }
}

function Set-LayoutTheme {
    param([ValidateSet('Classic', 'Workbench')][string]$Theme, [switch]$NoSave)
    if ($Theme -eq $script:currentTheme -or $script:changingTheme) { return }
    $oldTheme = $script:currentTheme
    if (-not $NoSave) {
        Save-WindowLayout
        $script:preferences.LayoutTheme = $Theme
        try { Save-WorkflowPreferences }
        catch { $script:preferences.LayoutTheme = $oldTheme; throw }
    }
    $focused = $form.ActiveControl
    while ($focused -is [Windows.Forms.ContainerControl] -and $focused.ActiveControl) { $focused = $focused.ActiveControl }
    $recordPosition = $recordsPanel.AutoScrollPosition; $stepPosition = $stepPanel.AutoScrollPosition
    $script:changingTheme = $true
    $form.SuspendLayout(); $mainLayout.SuspendLayout()
    try {
        $script:currentTheme = $Theme
        if ($Theme -eq 'Workbench') { Set-WorkbenchPresentation } else { Set-ClassicPresentation }
        $script:splitRatio = [double]$script:themeSplitters[$Theme].SplitRatio
        $script:workspaceRatio = if ($Theme -eq 'Workbench') { [double]$script:themeSplitters.Workbench.WorkspaceRatio } else { 0.72 }
        $classicThemeItem.Checked = $Theme -eq 'Classic'; $workbenchThemeItem.Checked = $Theme -eq 'Workbench'
    }
    finally {
        $mainLayout.ResumeLayout($true); $form.ResumeLayout($true)
        $script:changingTheme = $false
    }
    Apply-SavedSplitter
    Sync-ThemeStepWidths
    foreach ($row in $recordsPanel.Controls) { Update-ThemeRecordRow $row }
    Update-StepDisplay
    Refresh-ThemeScrollPanels
    $recordsPanel.AutoScrollPosition = New-Object Drawing.Point(-$recordPosition.X, -$recordPosition.Y)
    $stepPanel.AutoScrollPosition = New-Object Drawing.Point(-$stepPosition.X, -$stepPosition.Y)
    if ($focused -and -not $focused.IsDisposed -and $focused.CanFocus) { $focused.Focus() | Out-Null }
    else { $form.ActiveControl = $null }
    Update-WorkflowStatus
}

function Initialize-LayoutThemes {
    $script:classicAreaSplit = $areaSplit
    $script:classicBackground = $form.BackColor
    $script:themeMovableControls = @($profileBar, $configStatusLabel, $nameLabel, $nameInput, $addButton, $actionPanel, $recordsPanel, $fileLabel, $undoDeleteButton, $stepGroup)
    $script:themeStyledControls = @($saveProfile, $stepPanel, $stepStatus, $redoRoundButton, $nextRoundButton, $restartButton, $clearStepsButton)
    foreach ($control in $script:themeMovableControls + $script:themeStyledControls) { $script:themePresentations[$control] = Get-ThemePresentation $control }
    foreach ($button in $actionPanel.Controls) { Update-ThemeButton $button }
    $actionPanel.Add_ControlAdded({ param($sender, $eventArgs) Update-ThemeButton $eventArgs.Control })
    $stepPanel.Add_ControlAdded({ param($sender, $eventArgs) Update-ThemeButton $eventArgs.Control; Sync-ThemeStepWidths })
    $stepPanel.Add_SizeChanged({ Sync-ThemeStepWidths; Request-ThemeScrollRefresh })
    $recordsPanel.Add_SizeChanged({ Request-ThemeScrollRefresh })
    $recordsPanel.Add_ControlAdded({ param($sender, $eventArgs) Update-ThemeRecordRow $eventArgs.Control })
    $profileBar.Add_SizeChanged({ Request-ThemeScrollRefresh })
    $script:settingsMenu = New-Object Windows.Forms.ToolStripMenuItem('设置(&S)')
    $script:themeMenu = New-Object Windows.Forms.ToolStripMenuItem('界面布局')
    $script:classicThemeItem = New-Object Windows.Forms.ToolStripMenuItem('经典布局')
    $classicThemeItem.Checked = $true
    $script:workbenchThemeItem = New-Object Windows.Forms.ToolStripMenuItem('精简工作台')
    foreach ($item in @($classicThemeItem, $workbenchThemeItem)) {
        $item.Tag = if ($item -eq $classicThemeItem) { 'Classic' } else { 'Workbench' }
        $item.Add_Click({
            param($sender, $eventArgs)
            try { Set-LayoutTheme -Theme ([string]$sender.Tag) }
            catch { [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '切换布局失败') | Out-Null }
        })
    }
    $themeMenu.DropDownItems.AddRange(@($classicThemeItem, $workbenchThemeItem))
    $settingsMenu.DropDownItems.Add($themeMenu) | Out-Null
    $mainMenu.Items.Insert(0, $settingsMenu)
    Initialize-WorkbenchShell
    $workbenchAreaSplit.Add_SplitterMoved({ if ($script:currentTheme -eq 'Workbench') { Update-WindowLayoutState } })
    $workspaceSplit.Add_SplitterMoved({ if ($script:currentTheme -eq 'Workbench') { Update-WindowLayoutState } })
    if ($script:preferences.LayoutTheme -eq 'Workbench') { Set-LayoutTheme -Theme Workbench -NoSave }
    $form.Add_Shown({ Sync-ThemeStepWidths; Refresh-ThemeScrollPanels })
    $form.Add_FormClosed({
        # Detached layout shells are not disposed by the visible form.
        if (-not $classicAreaSplit.IsDisposed) { $classicAreaSplit.Dispose() }
        if (-not $workspaceSplit.IsDisposed) { $workspaceSplit.Dispose() }
    })
}
