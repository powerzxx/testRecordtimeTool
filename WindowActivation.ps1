$script:recorderModalDepth = 0
$script:externalWindowPending = $false
$script:externalWindowAway = $false
$script:launchingExternalWindow = $false

function Update-RecorderTopMost {
    if (-not $form.IsDisposed) {
        $form.TopMost = $topMostToggle.Checked -and $script:recorderModalDepth -eq 0 -and -not $script:externalWindowPending
    }
}

function Restore-RecorderTopMost {
    $script:externalWindowPending = $false
    $script:externalWindowAway = $false
    Update-RecorderTopMost
}

function Update-RecorderWindowActivation {
    if (-not $script:externalWindowPending -or $script:launchingExternalWindow -or $script:recorderModalDepth -gt 0 -or $form.IsDisposed) { return }
    if ([RecorderForeground]::BelongsTo($form.Handle)) {
        if ($script:externalWindowAway) { Restore-RecorderTopMost }
    }
    elseif ([RecorderForeground]::GetForegroundWindow() -ne [intptr]::Zero) { $script:externalWindowAway = $true }
}

function Show-RecorderModalDialog {
    param([object]$Dialog, [Windows.Forms.Form]$Owner = $form)
    $script:recorderModalDepth++
    try {
        Update-RecorderTopMost
        if ($Dialog -is [Windows.Forms.Form]) { $Dialog.TopMost = $Owner.TopMost }
        return $Dialog.ShowDialog($Owner)
    }
    finally {
        $script:recorderModalDepth--
        Update-RecorderTopMost
    }
}

function Start-RecorderExternalApplication {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    [Diagnostics.Process]::Start($StartInfo) | Out-Null
}

function Open-RecorderExternalWindow {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    $previousPending = $script:externalWindowPending
    $previousAway = $script:externalWindowAway
    if ($topMostToggle.Checked) {
        $script:externalWindowPending = $true
        $script:externalWindowAway = $false
    }
    $script:launchingExternalWindow = $true
    try {
        Update-RecorderTopMost
        Start-RecorderExternalApplication -StartInfo $StartInfo
        # ShellExecute can reuse an existing editor or Explorer window and return
        # no process handle. Yield the main window instead of waiting on a PID.
        if ($script:externalWindowPending) { $form.SendToBack() }
    }
    catch {
        $script:externalWindowPending = $previousPending
        $script:externalWindowAway = $previousAway
        Update-RecorderTopMost
        throw
    }
    finally { $script:launchingExternalWindow = $false }
    Update-RecorderWindowActivation
}

function Initialize-RecorderWindowActivation {
    $form.Add_Activated({ Update-RecorderWindowActivation })
    $form.Add_Deactivate({
        if ($script:externalWindowPending -and -not $script:launchingExternalWindow -and $script:recorderModalDepth -eq 0) {
            $script:externalWindowAway = $true
        }
    })
    $spaceFilter.Add_InteractionReceived({
        if ($script:externalWindowPending -and -not $script:launchingExternalWindow -and $script:recorderModalDepth -eq 0) { Restore-RecorderTopMost }
    })
}
