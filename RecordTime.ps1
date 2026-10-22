Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -Path (Join-Path $PSScriptRoot 'SequenceControls.cs') -ReferencedAssemblies @('System.Windows.Forms.dll', 'System.Drawing.dll', 'System.dll')
Add-Type -Path (Join-Path $PSScriptRoot 'RecycleBackup.cs')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RecorderDpi {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDPIAware();
}
'@ -ReferencedAssemblies @('System.Windows.Forms.dll', 'System.dll', 'System.Core.dll')

try {
    if (-not [RecorderDpi]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
        [RecorderDpi]::SetProcessDPIAware() | Out-Null
    }
}
catch [System.EntryPointNotFoundException] {
    [RecorderDpi]::SetProcessDPIAware() | Out-Null
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:settingsDirectory = Join-Path $env:APPDATA 'EarphoneLogTimeRecorder'
$script:settingsPath = Join-Path $script:settingsDirectory 'buttons.json'
$script:buttonNames = @()
$script:stepNames = @()
$script:stepOrder = @()
$script:pendingSteps = @()
$script:completedSteps = @()
$script:roundStarted = $false
$script:nextStep = 0
$script:currentRound = 1
$script:activeLogPath = $null
$script:visibleLogStartIndex = 0
$script:undoDeletedRecord = $null

if (Test-Path -LiteralPath $script:settingsPath) {
    try {
        $savedNames = Get-Content -LiteralPath $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $savedNames -and $savedNames.PSObject.Properties.Name -contains 'Buttons') {
            $script:buttonNames = @($savedNames.Buttons | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) })
            $script:stepNames = @($savedNames.Steps | Where-Object { $_ -is [string] -and $_ -in $script:buttonNames })
        }
        else {
            $script:buttonNames = @($savedNames | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) })
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "读取已保存的按钮配置失败：$($_.Exception.Message)",
            '按钮配置错误',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = '耳机 Log 时间记录'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1060, 720)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 580)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.KeyPreview = $true

$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$mainLayout.Dock = 'Fill'
$mainLayout.ColumnCount = 1
$mainLayout.RowCount = 2
$mainLayout.Padding = New-Object System.Windows.Forms.Padding(10)
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30))) | Out-Null
$form.Controls.Add($mainLayout)

$areaSplit = New-Object System.Windows.Forms.SplitContainer
$areaSplit.Size = New-Object System.Drawing.Size(1000, 620)
$areaSplit.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$areaSplit.Dock = 'Fill'
$areaSplit.Margin = New-Object System.Windows.Forms.Padding(0)
$areaSplit.SplitterWidth = 8
$areaSplit.SplitterDistance = 284
$areaSplit.Panel1MinSize = 220
$areaSplit.Panel2MinSize = 100
$areaSplit.FixedPanel = [System.Windows.Forms.FixedPanel]::None
$areaSplit.BackColor = [System.Drawing.Color]::Silver
$areaSplit.Panel1.BackColor = $form.BackColor
$areaSplit.Panel2.BackColor = $form.BackColor
$areaSplit.AccessibleName = '测试区与记录区分隔线'
$areaSplit.AccessibleDescription = '上下拖动分隔线，调整测试区和记录区的高度'
$mainLayout.Controls.Add($areaSplit, 0, 0)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 2
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 73))) | Out-Null
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 27))) | Out-Null
$layout.RowCount = 4
$layout.Padding = New-Object System.Windows.Forms.Padding(0)
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 88))) | Out-Null
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 32))) | Out-Null
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28))) | Out-Null
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$areaSplit.Panel1.Controls.Add($layout)

$toolbar = New-Object System.Windows.Forms.TableLayoutPanel
$toolbar.Dock = 'Fill'
$toolbar.ColumnCount = 1
$toolbar.RowCount = 2
$toolbar.Margin = New-Object System.Windows.Forms.Padding(0)
$toolbar.Padding = New-Object System.Windows.Forms.Padding(0)
$toolbar.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42))) | Out-Null
$toolbar.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42))) | Out-Null

$buttonToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonToolbar.Dock = 'Fill'
$buttonToolbar.WrapContents = $false
$buttonToolbar.AutoScroll = $true
$buttonToolbar.Margin = New-Object System.Windows.Forms.Padding(0)
$buttonToolbar.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)

$fileToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$fileToolbar.Dock = 'Fill'
$fileToolbar.WrapContents = $false
$fileToolbar.AutoScroll = $true
$fileToolbar.Margin = New-Object System.Windows.Forms.Padding(0)
$fileToolbar.Padding = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)

$nameLabel = New-Object System.Windows.Forms.Label
$nameLabel.Text = '按钮名称'
$nameLabel.AutoSize = $true
$nameLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 6, 0)

$nameInput = New-Object System.Windows.Forms.TextBox
$nameInput.Width = 180
$nameInput.Margin = New-Object System.Windows.Forms.Padding(0, 3, 8, 0)
$inputHint = New-Object System.Windows.Forms.ToolTip
$inputHint.SetToolTip($nameInput, 'Enter 添加；Esc 或点击空白处返回测试，随后按空格记录。')

