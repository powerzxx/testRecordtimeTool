# Store layout separately so moving the window never overwrites button settings.
$script:windowLayoutPath = Join-Path $script:settingsDirectory 'window.json'
$script:windowWasMaximized = $false
$script:splitRatio = 0.46

function Write-RecorderSettings {
    param([string]$Path, [string]$Json)
    $directory = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ([guid]::NewGuid().ToString() + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $Json, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Update-WindowLayoutState {
    if ($script:changingTheme -or $script:applyingThemeSplitters) { return }
    if ($form.WindowState -eq [Windows.Forms.FormWindowState]::Minimized) { return }
    $script:windowWasMaximized = $form.WindowState -eq [Windows.Forms.FormWindowState]::Maximized
    $available = $areaSplit.ClientSize.Height - $areaSplit.SplitterWidth
    if ($available -gt 0) { $script:splitRatio = $areaSplit.SplitterDistance / $available }
    if ($script:themeSplitters) {
        $script:themeSplitters[$script:currentTheme].SplitRatio = $script:splitRatio
        if ($script:currentTheme -eq 'Workbench') {
            $width = $workspaceSplit.ClientSize.Width - $workspaceSplit.SplitterWidth
            if ($width -gt 0) {
                $script:workspaceRatio = $workspaceSplit.SplitterDistance / $width
                $script:themeSplitters.Workbench.WorkspaceRatio = $script:workspaceRatio
            }
        }
    }
}

function Apply-SavedSplitter {
    $script:applyingThemeSplitters = $true
    try {
    if ($script:currentTheme -eq 'Workbench') {
        $width = $workspaceSplit.ClientSize.Width - $workspaceSplit.SplitterWidth
        $maximumWidth = $width - $workspaceSplit.Panel2MinSize
        if ($maximumWidth -ge $workspaceSplit.Panel1MinSize) {
            $workspaceSplit.SplitterDistance = [int][Math]::Max($workspaceSplit.Panel1MinSize, [Math]::Min($maximumWidth, [Math]::Round($width * $script:workspaceRatio)))
        }
    }
    $available = $areaSplit.ClientSize.Height - $areaSplit.SplitterWidth
    $maximum = $available - $areaSplit.Panel2MinSize
    if ($maximum -ge $areaSplit.Panel1MinSize) {
        $areaSplit.SplitterDistance = [int][Math]::Max($areaSplit.Panel1MinSize, [Math]::Min($maximum, [Math]::Round($available * $script:splitRatio)))
    }
    }
    finally { $script:applyingThemeSplitters = $false }
}

function Save-WindowLayout {
    Update-WindowLayoutState
    $bounds = if ($form.WindowState -eq [Windows.Forms.FormWindowState]::Normal) { $form.Bounds } else { $form.RestoreBounds }
    $json = @{ Version = 2; X = $bounds.X; Y = $bounds.Y; Width = $bounds.Width; Height = $bounds.Height; Maximized = $script:windowWasMaximized; SplitRatio = $script:splitRatio; Themes = $script:themeSplitters } | ConvertTo-Json -Depth 5
    Write-RecorderSettings -Path $script:windowLayoutPath -Json $json
}

function Restore-WindowLayout {
    if (-not [IO.File]::Exists($script:windowLayoutPath)) { return }
    try {
        $saved = [IO.File]::ReadAllText($script:windowLayoutPath) | ConvertFrom-Json
        foreach ($property in @('X', 'Y', 'Width', 'Height', 'SplitRatio', 'Maximized')) {
            if ($saved.PSObject.Properties.Name -notcontains $property) { throw 'Incomplete window layout' }
        }
        if ($saved.Width -le 0 -or $saved.Height -le 0 -or $saved.SplitRatio -le 0 -or $saved.SplitRatio -ge 1) { throw 'Invalid window layout' }
        $requested = New-Object Drawing.Rectangle([int]$saved.X, [int]$saved.Y, [int]$saved.Width, [int]$saved.Height)
        $workArea = [Windows.Forms.Screen]::FromRectangle($requested).WorkingArea
        $width = [Math]::Max($form.MinimumSize.Width, [Math]::Min($requested.Width, $workArea.Width))
        $height = [Math]::Max($form.MinimumSize.Height, [Math]::Min($requested.Height, $workArea.Height))
        $x = [Math]::Max($workArea.Left, [Math]::Min($requested.X, $workArea.Right - $width))
        $y = [Math]::Max($workArea.Top, [Math]::Min($requested.Y, $workArea.Bottom - $height))
        $form.StartPosition = 'Manual'
        $form.Bounds = New-Object Drawing.Rectangle($x, $y, $width, $height)
        $script:windowWasMaximized = $saved.Maximized -eq $true
        $form.WindowState = if ($script:windowWasMaximized) { 'Maximized' } else { 'Normal' }
        if ($saved.PSObject.Properties.Name -contains 'Themes') {
            foreach ($theme in @('Classic', 'Workbench')) {
                $value = $saved.Themes.$theme
                if ($value -and $value.SplitRatio -gt 0 -and $value.SplitRatio -lt 1) {
                    $script:themeSplitters[$theme].SplitRatio = [double]$value.SplitRatio
                }
                if ($theme -eq 'Workbench' -and $value.WorkspaceRatio -gt 0 -and $value.WorkspaceRatio -lt 1) {
                    $script:themeSplitters.Workbench.WorkspaceRatio = [double]$value.WorkspaceRatio
                }
            }
        }
        else { $script:themeSplitters.Classic.SplitRatio = [double]$saved.SplitRatio }
        $script:splitRatio = [double]$script:themeSplitters[$script:currentTheme].SplitRatio
        $script:workspaceRatio = [double]$script:themeSplitters.Workbench.WorkspaceRatio
        Apply-SavedSplitter
    }
    catch {
        $configStatusLabel.Text = '窗口布局读取失败，使用默认布局'
    }
}

$form.Add_Shown({
    Apply-SavedSplitter
    $areaSplit.Add_SplitterMoved({ Update-WindowLayoutState })
    $form.Add_ResizeEnd({ Update-WindowLayoutState })
    $form.Add_SizeChanged({
        if ($form.WindowState -ne [Windows.Forms.FormWindowState]::Minimized) {
            $script:windowWasMaximized = $form.WindowState -eq [Windows.Forms.FormWindowState]::Maximized
        }
    })
})
$form.Add_FormClosing({
    try { Save-WindowLayout }
    catch {
        [Windows.Forms.MessageBox]::Show($form, "窗口布局保存失败：$($_.Exception.Message)", '保存失败') | Out-Null
    }
})
