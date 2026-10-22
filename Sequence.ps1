function Update-StepDisplay {
    $script:nextStep = 0
    if ($script:pendingSteps.Count -gt 0) {
        $script:nextStep = $stepPanel.Controls.GetChildIndex($script:pendingSteps[0])
    }
    for ($i = 0; $i -lt $stepPanel.Controls.Count; $i++) {
        $button = $stepPanel.Controls[$i]
        $button.Text = [string]$button.Tag
        $button.BackColor = if ($script:pendingSteps.Count -gt 0 -and $i -eq $script:nextStep) { [System.Drawing.Color]::Gold } elseif ($script:completedSteps -contains $button) { [System.Drawing.Color]::Honeydew } else { [System.Drawing.Color]::WhiteSmoke }
    }
    $stepStatus.Text = if ($stepPanel.Controls.Count -eq 0) { '第 {0} 轮 · 拖入按钮后继续' -f $script:currentRound } elseif ($script:pendingSteps.Count -eq 0) { '第 {0} 轮 · 按空格进入下一轮' -f $script:currentRound } else { '第 {0} 轮 · 下一步 {1}/{2}' -f $script:currentRound, ($script:nextStep + 1), $stepPanel.Controls.Count }
    if ($script:pendingSteps.Count -gt 0) {
        $stepStatus.Text += "`r`n下一步：" + [string]$script:pendingSteps[0].Tag
    }
    $inputHint.SetToolTip($stepStatus, $stepStatus.Text)
    $clearStepsButton.Enabled = $stepPanel.Controls.Count -gt 0
    $nextRoundButton.Enabled = $stepPanel.Controls.Count -gt 0
    $redoRoundButton.Enabled = $stepPanel.Controls.Count -gt 0
    if ($script:nextStep -lt $stepPanel.Controls.Count) {
        $stepPanel.ScrollControlIntoView($stepPanel.Controls[$script:nextStep])
    }
}

function Reset-StepProgress {
    param([int]$Round = 1)
    Clear-UndoSpace
    $script:lastStepTimestamp = $null
    $script:nextStep = 0
    $script:currentRound = $Round
    $script:stepOrder = @($stepPanel.Controls)
    $script:pendingSteps = @($script:stepOrder)
    $script:completedSteps = @()
    $script:roundStarted = $false
    Update-StepDisplay
}

function Sync-Steps {
    param([switch]$NoSave)
    Clear-UndoSpace
    # Track identities so renames and duplicate button names preserve progress.
    $currentOrder = @($stepPanel.Controls)
    if (-not $script:roundStarted) {
        $script:pendingSteps = @($currentOrder)
    }
    else {
        $remaining = @($script:pendingSteps | Where-Object { $currentOrder -contains $_ })
        $anchorIndex = 0
        if ($remaining.Count -gt 0) {
            $anchorIndex = $stepPanel.Controls.GetChildIndex($remaining[0])
        }
        $updatedPending = @()
        # Preserve the next step. New entries before it wait for the next round.
        for ($offset = 0; $offset -lt $currentOrder.Count; $offset++) {
            $index = ($anchorIndex + $offset) % $currentOrder.Count
            $step = $currentOrder[$index]
            $isNew = $script:stepOrder -notcontains $step
            if ($remaining -contains $step -or ($isNew -and $index -ge $anchorIndex)) {
                $updatedPending += $step
            }
        }
        $script:pendingSteps = @($updatedPending)
    }
    $script:completedSteps = @($script:completedSteps | Where-Object { $currentOrder -contains $_ })
    $script:stepOrder = @($currentOrder)
    $script:stepNames = @($stepPanel.Controls | ForEach-Object { [string]$_.Tag })
    Update-StepDisplay
    if (-not $NoSave) { Set-ConfigDirty }
}

function Invoke-NextStep {
    # Capture at the key event, before rendering or file work.
    $pressedAt = Get-Date
    if ($stepPanel.Controls.Count -eq 0) { return }
    if ([string]::IsNullOrWhiteSpace($script:activeLogPath)) {
        $stepStatus.Text = '请先打开或新建记录文件'
        return
    }
    $startNextRound = $script:pendingSteps.Count -eq 0
    $pending = if ($startNextRound) { @($stepPanel.Controls) } else { @($script:pendingSteps) }
    $target = @($pending)[0]
    $name = [string]$target.Tag
    $recordRound = if ($startNextRound) { $script:currentRound + 1 } else { $script:currentRound }
    if (Write-ActionRecord -Name $name -Timestamp $pressedAt -RoundNumber $recordRound -Snapshot (Get-SequenceSnapshot)) {
        if ($startNextRound) {
            $script:currentRound++
            $script:completedSteps = @()
        }
        $script:roundStarted = $true
        $script:completedSteps += $target
        $script:pendingSteps = @($pending | Select-Object -Skip 1)
        if ($script:pendingSteps.Count -eq 0) {
            $script:currentRound++
            $script:roundStarted = $false
            $script:completedSteps = @()
            $script:pendingSteps = @($stepPanel.Controls)
        }
        Update-StepDisplay
    }
}