$addButton = New-Object System.Windows.Forms.Button
$addButton.Text = '添加按钮'
$addButton.AutoSize = $true
$addButton.Height = 30
$addButton.Margin = New-Object System.Windows.Forms.Padding(0, 1, 8, 0)

$saveConfigButton = New-Object System.Windows.Forms.Button
$saveConfigButton.Text = '保存按钮配置'
$saveConfigButton.AutoSize = $true
$saveConfigButton.Height = 30
$saveConfigButton.Enabled = $false
$saveConfigButton.Margin = New-Object System.Windows.Forms.Padding(0, 1, 8, 0)

$clearConfigButton = New-Object System.Windows.Forms.Button
$clearConfigButton.Text = '清空当前配置'
$clearConfigButton.AutoSize = $true
$clearConfigButton.Height = 30
$clearConfigButton.ForeColor = [System.Drawing.Color]::Firebrick
$clearConfigButton.Enabled = $script:buttonNames.Count -gt 0
$clearConfigButton.AccessibleDescription = '移除当前方案的按钮和测试步骤，其他方案及已有记录不受影响'
$clearConfigButton.Margin = New-Object System.Windows.Forms.Padding(0, 1, 8, 0)

$configStatusLabel = New-Object System.Windows.Forms.Label
$configStatusLabel.Text = if ($script:buttonNames.Count -gt 0) { '已载入已保存的按钮配置' } else { '当前没有已保存配置' }
$configStatusLabel.AutoSize = $true
$configStatusLabel.Margin = New-Object System.Windows.Forms.Padding(4, 8, 8, 0)

$statusToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$statusToolbar.Dock = 'Fill'
$statusToolbar.WrapContents = $false
$statusToolbar.Margin = New-Object System.Windows.Forms.Padding(0)
$statusToolbar.Padding = New-Object System.Windows.Forms.Padding(0)

$undoDeleteButton = New-Object System.Windows.Forms.Button
$undoDeleteButton.Text = '撤销删除'
$undoDeleteButton.AutoSize = $true
$undoDeleteButton.Height = 26
$undoDeleteButton.Visible = $false
$undoDeleteButton.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
$statusToolbar.Controls.AddRange(@($configStatusLabel, $undoDeleteButton))

$undoDeleteTimer = New-Object System.Windows.Forms.Timer
$undoDeleteTimer.Interval = 5000

$selectFileButton = New-Object System.Windows.Forms.Button
$selectFileButton.Text = '打开记录文件'
$selectFileButton.AutoSize = $true
$selectFileButton.Height = 30
$selectFileButton.Margin = New-Object System.Windows.Forms.Padding(0, 1, 0, 0)

$newFileButton = New-Object System.Windows.Forms.Button
$newFileButton.Text = '新建记录文件'
$newFileButton.AutoSize = $true
$newFileButton.Height = 30
$newFileButton.Margin = New-Object System.Windows.Forms.Padding(0, 1, 8, 0)

$clearRecordsButton = New-Object System.Windows.Forms.Button
$clearRecordsButton.Text = '清空记录'
$clearRecordsButton.AutoSize = $true
$clearRecordsButton.Height = 30
$clearRecordsButton.ForeColor = [System.Drawing.Color]::Firebrick
$clearRecordsButton.Enabled = $false
$clearRecordsButton.AccessibleDescription = '确认后将带时间的 txt 备份送入回收站，成功后清空当前记录，保留文件继续使用'
$clearRecordsButton.Margin = New-Object System.Windows.Forms.Padding(0, 1, 8, 0)

$topMostToggle = New-Object System.Windows.Forms.CheckBox
$topMostToggle.Text = '窗口置顶'
$topMostToggle.AutoSize = $true
$topMostToggle.Margin = New-Object System.Windows.Forms.Padding(4, 8, 8, 0)

$soundToggle = New-Object System.Windows.Forms.CheckBox
$soundToggle.Text = '记录时提示音'
$soundToggle.AutoSize = $true
$soundToggle.Margin = New-Object System.Windows.Forms.Padding(4, 8, 0, 0)

$buttonToolbar.Controls.AddRange(@($nameLabel, $nameInput, $addButton, $saveConfigButton, $clearConfigButton))
$fileToolbar.Controls.AddRange(@($selectFileButton, $newFileButton, $clearRecordsButton, $topMostToggle, $soundToggle))
$toolbar.Controls.Add($buttonToolbar, 0, 0)
$toolbar.Controls.Add($fileToolbar, 0, 1)
$layout.Controls.Add($toolbar, 0, 0)

$fileLabel = New-Object System.Windows.Forms.Label
$fileLabel.Text = '请先打开已有记录文件，或新建一个记录文件'
$fileLabel.Dock = 'Fill'
$fileLabel.AutoEllipsis = $true
$fileLabel.TextAlign = 'MiddleLeft'
$layout.Controls.Add($fileLabel, 0, 1)

$configStatusLabel.AutoEllipsis = $true
$configStatusLabel.TextAlign = 'MiddleLeft'
$configStatusLabel.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$layout.Controls.Add($statusToolbar, 0, 2)

$actionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$actionPanel.Dock = 'Fill'
$actionPanel.AutoScroll = $true
$actionPanel.WrapContents = $true
$actionPanel.Padding = New-Object System.Windows.Forms.Padding(2, 8, 2, 2)
$layout.Controls.Add($actionPanel, 0, 3)

$stepGroup = New-Object System.Windows.Forms.GroupBox
$stepGroup.Text = '测试步骤（上下拖动排序）'
$stepGroup.Dock = 'Fill'
$layout.Controls.Add($stepGroup, 1, 0)
$layout.SetRowSpan($stepGroup, 4)
$stepPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$stepPanel.Dock = 'Fill'
$stepPanel.AutoScroll = $true
$stepPanel.FlowDirection = 'TopDown'
$stepPanel.WrapContents = $false
$stepPanel.AllowDrop = $true
$stepPanel.BackColor = [System.Drawing.Color]::AliceBlue
$stepFooter = New-Object System.Windows.Forms.TableLayoutPanel
$stepFooter.Dock = 'Bottom'
$stepFooter.Height = 100
$stepFooter.ColumnCount = 2
$stepFooter.RowCount = 3
$stepFooter.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
$stepFooter.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
$stepFooter.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28))) | Out-Null
$stepFooter.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
$stepFooter.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
$restartButton = New-Object System.Windows.Forms.Button
$restartButton.Text = '全部重来'
$restartButton.AccessibleDescription = '回到第 1 轮、第 1 步，保留已有记录'
$restartButton.Dock = 'Fill'
$restartButton.Width = 96
$redoRoundButton = New-Object System.Windows.Forms.Button
$redoRoundButton.Text = '重做本轮'
$redoRoundButton.Dock = 'Fill'
$redoRoundButton.AccessibleDescription = '保留当前轮次，回到第 1 步，等待按空格记录；保留已有记录'
$nextRoundButton = New-Object System.Windows.Forms.Button
$nextRoundButton.Text = '开始下一轮'
$nextRoundButton.Dock = 'Fill'
$nextRoundButton.AccessibleDescription = '轮次加 1，回到第 1 步，等待按空格记录'
$clearStepsButton = New-Object System.Windows.Forms.Button
$clearStepsButton.Text = '清空步骤'
$clearStepsButton.Dock = 'Fill'
$clearStepsButton.Width = 96
$clearStepsButton.ForeColor = [System.Drawing.Color]::Firebrick
$stepStatus = New-Object System.Windows.Forms.Label
$stepStatus.Dock = 'Fill'
$stepStatus.TextAlign = 'MiddleLeft'
$stepStatus.AutoEllipsis = $true
$stepFooter.Controls.Add($stepStatus, 0, 0)
$stepFooter.SetColumnSpan($stepStatus, 2)
$stepFooter.Controls.Add($redoRoundButton, 0, 1)
$stepFooter.Controls.Add($nextRoundButton, 1, 1)
$stepFooter.Controls.Add($restartButton, 0, 2)
$stepFooter.Controls.Add($clearStepsButton, 1, 2)
$stepGroup.Controls.AddRange(@($stepPanel, $stepFooter))

$recordsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$recordsPanel.Dock = 'Fill'
$recordsPanel.FlowDirection = 'TopDown'
$recordsPanel.WrapContents = $false
$recordsPanel.AutoScroll = $true
$recordsPanel.Padding = New-Object System.Windows.Forms.Padding(4)
$recordsPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$recordsPanel.BackColor = [System.Drawing.Color]::White
$areaSplit.Panel2.Controls.Add($recordsPanel)


. (Join-Path $PSScriptRoot 'Sequence.ps1')
. (Join-Path $PSScriptRoot 'Dialogs.ps1')
. (Join-Path $PSScriptRoot 'WindowActivation.ps1')
. (Join-Path $PSScriptRoot 'WindowLayout.ps1')
. (Join-Path $PSScriptRoot 'Workflow.ps1')
. (Join-Path $PSScriptRoot 'RecordBackup.ps1')
. (Join-Path $PSScriptRoot 'UserGuide.ps1')
. (Join-Path $PSScriptRoot 'LayoutThemes.ps1')

function Sync-RecordRowWidths {
    $rowWidth = [Math]::Max(100, $recordsPanel.ClientSize.Width - $recordsPanel.Padding.Horizontal - 24)
    foreach ($row in $recordsPanel.Controls) {
        $row.Width = $rowWidth
    }
}

$recordsPanel.Add_SizeChanged({ Sync-RecordRowWidths })

function Clear-UndoDelete {
    $undoDeleteTimer.Stop()
    $script:undoDeletedRecord = $null
    $undoDeleteButton.Visible = $false
}

$undoDeleteTimer.Add_Tick({
    Clear-UndoDelete
    $configStatusLabel.Text = '撤销时间已过'
})

