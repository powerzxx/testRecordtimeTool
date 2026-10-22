$ErrorActionPreference = 'Stop'
$originalAppData = $env:APPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RecorderSequenceTest-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
$env:APPDATA = $testRoot
function Assert($condition, $message) { if (-not $condition) { throw $message } }
try {
    $configDir = Join-Path $testRoot 'EarphoneLogTimeRecorder'
    New-Item -ItemType Directory -Path $configDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $configDir 'buttons.json'), '["1","2","3"]')
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RecordTime.ps1'))
    $source = $source.Replace('[System.Windows.Forms.Application]::Run($form)', '')
    $source = $source.Replace('$PSScriptRoot', "'" + $PSScriptRoot.Replace("'", "''") + "'")
    # Deterministic answers for the rename/delete dialogs in this isolated UI test.
    $source = [regex]::Replace($source, '\(Show-RecorderInputDialog [^\r\n]+\)\.Trim\(\)', "'Renamed'")
    $source = [regex]::Replace($source, '(?s)\$answer = \[System.Windows.Forms.MessageBox\]::Show\(\s*\$form,\s*\(''确定删除.*?\n        \)', '$answer = [System.Windows.Forms.DialogResult]::Yes')
    . ([scriptblock]::Create($source))
    Assert ($actionPanel.Controls.Count -eq 3) 'Legacy config failed'
    Assert ($stepPanel.Controls.Count -eq 0) 'Legacy config should have no steps'
    $script:activeLogPath = Join-Path $testRoot 'records.txt'
    [IO.File]::WriteAllText($script:activeLogPath, '')
    $form.Show()
    $form.Activate()
    [Windows.Forms.Application]::DoEvents()
    # Simulate actual drop event handlers: copy from library, then reorder.
    foreach ($button in @($actionPanel.Controls)) {
        $data = New-Object Windows.Forms.DataObject('RecorderStep', $button)
        $point = $stepPanel.PointToScreen((New-Object Drawing.Point(300, 500)))
        $args = New-Object Windows.Forms.DragEventArgs($data, 0, $point.X, $point.Y, 3, 0)
        & $stepDrop $stepPanel $args
    }
    Assert (($script:stepNames -join ',') -eq '1,2,3') 'Drop from library failed'
    $last = $stepPanel.Controls[2]
    $data = New-Object Windows.Forms.DataObject('RecorderStep', $last)
    $point = $stepPanel.PointToScreen((New-Object Drawing.Point(0, 0)))
    $args = New-Object Windows.Forms.DragEventArgs($data, 0, $point.X, $point.Y, 3, 0)
    & $stepDrop $stepPanel $args
    Assert (($script:stepNames -join ',') -eq '3,1,2') 'Reordering failed'
    $automatic = Get-Content $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert (($automatic.Steps -join ',') -eq '3,1,2') 'Step reorder not automatically saved'
    Assert (([IO.File]::ReadAllText($script:activeLogPath)).Length -eq 0) 'Dragging must not record'
    $restartButton.Focus() | Out-Null
    $key = [Windows.Forms.Message]::Create($restartButton.Handle, 0x100, [intptr]32, [intptr]0)
    Assert ($spaceFilter.PreFilterMessage([ref]$key)) 'Space not consumed'
    Assert ($script:nextStep -eq 1) 'Space did not advance exactly once'
    $repeat = [Windows.Forms.Message]::Create($restartButton.Handle, 0x100, [intptr]32, [intptr]0x40000000)
    $spaceFilter.PreFilterMessage([ref]$repeat) | Out-Null
    Assert ($script:nextStep -eq 1) 'Held space repeated'
    $nameInput.Focus() | Out-Null
    $key = [Windows.Forms.Message]::Create($nameInput.Handle, 0x100, [intptr]32, [intptr]0)
    Assert (-not $spaceFilter.PreFilterMessage([ref]$key)) 'Text input space swallowed'
    Assert ($script:nextStep -eq 1) 'Text input triggered recording'
    Invoke-NextStep
    Invoke-NextStep
    Assert ($script:nextStep -eq 0) 'Next round should start at first step'
    Assert ($script:currentRound -eq 2) 'Round should advance after last step'
    Assert ($stepPanel.Controls[0].BackColor -eq [Drawing.Color]::Gold) 'First step should be highlighted for next round'
    Invoke-NextStep
    Invoke-NextStep
    Invoke-NextStep
    $lines = @([IO.File]::ReadAllLines($script:activeLogPath) | Where-Object { $_ -match '^\d{2}:\d{2}:\d{2}' })
    Assert ($lines.Count -eq 6) 'Two rounds should record exactly six entries'
    Assert ($script:currentRound -eq 3) 'Two completed rounds should prepare round three'
    Assert (($lines[0] -match ' 3$') -and ($lines[1] -match ' 1$') -and ($lines[2] -match ' 2$')) 'Record order incorrect'
    Assert (($lines[3] -match ' 3$') -and ($lines[4] -match ' 1$') -and ($lines[5] -match ' 2$')) 'Second round order incorrect'
    Save-ButtonConfig
    $saved = Get-Content $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert (($saved.Steps -join ',') -eq '3,1,2') 'Steps not saved'
    Assert (($saved.Buttons -join ',') -eq '1,2,3') 'Library was changed'
    Reset-StepProgress
    Assert ($script:nextStep -eq 0) 'Restart failed'
    Assert ($script:currentRound -eq 1) 'Restart did not reset round'
    Remove-StepsForName -Name '1'
    Assert (($script:stepNames -join ',') -eq '3,2') 'Delete synchronization failed'
    $script:activeLogPath = $null
    Invoke-NextStep
    Assert ($script:nextStep -eq 0) 'Missing log advanced progress'

    $target = $actionPanel.Controls[2]
    $target.ContextMenuStrip.Items[0].PerformClick()
    $saved = Get-Content $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert (($saved.Buttons -join ',') -eq '1,3,2') 'Button reorder not auto-saved'
    $target.ContextMenuStrip.Items[3].PerformClick()
    $saved = Get-Content $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert (($saved.Buttons -join ',') -eq '1,Renamed,2' -and ($saved.Steps -join ',') -eq 'Renamed,2') 'Rename not auto-saved consistently'
    $target.ContextMenuStrip.Items[4].PerformClick()
    $saved = Get-Content $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert (($saved.Buttons -join ',') -eq '1,2' -and ($saved.Steps -join ',') -eq '2') 'Delete not auto-saved consistently'
    $clearStepsButton.PerformClick()
    $saved = Get-Content $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($saved.Steps.Count -eq 0 -and -not $saveConfigButton.Enabled) 'Clear steps not auto-saved'

    # Regressions: progress must survive changes outside the actual sequence.
    $script:activeLogPath = Join-Path $testRoot 'progress-regression.txt'
    Add-StepButton -Name '2' | Out-Null
    Add-StepButton -Name '2' | Out-Null
    Sync-Steps
    1..5 | ForEach-Object { Invoke-NextStep }
    Assert ($script:currentRound -eq 3 -and $script:nextStep -eq 1) 'Regression setup failed'
    $outside = $actionPanel.Controls | Where-Object { $_.Tag -eq '1' } | Select-Object -First 1
    $outside.Focus() | Out-Null
    $outside.PerformClick()
    Assert ($script:currentRound -eq 3 -and $script:nextStep -eq 1) 'Outside click reset progress'
    $key = [Windows.Forms.Message]::Create($outside.Handle, 0x100, [intptr]32, [intptr]0)
    $spaceFilter.PreFilterMessage([ref]$key) | Out-Null
    Assert ($script:currentRound -eq 4 -and $script:nextStep -eq 0) 'Space after outside click reset round'
    Invoke-NextStep
    $outside.ContextMenuStrip.Items[3].PerformClick()
    Assert ($script:currentRound -eq 4 -and $script:nextStep -eq 1) 'Unrelated rename reset progress'
    $outside.ContextMenuStrip.Items[4].PerformClick()
    Assert ($script:currentRound -eq 4 -and $script:nextStep -eq 1) 'Unrelated delete reset progress'
    $lastStep = $stepPanel.Controls[1]
    $data = New-Object Windows.Forms.DataObject('RecorderStep', $lastStep)
    $point = $stepPanel.PointToScreen((New-Object Drawing.Point($lastStep.Left, ($lastStep.Top + 1))))
    $dropArgs = New-Object Windows.Forms.DragEventArgs($data, 0, $point.X, $point.Y, 3, 0)
    & $stepDrop $lastStep $dropArgs
    Assert ($script:currentRound -eq 4 -and $script:nextStep -eq 1) 'No-op drag reset progress'
    Sync-Steps
    Assert ($script:currentRound -eq 4 -and $script:nextStep -eq 1) 'Unchanged sync reset progress'
    $included = $actionPanel.Controls[0]
    $included.ContextMenuStrip.Items[3].PerformClick()
    Assert ($script:currentRound -eq 4 -and $script:nextStep -eq 1) 'Included rename reset progress'
    Assert (($script:stepNames -join ',') -eq 'Renamed,Renamed') 'Included rename did not update step labels'
    $point = $stepPanel.PointToScreen((New-Object Drawing.Point(0, 0)))
    $dropArgs = New-Object Windows.Forms.DragEventArgs($data, 0, $point.X, $point.Y, 3, 0)
    & $stepDrop $stepPanel $dropArgs
    Assert ($script:currentRound -eq 4 -and $script:nextStep -eq 0) 'Duplicate reorder should preserve round and pending identity'
    1..3 | ForEach-Object { Invoke-NextStep }
    $stepPanel.Controls[0].ContextMenuStrip.Items[0].PerformClick()
    Assert ($script:currentRound -eq 6 -and $script:nextStep -eq 0) 'Removing a step should preserve round'
    Write-Output 'PASS: outside click then space, unrelated rename/delete, no-op drag, included rename, duplicate reorder, actual removal'

    foreach ($name in @('A','B','C','Before','After')) {
        $nameInput.Text = $name
        $addButton.PerformClick()
    }
    function Start-LiveStepScenario {
        while ($stepPanel.Controls.Count -gt 0) { $stepPanel.Controls[0].Dispose() }
        foreach ($name in @('A','B','C')) { Add-StepButton -Name $name | Out-Null }
        Sync-Steps
        Reset-StepProgress
        1..7 | ForEach-Object { Invoke-NextStep }
        Assert ($script:currentRound -eq 3 -and $script:pendingSteps[0].Tag -eq 'B') 'Live scenario setup failed'
    }
    Start-LiveStepScenario
    $before = Add-StepButton -Name 'Before'
    $stepPanel.Controls.SetChildIndex($before, 1)
    Sync-Steps
    Assert ($script:currentRound -eq 3 -and $script:pendingSteps[0].Tag -eq 'B') 'Insertion before cursor changed round or next step'
    Assert ($before.BackColor -eq [Drawing.Color]::WhiteSmoke) 'Deferred step incorrectly shown as completed'
    $recordWriter = (Get-Command Write-ActionRecord).ScriptBlock
    try {
        Set-Item Function:Write-ActionRecord -Value { return $false }
        Invoke-NextStep
        Assert ($script:currentRound -eq 3 -and $script:pendingSteps[0].Tag -eq 'B') 'Failed write consumed pending step'
    }
    finally { Set-Item Function:Write-ActionRecord -Value $recordWriter }
    $after = Add-StepButton -Name 'After'
    $stepPanel.Controls.SetChildIndex($after, 3)
    Sync-Steps
    1..3 | ForEach-Object { Invoke-NextStep }
    $tail = @([IO.File]::ReadAllLines($script:activeLogPath) | Select-Object -Last 3 | ForEach-Object { $_.Substring(9) })
    Assert (($tail -join ',') -eq 'B,After,C' -and $script:currentRound -eq 4) 'Inserted steps executed in wrong round'
    1..5 | ForEach-Object { Invoke-NextStep }
    $tail = @([IO.File]::ReadAllLines($script:activeLogPath) | Select-Object -Last 5 | ForEach-Object { $_.Substring(9) })
    Assert (($tail -join ',') -eq 'A,Before,B,After,C' -and $script:currentRound -eq 5) 'Next round missing deferred step'
    Start-LiveStepScenario
    $completed = $stepPanel.Controls[0]
    $stepPanel.Controls.SetChildIndex($completed, 2)
    Sync-Steps
    1..2 | ForEach-Object { Invoke-NextStep }
    $tail = @([IO.File]::ReadAllLines($script:activeLogPath) | Select-Object -Last 2 | ForEach-Object { $_.Substring(9) })
    Assert (($tail -join ',') -eq 'B,C' -and $script:currentRound -eq 4) 'Reorder repeated completed step'
    Start-LiveStepScenario
    Remove-StepsForName -Name 'B'
    Assert ($script:currentRound -eq 3 -and $script:pendingSteps[0].Tag -eq 'C') 'Deleting next step lost successor'
    Remove-StepsForName -Name 'C'
    Assert ($script:currentRound -eq 3 -and $script:pendingSteps.Count -eq 0) 'Removing remaining steps reset round'
    Invoke-NextStep
    Assert ($script:currentRound -eq 5) 'Single-step following round failed'
    $clearStepsButton.PerformClick()
    Invoke-NextStep
    Assert ($script:currentRound -eq 5) 'Clearing steps reset round'
    Add-StepButton -Name 'A' | Out-Null
    Sync-Steps
    Assert ($script:currentRound -eq 5) 'Adding into empty area reset round'
    Reset-StepProgress
    Assert ($script:currentRound -eq 1) 'Explicit restart must still reset round'
    Write-Output 'PASS: live insert before/after cursor, next round inclusion, completed-step reorder, successor deletion, empty sequence'

    Start-LiveStepScenario
    $beforeRestart = [IO.File]::ReadAllText($script:activeLogPath)
    $rowCount = $recordsPanel.Controls.Count
    $redoRoundButton.PerformClick()
    Assert ($script:currentRound -eq 3 -and $script:nextStep -eq 0 -and $script:pendingSteps.Count -eq 3) 'Redo must keep round and restart at step one'
    Assert ($script:completedSteps.Count -eq 0 -and -not $script:roundStarted) 'Redo kept old completed steps'
    $redoRoundButton.PerformClick()
    Assert ($script:currentRound -eq 3 -and [IO.File]::ReadAllText($script:activeLogPath) -eq $beforeRestart -and $recordsPanel.Controls.Count -eq $rowCount) 'Repeated redo changed round or records'
    $redoRoundButton.Focus() | Out-Null
    $key = [Windows.Forms.Message]::Create($redoRoundButton.Handle, 0x100, [intptr]32, [intptr]0)
    $spaceFilter.PreFilterMessage([ref]$key) | Out-Null
    Assert ($script:currentRound -eq 3 -and $script:pendingSteps[0].Tag -eq 'B' -and [IO.File]::ReadAllLines($script:activeLogPath)[-1] -match ' A$') 'Space after redo must record step one without changing round'
    $beforeRestart = [IO.File]::ReadAllText($script:activeLogPath)
    $rowCount = $recordsPanel.Controls.Count
    $nextRoundButton.PerformClick()
    Assert ($script:currentRound -eq 4 -and $script:nextStep -eq 0 -and $script:pendingSteps.Count -eq 3) 'Next round did not reset steps and increment round'
    Assert ($script:completedSteps.Count -eq 0 -and -not $script:roundStarted) 'Next round kept old completion state'
    Assert ([IO.File]::ReadAllText($script:activeLogPath) -eq $beforeRestart -and $recordsPanel.Controls.Count -eq $rowCount) 'Next round wrote or removed records'
    $nextRoundButton.Focus() | Out-Null
    $key = [Windows.Forms.Message]::Create($nextRoundButton.Handle, 0x100, [intptr]32, [intptr]0)
    $spaceFilter.PreFilterMessage([ref]$key) | Out-Null
    Assert ($script:currentRound -eq 4 -and $script:pendingSteps[0].Tag -eq 'B') 'Space on next-round button must record first step only'
    Assert ([IO.File]::ReadAllLines($script:activeLogPath)[-1] -match ' A$') 'Next round did not record step one first'
    $beforeRestart = [IO.File]::ReadAllText($script:activeLogPath)
    $restartButton.PerformClick()
    Assert ($script:currentRound -eq 1 -and $script:nextStep -eq 0) 'Reset rounds did not return to round one step one'
    Assert ([IO.File]::ReadAllText($script:activeLogPath) -eq $beforeRestart) 'Reset rounds changed existing records'
    $form.Size = $form.MinimumSize
    $areaSplit.SplitterDistance = $areaSplit.Panel1MinSize
    [Windows.Forms.Application]::DoEvents()
    Assert ($stepPanel.Height -gt 40 -and $nextRoundButton.Height -ge 25 -and $redoRoundButton.Height -ge 25 -and $clearStepsButton.Bottom -le $stepFooter.Height) 'New round controls do not fit minimum layout'
    $clearStepsButton.PerformClick()
    Assert (-not $nextRoundButton.Enabled) 'Next round should be disabled for empty steps'
    Assert (-not $redoRoundButton.Enabled) 'Redo should be disabled for empty steps'
    $redoRoundButton.PerformClick()
    $nextRoundButton.PerformClick()
    Assert ($script:currentRound -eq 1) 'Empty sequence advanced rounds'
    Write-Output 'PASS: separate reset/redo/next-round buttons, no implicit records, space focus, minimum layout and empty sequence'

    Start-LiveStepScenario
    $nameInput.Text = 'BatchOne'
    $nameInput.Focus() | Out-Null
    $enter = New-Object Windows.Forms.KeyEventArgs([Windows.Forms.Keys]::Enter)
    $onKeyDown = [Windows.Forms.Control].GetMethod('OnKeyDown', [Reflection.BindingFlags]'Instance,NonPublic')
    $onKeyDown.Invoke($nameInput, @($enter.PSObject.BaseObject)) | Out-Null
    Assert ($nameInput.Focused -and $nameInput.Text -eq '' -and $script:buttonNames -contains 'BatchOne') 'Enter add should retain input focus'
    $nameInput.Text = 'BatchTwo'
    $addButton.PerformClick()
    Assert ($nameInput.Focused -and $nameInput.Text -eq '' -and $script:buttonNames -contains 'BatchTwo') 'Click add should retain input focus'
    $nameInput.Text = 'unfinished name'
    $beforeFocusChange = [IO.File]::ReadAllText($script:activeLogPath)
    $escape = [Windows.Forms.Message]::Create($nameInput.Handle, 0x100, [intptr]27, [intptr]0)
    Assert ($spaceFilter.PreFilterMessage([ref]$escape)) 'Escape was not handled'
    Assert (-not $nameInput.Focused -and $null -eq $form.ActiveControl -and $nameInput.Text -eq 'unfinished name') 'Escape must leave input without clearing it'
    Assert ($script:currentRound -eq 3 -and $script:pendingSteps[0].Tag -eq 'B') 'Escape changed test progress'
    Assert ([IO.File]::ReadAllText($script:activeLogPath) -eq $beforeFocusChange) 'Escape changed records'
    $key = [Windows.Forms.Message]::Create($form.Handle, 0x100, [intptr]32, [intptr]0)
    Assert ($spaceFilter.PreFilterMessage([ref]$key)) 'Space after Escape was not handled'
    Assert ($script:pendingSteps[0].Tag -eq 'C') 'Space after Escape did not execute next step'
    $beforeFocusChange = [IO.File]::ReadAllText($script:activeLogPath)
    $dynamicLabel = $recordsPanel.Controls[$recordsPanel.Controls.Count - 1].Controls['RecordText']
    foreach ($surface in @($actionPanel, $stepPanel, $recordsPanel, $fileLabel, $dynamicLabel, $areaSplit)) {
        $nameInput.Focus() | Out-Null
        $click = [Windows.Forms.Message]::Create($surface.Handle, 0x201, [intptr]1, [intptr]0)
        Assert (-not $spaceFilter.PreFilterMessage([ref]$click)) 'Blank click should still be dispatched normally'
        Assert (-not $nameInput.Focused -and $null -eq $form.ActiveControl) 'Blank click did not leave input'
    }
    foreach ($interactive in @($nameInput, $addButton, $topMostToggle, $soundToggle, $actionPanel.Controls[0])) {
        $nameInput.Focus() | Out-Null
        $click = [Windows.Forms.Message]::Create($interactive.Handle, 0x201, [intptr]1, [intptr]0)
        Assert (-not $spaceFilter.PreFilterMessage([ref]$click) -and $nameInput.Focused) 'Interactive click incorrectly triggered focus shortcut'
    }
    Assert ($script:currentRound -eq 3 -and $script:pendingSteps[0].Tag -eq 'C' -and [IO.File]::ReadAllText($script:activeLogPath) -eq $beforeFocusChange) 'Mouse focus shortcuts changed progress or records'
    $row = $recordsPanel.Controls[$recordsPanel.Controls.Count - 1]
    $row.Controls['EditRecordButton'].Visible = $true
    $row.Controls['EditRecordButton'].PerformClick()
    $editor = $row.Controls['RecordEditInput']
    $editor.Text = '12:34:56 unsaved edit'
    $escape = [Windows.Forms.Message]::Create($editor.Handle, 0x100, [intptr]27, [intptr]0)
    Assert (-not $spaceFilter.PreFilterMessage([ref]$escape)) 'Record editor Escape behavior was intercepted'
    $click = [Windows.Forms.Message]::Create($fileLabel.Handle, 0x201, [intptr]1, [intptr]0)
    $spaceFilter.PreFilterMessage([ref]$click) | Out-Null
    Assert (-not $editor.Focused -and $editor.Text -eq '12:34:56 unsaved edit') 'Blank click lost edit draft'
    Write-Output 'PASS: batch add focus, Escape return, blank/label clicks, interactive exclusions, unchanged records and edit drafts'

    $form.WindowState = 'Normal'
    $form.Size = New-Object Drawing.Size(1100, 740)
    $form.Location = New-Object Drawing.Point(30, 40)
    $areaSplit.SplitterDistance = 330
    Save-WindowLayout
    $savedLayout = Get-Content $script:windowLayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $form.Size = New-Object Drawing.Size(1040, 600)
    $areaSplit.SplitterDistance = 240
    Restore-WindowLayout
    Assert ($form.Width -eq $savedLayout.Width -and $form.Height -eq $savedLayout.Height) 'Window size not restored'
    Assert ($form.Left -eq $savedLayout.X -and $form.Top -eq $savedLayout.Y) 'Window position not restored'
    Assert ([Math]::Abs($areaSplit.SplitterDistance / ($areaSplit.ClientSize.Height - $areaSplit.SplitterWidth) - $savedLayout.SplitRatio) -lt 0.005) 'Splitter ratio not restored'
    $form.WindowState = 'Maximized'
    [Windows.Forms.Application]::DoEvents()
    Save-WindowLayout
    $maxLayout = Get-Content $script:windowLayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($maxLayout.Maximized -eq $true) 'Maximized state not saved'
    $form.WindowState = 'Minimized'
    Save-WindowLayout
    $minLayout = Get-Content $script:windowLayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($minLayout.Maximized -eq $true -and $minLayout.Width -eq $maxLayout.Width) 'Minimize lost restore state'
    $form.WindowState = 'Normal'
    Restore-WindowLayout
    Assert ($form.WindowState -eq [Windows.Forms.FormWindowState]::Maximized) 'Maximized state not restored'
    $form.WindowState = 'Normal'
    $savedLayout.X = -50000
    $savedLayout.Y = -50000
    Write-RecorderSettings -Path $script:windowLayoutPath -Json ($savedLayout | ConvertTo-Json)
    Restore-WindowLayout
    Assert ([Windows.Forms.Screen]::FromControl($form).WorkingArea.IntersectsWith($form.Bounds)) 'Off-screen layout was not recovered'
    [IO.File]::WriteAllText($script:windowLayoutPath, 'invalid json')
    Restore-WindowLayout
    Write-Output 'PASS: unified autosave, round progress, layout restore, maximize/minimize, off-screen and invalid layout'
    $bitmap = New-Object Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bitmap.Save((Join-Path $testRoot 'preview.png'))
    $bitmap.Dispose()
    Write-Output "PASS: legacy config, drag/drop, reorder, space, repeat suppression, text input, two rounds, persistence, reset, deletion, missing log. Preview: $testRoot\preview.png"
}
finally {
    if ($form) { $form.Close(); $form.Dispose() }
    $env:APPDATA = $originalAppData
}