$stepDragOver = {
    param($sender, $eventArgs)
    $source = $eventArgs.Data.GetData('RecorderStep')
    $eventArgs.Effect = [System.Windows.Forms.DragDropEffects]::None
    if ($source -is [RecorderDragButton]) {
        if ($source.Parent -eq $actionPanel) { $eventArgs.Effect = [System.Windows.Forms.DragDropEffects]::Copy }
        elseif ($source.Parent -eq $stepPanel) { $eventArgs.Effect = [System.Windows.Forms.DragDropEffects]::Move }
    }
}
$stepDrop = {
    param($sender, $eventArgs)
    $source = $eventArgs.Data.GetData('RecorderStep')
    if ($source -isnot [RecorderDragButton]) { return }
    if ($source.Parent -ne $actionPanel -and $source.Parent -ne $stepPanel) { return }
    $point = $stepPanel.PointToClient((New-Object System.Drawing.Point($eventArgs.X, $eventArgs.Y)))
    $index = $stepPanel.Controls.Count
    foreach ($candidate in $stepPanel.Controls) {
        if ($point.Y -lt ($candidate.Top + $candidate.Height / 2)) {
            $index = $stepPanel.Controls.GetChildIndex($candidate)
            break
        }
    }
    if ($source.Parent -eq $stepPanel) {
        $oldIndex = $stepPanel.Controls.GetChildIndex($source)
        if ($oldIndex -lt $index) { $index-- }
        if ($oldIndex -eq $index) { return }
        $stepPanel.Controls.SetChildIndex($source, $index)
    }
    else {
        $newStep = Add-StepButton -Name ([string]$source.Tag)
        $stepPanel.Controls.SetChildIndex($newStep, $index)
    }
    Sync-Steps
    $restartButton.Focus() | Out-Null
}

function Add-StepButton {
    param([string]$Name)
    $button = New-Object RecorderDragButton
    $button.Tag = $Name
    $button.AutoSize = $true
    $button.MinimumSize = New-Object System.Drawing.Size(85, 38)
    $button.Margin = New-Object System.Windows.Forms.Padding(4)
    $button.AllowDrop = $true
    $button.Add_DragEnter($stepDragOver)
    $button.Add_DragOver($stepDragOver)
    $button.Add_DragDrop($stepDrop)
    $button.Add_Click({
        param($sender, $eventArgs)
        # A click records exactly this button; only space advances the sequence.
        Write-ActionRecord -Name ([string]$sender.Tag) | Out-Null
    })
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $remove = $menu.Items.Add('从测试步骤中移除')
    $remove.Tag = $button
    $remove.Add_Click({
        param($sender, $eventArgs)
        $target = $sender.Tag
        $stepPanel.Controls.Remove($target)
        $target.Dispose()
        Sync-Steps
    })
    $button.ContextMenuStrip = $menu
    $stepPanel.Controls.Add($button)
    return $button
}

function Remove-StepsForName {
    param([string]$Name, [switch]$NoSave)
    foreach ($button in @($stepPanel.Controls)) {
        if ([string]$button.Tag -eq $Name) {
            $stepPanel.Controls.Remove($button)
            $button.Dispose()
        }
    }
    Sync-Steps -NoSave:$NoSave
}

$stepPanel.Add_DragEnter($stepDragOver)
$stepPanel.Add_DragOver($stepDragOver)
$stepPanel.Add_DragDrop($stepDrop)
$restartButton.Add_Click({ Reset-StepProgress })
$redoRoundButton.Add_Click({
    if ($stepPanel.Controls.Count -eq 0) { return }
    Reset-StepProgress -Round $script:currentRound
})
$nextRoundButton.Add_Click({
    if ($stepPanel.Controls.Count -eq 0) { return }
    Reset-StepProgress -Round ($script:currentRound + 1)
})
$clearStepsButton.Add_Click({
    while ($stepPanel.Controls.Count -gt 0) {
        $stepPanel.Controls[0].Dispose()
    }
    Sync-Steps
    $restartButton.Focus() | Out-Null
})
$spaceFilter = New-Object RecorderSpaceFilter
$spaceFilter.Owner = $form
$spaceFilter.NameInput = $nameInput
$spaceFilter.Add_SpacePressed({ Invoke-NextStep })
[System.Windows.Forms.Application]::AddMessageFilter($spaceFilter)
$form.Add_FormClosed({ [System.Windows.Forms.Application]::RemoveMessageFilter($spaceFilter) })
