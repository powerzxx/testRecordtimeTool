function New-RecorderInputDialog {
    param(
        [string]$Prompt,
        [string]$Title,
        [string]$DefaultText = '',
        [Windows.Forms.Form]$Owner = $form
    )
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $Title
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MinimizeBox = $false; $dialog.MaximizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.AutoScaleMode = 'Dpi'
    $dialog.Font = $Owner.Font
    $dialog.ClientSize = New-Object Drawing.Size(450, 155)
    # An owned modal window stays above its owner, including when it is topmost.
    $dialog.Owner = $Owner
    $dialog.TopMost = $Owner.TopMost

    $layout = New-Object Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'; $layout.Padding = New-Object Windows.Forms.Padding(14)
    $layout.ColumnCount = 1; $layout.RowCount = 3
    $layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 30))) | Out-Null
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 38))) | Out-Null
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100))) | Out-Null
    $dialog.Controls.Add($layout)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Prompt; $label.Dock = 'Fill'; $label.TextAlign = 'MiddleLeft'
    $layout.Controls.Add($label, 0, 0)
    $input = New-Object Windows.Forms.TextBox
    $input.Name = 'DialogInput'; $input.Dock = 'Fill'; $input.Text = $DefaultText
    $layout.Controls.Add($input, 0, 1)
    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Fill'; $buttons.FlowDirection = 'RightToLeft'
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'; $cancel.DialogResult = 'Cancel'; $cancel.AutoSize = $true
    $ok = New-Object Windows.Forms.Button
    $ok.Text = '确定'; $ok.DialogResult = 'OK'; $ok.AutoSize = $true
    $buttons.Controls.AddRange(@($cancel, $ok))
    $layout.Controls.Add($buttons, 0, 2)
    $dialog.AcceptButton = $ok; $dialog.CancelButton = $cancel
    $dialog.ActiveControl = $input
    $input.SelectAll()
    return $dialog
}

function Show-RecorderInputDialog {
    param(
        [string]$Prompt,
        [string]$Title,
        [string]$DefaultText = '',
        [Windows.Forms.Form]$Owner = $form
    )
    $dialog = New-RecorderInputDialog -Prompt $Prompt -Title $Title -DefaultText $DefaultText -Owner $Owner
    try {
        if ((Show-RecorderModalDialog -Dialog $dialog -Owner $Owner) -eq [Windows.Forms.DialogResult]::OK) {
            return $dialog.Controls.Find('DialogInput', $true)[0].Text
        }
        return ''
    }
    finally { $dialog.Dispose() }
}