$undoDeleteButton.Add_Click({
    if ($null -eq $script:undoDeletedRecord) {
        return
    }

    $deleted = $script:undoDeletedRecord
    try {
        $currentLines = [System.IO.File]::ReadAllLines($deleted.Path, [System.Text.Encoding]::UTF8)
        $expectedLines = [string[]]$deleted.ExpectedLines
        $matchesExpected = $currentLines.Length -eq $expectedLines.Length
        if ($matchesExpected) {
            for ($lineIndex = 0; $lineIndex -lt $currentLines.Length; $lineIndex++) {
                if ($currentLines[$lineIndex] -ne $expectedLines[$lineIndex]) {
                    $matchesExpected = $false
                    break
                }
            }
        }
        if (-not $matchesExpected) {
            Clear-UndoSpace
        Clear-UndoDelete
            [System.Windows.Forms.MessageBox]::Show($form,
                '记录文件在删除后又发生了变化，无法安全撤销。',
                '无法撤销删除',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        $restoredLines = New-Object 'System.Collections.Generic.List[string]'
        for ($lineIndex = 0; $lineIndex -le $currentLines.Length; $lineIndex++) {
            if ($lineIndex -eq $deleted.Index) {
                $restoredLines.Add([string]$deleted.Line)
            }
            if ($lineIndex -lt $currentLines.Length) {
                $restoredLines.Add($currentLines[$lineIndex])
            }
        }
        [System.IO.File]::WriteAllLines(
            $deleted.Path,
            $restoredLines.ToArray(),
            (New-Object System.Text.UTF8Encoding($false))
        )
        Clear-UndoSpace
        Clear-UndoDelete
        $script:visibleLogStartIndex = 0
        Load-LogRows -Lines $restoredLines.ToArray()
        $configStatusLabel.Text = '已撤销删除，记录已恢复'
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($form,
            "撤销删除失败：$($_.Exception.Message)",
            '撤销失败',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

function Save-EditedRecord {
    param(
        [System.Windows.Forms.Panel]$Row,
        [string]$Text
    )

    $match = [regex]::Match($Text, '^(\d{2}:\d{2}:\d{2}(?:\.\d{3})?)\s+(.+)$')
    $parsedTime = [DateTime]::MinValue
    $timeIsValid = $match.Success -and [DateTime]::TryParseExact(
        $match.Groups[1].Value,
        $(if ($match.Groups[1].Value.Contains('.')) { 'HH:mm:ss.fff' } else { 'HH:mm:ss' }),
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsedTime
    )
    if (-not $timeIsValid -or $match.Groups[2].Value.Contains("`r") -or $match.Groups[2].Value.Contains("`n")) {
        [System.Windows.Forms.MessageBox]::Show($form,
            '请使用 HH:mm:ss 内容 或 HH:mm:ss.fff 内容 格式，并确保内容在同一行。',
            '记录格式不正确',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($script:activeLogPath)) {
        return $false
    }

    $rowIndex = $recordsPanel.Controls.GetChildIndex($Row)
    $fileIndex = $script:visibleLogStartIndex + $rowIndex
    try {
        $fileLines = [System.IO.File]::ReadAllLines($script:activeLogPath, [System.Text.Encoding]::UTF8)
        if (
            $fileLines.Length -ne ($script:visibleLogStartIndex + $recordsPanel.Controls.Count) -or
            $rowIndex -lt 0 -or
            $fileIndex -ge $fileLines.Length -or
            $fileLines[$fileIndex] -ne [string]$Row.Tag
        ) {
            $script:visibleLogStartIndex = 0
            Load-LogRows -Lines $fileLines
            [System.Windows.Forms.MessageBox]::Show($form,
                '记录文件内容已发生变化，已重新载入。请再次选择要修改的记录。',
                '记录已更新',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return $false
        }

        $updatedText = $Text.Trim()
        $fileLines[$fileIndex] = $updatedText
        [System.IO.File]::WriteAllLines(
            $script:activeLogPath,
            $fileLines,
            (New-Object System.Text.UTF8Encoding($false))
        )
        Clear-UndoSpace
        Clear-UndoDelete
        $Row.Tag = $updatedText
        $Row.Controls['RecordText'].Text = $updatedText
        $Row.Controls['RecordText'].Visible = $true
        $Row.Controls['RecordEditInput'].Visible = $false
        $Row.Controls['EditRecordButton'].Text = '编辑'
        $Row.Controls['CancelRecordEditButton'].Visible = $false
        $Row.Controls['RemoveRecordButton'].Visible = $true
        $Row.AccessibleDescription = ''
        $Row.BackColor = [System.Drawing.Color]::LightGoldenrodYellow
        $Row.Controls['RecordText'].BackColor = [System.Drawing.Color]::LightGoldenrodYellow
        foreach ($otherRow in $recordsPanel.Controls) {
            if (-not [object]::ReferenceEquals($otherRow, $Row)) {
                $otherRow.BackColor = [System.Drawing.Color]::White
                $otherRow.Controls['RecordText'].BackColor = [System.Drawing.Color]::White
            }
        }
        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($form,
            "修改这条记录失败：$($_.Exception.Message)",
            '修改记录失败',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }
}

function Add-LogRow {
    param(
        [string]$Text,
        [bool]$Highlight = $false
    )

    $row = New-Object System.Windows.Forms.TableLayoutPanel
    $row.ColumnCount = 5
    $row.RowCount = 1
    $row.Padding = New-Object System.Windows.Forms.Padding(0)
    $row.Height = 32
    $row.Width = [Math]::Max(100, $recordsPanel.ClientSize.Width - $recordsPanel.Padding.Horizontal - 24)
    $row.Margin = New-Object System.Windows.Forms.Padding(0)
    $row.Tag = $Text
    $row.BackColor = [Drawing.Color]::White
    $row.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
    $row.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 76))) | Out-Null
    $row.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 76))) | Out-Null
    $row.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
    $row.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90))) | Out-Null
    $row.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
    if ($Highlight) {
        $row.BackColor = [System.Drawing.Color]::LightGoldenrodYellow
    }

    $recordLabel = New-Object System.Windows.Forms.Label
    $recordLabel.Name = 'RecordText'
    $recordLabel.Text = $Text
    $recordLabel.Dock = 'Fill'
    $recordLabel.AutoEllipsis = $true
    $recordLabel.TextAlign = 'MiddleLeft'
    $recordLabel.Padding = New-Object System.Windows.Forms.Padding(2, 0, 4, 0)
    $recordLabel.Font = New-Object System.Drawing.Font('Consolas', 11)
    $recordLabel.BackColor = $row.BackColor

    $recordInput = New-Object System.Windows.Forms.TextBox
    $recordInput.Name = 'RecordEditInput'
    $recordInput.Dock = 'Fill'
    $recordInput.Font = New-Object System.Drawing.Font('Consolas', 11)
    $recordInput.Visible = $false

    $editButton = New-Object System.Windows.Forms.Button
    $editButton.Name = 'EditRecordButton'
    $editButton.Text = '编辑'
    $editButton.Dock = 'Fill'
    $editButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $editButton.FlatAppearance.BorderSize = 1
    $editButton.ForeColor = [System.Drawing.Color]::DarkSlateBlue
    $editButton.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $editButton.Visible = $false
    if ($Text -match '^--- 第 \d+ 轮 ---$') {
        $editButton.Enabled = $false
        $recordLabel.ForeColor = [System.Drawing.Color]::SteelBlue
    }
    elseif ($Text -match '\[异常\]') { $recordLabel.ForeColor = [System.Drawing.Color]::Firebrick }

    $cancelEditButton = New-Object System.Windows.Forms.Button
    $cancelEditButton.Name = 'CancelRecordEditButton'
    $cancelEditButton.Text = '取消'
    $cancelEditButton.Dock = 'Fill'
    $cancelEditButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $cancelEditButton.ForeColor = [System.Drawing.Color]::DimGray
    $cancelEditButton.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $cancelEditButton.Visible = $false

    $removeButton = New-Object System.Windows.Forms.Button
    $removeButton.Name = 'RemoveRecordButton'
    $removeButton.Text = '删除'
    $removeButton.Dock = 'Fill'
    $removeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $removeButton.ForeColor = [System.Drawing.Color]::Firebrick
    $removeButton.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $removeButton.Visible = $false

    $row.Controls.Add($recordLabel, 0, 0)
    $row.Controls.Add($recordInput, 0, 0)
    $row.Controls.Add($editButton, 1, 0)
    $row.Controls.Add($cancelEditButton, 2, 0)
    $row.Controls.Add($removeButton, 4, 0)

    $showRowActions = {
        param($sender, $eventArgs)
        if ($row.AccessibleDescription -ne 'Editing') {
            $editButton.Visible = $true
            $removeButton.Visible = $true
        }
    }.GetNewClosure()
    $hideRowActions = {
        param($sender, $eventArgs)
        $cursor = $row.PointToClient([System.Windows.Forms.Cursor]::Position)
        if (-not $row.ClientRectangle.Contains($cursor)) {
            if ($row.AccessibleDescription -ne 'Editing') {
                $editButton.Visible = $false
                $removeButton.Visible = $false
            }
        }
    }.GetNewClosure()

    foreach ($control in @($row, $recordLabel, $recordInput, $editButton, $cancelEditButton, $removeButton)) {
        $control.Add_MouseEnter($showRowActions)
        $control.Add_MouseLeave($hideRowActions)
    }

    $editButton.Tag = $row
    $editButton.Add_Click({
        param($sender, $eventArgs)
        $targetRow = $sender.Tag
        if ($targetRow.AccessibleDescription -eq 'Editing') {
            Save-EditedRecord -Row $targetRow -Text $targetRow.Controls['RecordEditInput'].Text | Out-Null
            return
        }

        $targetRow.AccessibleDescription = 'Editing'
        $targetRow.Controls['RecordText'].Visible = $false
        $targetRow.Controls['RecordEditInput'].Text = [string]$targetRow.Tag
        $targetRow.Controls['RecordEditInput'].Visible = $true
        $targetRow.Controls['RemoveRecordButton'].Visible = $false
        $targetRow.Controls['CancelRecordEditButton'].Visible = $true
        $targetRow.Controls['EditRecordButton'].Text = '保存'
        $targetRow.Controls['RecordEditInput'].Focus()
        $targetRow.Controls['RecordEditInput'].SelectAll()
    })

    $cancelEditButton.Tag = $row
    $cancelEditButton.Add_Click({
        param($sender, $eventArgs)
        $targetRow = $sender.Tag
        $targetRow.Controls['RecordEditInput'].Text = [string]$targetRow.Tag
        $targetRow.Controls['RecordEditInput'].Visible = $false
        $targetRow.Controls['RecordText'].Visible = $true
        $targetRow.Controls['EditRecordButton'].Text = '编辑'
        $targetRow.Controls['CancelRecordEditButton'].Visible = $false
        $targetRow.Controls['RemoveRecordButton'].Visible = $true
        $targetRow.AccessibleDescription = ''
    })

    $recordInput.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $eventArgs.SuppressKeyPress = $true
            $targetRow = $sender.Parent
            Save-EditedRecord -Row $targetRow -Text $sender.Text | Out-Null
        }
        elseif ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $sender.Parent.Controls['CancelRecordEditButton'].PerformClick()
        }
    })

    $removeButton.Tag = $row
    $removeButton.Add_Click({
        param($sender, $eventArgs)
        $targetRow = $sender.Tag
        if ([string]::IsNullOrWhiteSpace($script:activeLogPath)) {
            return
        }

        $rowIndex = $recordsPanel.Controls.GetChildIndex($targetRow)
        $fileIndex = $script:visibleLogStartIndex + $rowIndex
        try {
            $fileLines = [System.IO.File]::ReadAllLines($script:activeLogPath, [System.Text.Encoding]::UTF8)
            if (
                $fileLines.Length -ne ($script:visibleLogStartIndex + $recordsPanel.Controls.Count) -or
                $rowIndex -lt 0 -or
                $fileIndex -ge $fileLines.Length -or
                $fileLines[$fileIndex] -ne [string]$targetRow.Tag
            ) {
                $script:visibleLogStartIndex = 0
                Load-LogRows -Lines $fileLines
                [System.Windows.Forms.MessageBox]::Show($form,
                    '记录文件内容已发生变化，已重新载入。请再次选择要删除的记录。',
                    '记录已更新',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                return
            }

            $remainingLines = New-Object 'System.Collections.Generic.List[string]'
            for ($lineIndex = 0; $lineIndex -lt $fileLines.Length; $lineIndex++) {
                if ($lineIndex -ne $fileIndex) {
                    $remainingLines.Add($fileLines[$lineIndex])
                }
            }
            [System.IO.File]::WriteAllLines(
                $script:activeLogPath,
                $remainingLines.ToArray(),
                (New-Object System.Text.UTF8Encoding($false))
            )
            Clear-UndoSpace
        Clear-UndoDelete
            $script:undoDeletedRecord = @{
                Path = $script:activeLogPath
                Line = [string]$targetRow.Tag
                Index = $fileIndex
                ExpectedLines = $remainingLines.ToArray()
            }
            $undoDeleteButton.Visible = $true
            $undoDeleteTimer.Start()
            $configStatusLabel.Text = '记录已删除；可在 5 秒内撤销'
            $recordsPanel.Controls.Remove($targetRow)
            $targetRow.Dispose()
            Sync-RecordRowWidths
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form,
                "删除这条记录失败：$($_.Exception.Message)",
                '删除记录失败',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $recordsPanel.Controls.Add($row)
    Sync-RecordRowWidths
    $recordsPanel.ScrollControlIntoView($row)
}

function Load-LogRows {
    param([string[]]$Lines)

    $script:visibleLogStartIndex = 0
    $recordsPanel.SuspendLayout()
    try {
        while ($recordsPanel.Controls.Count -gt 0) {
            $row = $recordsPanel.Controls[0]
            $recordsPanel.Controls.RemoveAt(0)
            $row.Dispose()
        }
        foreach ($line in $Lines) {
            Add-LogRow -Text $line
        }
    }
    finally {
        $recordsPanel.ResumeLayout($true)
    }
    if ($recordsPanel.Controls.Count -gt 0) {
        $recordsPanel.Controls[$recordsPanel.Controls.Count - 1].BackColor = [System.Drawing.Color]::LightGoldenrodYellow
        $recordsPanel.Controls[$recordsPanel.Controls.Count - 1].Controls['RecordText'].BackColor = [System.Drawing.Color]::LightGoldenrodYellow
    }
}

function Set-ConfigDirty {
    $saveConfigButton.Enabled = $true
    $clearConfigButton.Enabled = $actionPanel.Controls.Count -gt 0
    try {
        Save-ButtonConfig
        $configStatusLabel.Text = '配置已自动保存'
    }
    catch {
        $configStatusLabel.Text = '自动保存失败；请点击“保存按钮配置”重试'
        [System.Windows.Forms.MessageBox]::Show($form,
            "配置自动保存失败：$($_.Exception.Message)`r`n当前更改仍在界面中，请点击【保存按钮配置】重试。",
            '自动保存失败',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
}

function Save-ButtonConfig {
    if (-not (Test-Path -LiteralPath $script:settingsDirectory)) {
        New-Item -ItemType Directory -Path $script:settingsDirectory -Force | Out-Null
    }

    $configuration = Get-ButtonConfiguration
    $json = ConvertTo-Json -InputObject $configuration -Depth 6
    Write-RecorderSettings -Path $script:settingsPath -Json $json
    $script:profiles = $configuration.Profiles
    $saveConfigButton.Enabled = $false
    $configStatusLabel.Text = '按钮配置已保存'
}

function Write-ActionRecord {
    param([string]$Name, [datetime]$Timestamp = (Get-Date), [int]$RoundNumber = $script:currentRound, [hashtable]$Snapshot)
    return (Write-WorkflowRecord -Name $Name -Timestamp $Timestamp -RoundNumber $RoundNumber -Snapshot $Snapshot)
}

function Add-ActionButton {
    param([string]$Name)

    $actionButton = New-Object RecorderDragButton
    $actionButton.Text = $Name
    $actionButton.Tag = $Name
    $actionButton.AutoSize = $true
    $actionButton.MinimumSize = New-Object System.Drawing.Size(100, 48)
    $actionButton.Margin = New-Object System.Windows.Forms.Padding(6)
    $actionButton.Enabled = $true

    $actionButton.Add_Click({
        param($sender, $eventArgs)
        Write-ActionRecord -Name ([string]$sender.Tag) | Out-Null
    })
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $moveUpItem = New-Object System.Windows.Forms.ToolStripMenuItem('上移按钮')
    $moveUpItem.Tag = $actionButton
    $moveUpItem.Add_Click({
        param($sender, $eventArgs)
        $target = $sender.Tag
        $index = $actionPanel.Controls.GetChildIndex($target)
        if ($index -gt 0) {
            $actionPanel.Controls.SetChildIndex($target, $index - 1)
            $script:buttonNames = @($actionPanel.Controls | ForEach-Object { [string]$_.Tag })
            Set-ConfigDirty
        }
    })

    $moveDownItem = New-Object System.Windows.Forms.ToolStripMenuItem('下移按钮')
    $moveDownItem.Tag = $actionButton
    $moveDownItem.Add_Click({
        param($sender, $eventArgs)
        $target = $sender.Tag
        $index = $actionPanel.Controls.GetChildIndex($target)
        if ($index -lt ($actionPanel.Controls.Count - 1)) {
            $actionPanel.Controls.SetChildIndex($target, $index + 1)
            $script:buttonNames = @($actionPanel.Controls | ForEach-Object { [string]$_.Tag })
            Set-ConfigDirty
        }
    })

    $renameItem = New-Object System.Windows.Forms.ToolStripMenuItem('重命名按钮')
    $renameItem.Tag = $actionButton
    $renameItem.Add_Click({
        param($sender, $eventArgs)
        $target = $sender.Tag
        $oldName = [string]$target.Tag
        $newName = (Show-RecorderInputDialog -Prompt '输入新的按钮名称：' -Title '重命名按钮' -DefaultText $oldName).Trim()
        if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq $oldName) {
            return
        }
        if (@($script:buttonNames | Where-Object { $_ -ne $oldName -and $_ -eq $newName }).Count -gt 0) {
            [System.Windows.Forms.MessageBox]::Show($form, '这个按钮名称已经存在。', '无法重命名') | Out-Null
            return
        }

        $index = [array]::IndexOf($script:buttonNames, $oldName)
        if ($index -ge 0) {
            $script:buttonNames[$index] = $newName
        }
        foreach ($step in $stepPanel.Controls) {
            if ([string]$step.Tag -eq $oldName) { $step.Tag = $newName }
        }
        $target.Text = $newName
        $target.Tag = $newName
        Sync-Steps
    })

    $deleteItem = New-Object System.Windows.Forms.ToolStripMenuItem('删除按钮')
    $deleteItem.Tag = $actionButton
    $deleteItem.Add_Click({
        param($sender, $eventArgs)
        $target = $sender.Tag
        $answer = [System.Windows.Forms.MessageBox]::Show($form,
            ('确定删除“' + [string]$target.Tag + '”按钮吗？已有记录不会受影响。'),
            '删除按钮',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }

        $script:buttonNames = @($script:buttonNames | Where-Object { $_ -ne [string]$target.Tag })
        Remove-StepsForName -Name ([string]$target.Tag) -NoSave
        $actionPanel.Controls.Remove($target)
        $target.Dispose()
        Set-ConfigDirty
    })
    $menu.Items.AddRange(@($moveUpItem, $moveDownItem, (New-Object System.Windows.Forms.ToolStripSeparator), $renameItem, $deleteItem))
    $actionButton.ContextMenuStrip = $menu
    $actionPanel.Controls.Add($actionButton)
}

function Select-LogFile {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Open', 'New')]
        [string]$Mode
    )

    if ($Mode -eq 'Open') {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = '打开记录文件'
        $dialog.Filter = '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*'
        $dialog.CheckFileExists = $true
        if (-not [string]::IsNullOrWhiteSpace($script:preferences.LastDirectory) -and (Test-Path -LiteralPath $script:preferences.LastDirectory -PathType Container)) { $dialog.InitialDirectory = $script:preferences.LastDirectory }
        if ((Show-RecorderModalDialog -Dialog $dialog) -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        $selectedPath = $dialog.FileName
        try {
            $existingLines = [System.IO.File]::ReadAllLines($selectedPath, [System.Text.Encoding]::UTF8)
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form,
                "读取记录文件失败：$($_.Exception.Message)",
                '无法打开文件',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }
    }
    else {
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Title = '新建记录文件'
        $dialog.Filter = '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*'
        $dialog.DefaultExt = 'txt'
        $dialog.AddExtension = $true
        $dialog.FileName = '耳机操作记录.txt'
        if (-not [string]::IsNullOrWhiteSpace($script:preferences.LastDirectory) -and (Test-Path -LiteralPath $script:preferences.LastDirectory -PathType Container)) { $dialog.InitialDirectory = $script:preferences.LastDirectory }
        if ((Show-RecorderModalDialog -Dialog $dialog) -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        $selectedPath = $dialog.FileName
        try {
            [System.IO.File]::WriteAllText($selectedPath, [string]::Empty, (New-Object System.Text.UTF8Encoding($false)))
            $existingLines = @()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form,
                "创建记录文件失败：$($_.Exception.Message)",
                '无法创建文件',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }
    }

    Reset-StepProgress
    $script:activeLogPath = $selectedPath
    $script:lastLoggedRound = $null
    $script:preferences.LastDirectory = [IO.Path]::GetDirectoryName($selectedPath)
    try { Save-WorkflowPreferences }
    catch { $configStatusLabel.Text = '记录文件已打开，但上次目录保存失败' }
    Clear-UndoDelete
    $fileLabel.Text = "当前文件：$selectedPath"
    Load-LogRows -Lines $existingLines
    $clearRecordsButton.Enabled = $true
    foreach ($control in $actionPanel.Controls) {
        $control.Enabled = $true
    }
}

foreach ($savedName in $script:buttonNames) {
    Add-ActionButton -Name $savedName
}

$addButton.Add_Click({
    $newName = $nameInput.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($newName)) {
        [System.Windows.Forms.MessageBox]::Show($form, '请先输入按钮名称。', '按钮名称不能为空') | Out-Null
        $nameInput.Focus()
        return
    }
    if (@($script:buttonNames | Where-Object { $_ -eq $newName }).Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show($form, '这个按钮名称已经存在。', '无法添加按钮') | Out-Null
        $nameInput.SelectAll()
        $nameInput.Focus()
        return
    }

    $script:buttonNames += $newName
    Add-ActionButton -Name $newName
    Set-ConfigDirty
    $nameInput.Clear()
    $nameInput.Focus()
})

$nameInput.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $eventArgs.Modifiers -eq [System.Windows.Forms.Keys]::None) {
        $eventArgs.SuppressKeyPress = $true
        $addButton.PerformClick()
    }
})

$script:saveConfigAction = {
    $script:buttonNames = @($actionPanel.Controls | ForEach-Object { [string]$_.Tag })
    try {
        Save-ButtonConfig
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($form,
            "保存按钮配置失败：$($_.Exception.Message)",
            '配置保存失败',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}
$saveConfigButton.Add_Click($script:saveConfigAction)

$script:clearConfigAction = {
    if ($actionPanel.Controls.Count -eq 0) {
        return
    }

    $answer = [System.Windows.Forms.MessageBox]::Show($form,
        '确定清空当前方案的所有按钮和测试步骤吗？此操作会立即保存；其他方案和已有记录不会受影响。',
        '清空当前配置',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $previousSteps = @($script:stepNames)
    $script:stepNames = @()
    $previousNames = @($script:buttonNames)
    $script:buttonNames = @()
    try {
        Save-ButtonConfig
    }
    catch {
        $script:stepNames = $previousSteps
        $script:buttonNames = $previousNames
        [System.Windows.Forms.MessageBox]::Show($form,
            "清空按钮配置失败：$($_.Exception.Message)",
            '清空失败',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    while ($stepPanel.Controls.Count -gt 0) { $stepPanel.Controls[0].Dispose() }
    Sync-Steps -NoSave
    while ($actionPanel.Controls.Count -gt 0) {
        $button = $actionPanel.Controls[0]
        $actionPanel.Controls.RemoveAt(0)
        $button.Dispose()
    }
    $saveConfigButton.Enabled = $false
    $clearConfigButton.Enabled = $false
    $configStatusLabel.Text = '按钮配置已清空并保存；已有记录文件不会受影响'
}
$clearConfigButton.Add_Click($script:clearConfigAction)

$script:selectFileAction = { Select-LogFile -Mode Open }
$script:newFileAction = { Select-LogFile -Mode New }
$selectFileButton.Add_Click($script:selectFileAction)
$newFileButton.Add_Click($script:newFileAction)
$script:clearRecordsAction = {
    try { Clear-LogWithBackup | Out-Null }
    catch {
        [Windows.Forms.MessageBox]::Show($form, "清空记录失败：$($_.Exception.Message)", '清空失败', 'OK', 'Error') | Out-Null
    }
}
$clearRecordsButton.Add_Click($script:clearRecordsAction)
$topMostToggle.Add_CheckedChanged({ Restore-RecorderTopMost })
$form.Add_Shown({
    $selectFileButton.Focus()
})

Initialize-Workflow
Initialize-RecorderWindowActivation
Initialize-LayoutThemes
foreach ($stepName in $script:stepNames) { Add-StepButton -Name $stepName | Out-Null }
Reset-StepProgress
Restore-WindowLayout
[System.Windows.Forms.Application]::Run($form)
