$ErrorActionPreference = 'Stop'
$originalAppData = $env:APPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RecorderExternalTest-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$env:APPDATA = $testRoot
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Wait-ForWindowState([scriptblock]$Condition) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
        [Windows.Forms.Application]::DoEvents()
        if (& $Condition) { return }
        [Threading.Thread]::Sleep(20)
    } while ($watch.ElapsedMilliseconds -lt 30000)
    throw ('Window state did not settle at line ' + $MyInvocation.ScriptLineNumber + ': ' + $Condition.ToString() + '; foreground=' + [RecorderForeground]::GetForegroundWindow() + '; recorder=' + $form.Handle + '; topmost=' + $form.TopMost + '; pending=' + $script:externalWindowPending + '; away=' + $script:externalWindowAway)
}
try {
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RecordTime.ps1'))
    $source = $source.Replace('[System.Windows.Forms.Application]::Run($form)', '').Replace('$PSScriptRoot', "'" + $PSScriptRoot.Replace("'", "''") + "'")
    . ([scriptblock]::Create($source))
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RecorderExternalTestNative {
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string className, string title);
 public static IntPtr FindByTitle(string title) { return FindWindow(null, title); }
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
 [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr window, uint command);
 [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, IntPtr pid);
 [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint first, uint second, bool attach);
 [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr window);
 [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
 public static void FocusWindow(IntPtr window) {
  // The test runner is a background shell, so grant its UI thread access to
  // the foreground queue while arranging focus; always detach afterwards.
  uint current = GetCurrentThreadId();
  uint foreground = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
  uint target = GetWindowThreadProcessId(window, IntPtr.Zero);
  bool attachedForeground = current != foreground && AttachThreadInput(current, foreground, true);
  bool attachedTarget = current != target && target != foreground && AttachThreadInput(current, target, true);
  try { ShowWindow(window, 5); BringWindowToTop(window); SetForegroundWindow(window); }
  finally {
   if (attachedTarget) AttachThreadInput(current, target, false);
   if (attachedForeground) AttachThreadInput(current, foreground, false);
  }
 }
 public static bool IsAbove(IntPtr upper, IntPtr lower) {
  for (IntPtr current = GetWindow(lower, 3); current != IntPtr.Zero; current = GetWindow(current, 3)) {
   if (current == upper) return true;
  }
  return false;
 }
}
'@
    $script:fixtureTitle = 'Recorder external viewer ' + [guid]::NewGuid().ToString('N')
    $fixtureScript = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ExternalViewerNative {
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
}
"@
$external = New-Object Windows.Forms.Form
$external.Text = '__TITLE__'
$external.Size = New-Object Drawing.Size(600, 380)
$external.ShowInTaskbar = $false
$external.Add_Shown({
 [ExternalViewerNative]::ShowWindow($external.Handle, 5) | Out-Null
 [ExternalViewerNative]::SetForegroundWindow($external.Handle) | Out-Null
})
$external.Show()
[ExternalViewerNative]::ShowWindow($external.Handle, 5) | Out-Null
[Windows.Forms.Application]::Run($external)
'@
    $fixturePath = Join-Path $testRoot 'viewer.ps1'
    [IO.File]::WriteAllText($fixturePath, $fixtureScript.Replace('__TITLE__', $script:fixtureTitle), (New-Object Text.UTF8Encoding($true)))
    $script:fixturePath = $fixturePath
    $script:fixtureWindow = [intptr]::Zero
    $script:fixtureProcess = $null
    $script:launchCount = 0
    # Use a controlled, genuinely separate process instead of opening or closing
    # the user's own editor tabs or Explorer windows. Reuse it on later launches.
    Set-Item Function:Start-RecorderExternalApplication -Value {
        param([Diagnostics.ProcessStartInfo]$StartInfo)
        $script:launchCount++
        $script:lastExternalTarget = $StartInfo.FileName
        Assert ($StartInfo.UseShellExecute) 'External target no longer uses its system association'
        Assert (-not $form.TopMost) 'Main form is still topmost while launching external application'
        if ($topMostToggle.Checked) {
            Assert ($script:externalWindowPending) 'External suspension was not established before launch'
            [RecorderExternalTestNative]::FocusWindow($form.Handle)
            [Windows.Forms.Application]::DoEvents()
            Assert (-not $form.TopMost) 'Activation during launch restored topmost too early'
        }
        if ($null -eq $script:fixtureProcess) {
            $script:fixtureProcess = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $script:fixturePath + '"')) -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $testRoot 'viewer-error.log') -RedirectStandardOutput (Join-Path $testRoot 'viewer-output.log')
            Wait-ForWindowState { $script:fixtureWindow = [RecorderExternalTestNative]::FindByTitle($script:fixtureTitle); $script:fixtureWindow -ne [intptr]::Zero }
        }
        [RecorderExternalTestNative]::ShowWindow($script:fixtureWindow, 5) | Out-Null
        [RecorderExternalTestNative]::FocusWindow($script:fixtureWindow)
    }
    $form.Show(); [RecorderExternalTestNative]::FocusWindow($form.Handle)
    [Windows.Forms.Application]::DoEvents()
    $nameInput.Text = 'A'; $addButton.PerformClick()
    Add-StepButton -Name 'A' | Out-Null
    Sync-Steps
    $script:activeLogPath = Join-Path $testRoot 'records.txt'
    [IO.File]::WriteAllText($script:activeLogPath, '')
    Reset-StepProgress -Round 4
    Invoke-NextStep
    $before = [IO.File]::ReadAllText($script:activeLogPath)
    $round = $script:currentRound; $next = $script:pendingSteps[0]; $undo = $script:undoSpace
    foreach ($theme in @('Classic', 'Workbench')) {
        Set-LayoutTheme -Theme $theme
        foreach ($folder in @($false, $true)) {
            $topMostToggle.Checked = $true
            [RecorderExternalTestNative]::FocusWindow($form.Handle)
            Wait-ForWindowState { [RecorderExternalTestNative]::FocusWindow($form.Handle); [RecorderForeground]::BelongsTo($form.Handle) }
            if ($folder) { Open-CurrentLogLocation -Folder } else { Open-CurrentLogLocation }
            Wait-ForWindowState { [RecorderExternalTestNative]::FocusWindow($script:fixtureWindow); [RecorderForeground]::GetForegroundWindow() -eq $script:fixtureWindow }
            Update-RecorderWindowActivation
            Assert (-not $form.TopMost -and $topMostToggle.Checked -and $themeTopmostItem.Checked) 'External launch did not yield topmost while retaining user setting'
            Assert ([RecorderExternalTestNative]::IsAbove($script:fixtureWindow, $form.Handle)) 'Recorder still obscures external process'
            Assert ($script:lastExternalTarget -eq $(if ($folder) { $testRoot } else { $script:activeLogPath })) 'Wrong external target'
            [RecorderExternalTestNative]::FocusWindow($form.Handle)
            Wait-ForWindowState { [RecorderExternalTestNative]::FocusWindow($form.Handle); [RecorderForeground]::BelongsTo($form.Handle) -and $form.TopMost }
            Assert (-not $script:externalWindowPending) 'Returning to recorder did not finish suspension'
        }
        Write-Output ('PASS: ' + $theme + ' external file/folder process is above main window; returning restores topmost')
    }
    Assert ($script:launchCount -eq 4 -and -not $script:fixtureProcess.HasExited) 'Reused external process was not handled'
    $workingStarter = (Get-Command Start-RecorderExternalApplication).ScriptBlock
    Set-Item Function:Start-RecorderExternalApplication -Value { param($StartInfo) throw 'Simulated launch failure' }
    $failed = $false
    try { Open-CurrentLogLocation }
    catch { $failed = $true }
    Assert ($failed -and $form.TopMost -and -not $script:externalWindowPending) 'Failed launch left topmost suspended'
    Set-Item Function:Start-RecorderExternalApplication -Value $workingStarter
    Open-CurrentLogLocation
    Wait-ForWindowState { [RecorderExternalTestNative]::FocusWindow($script:fixtureWindow); [RecorderForeground]::GetForegroundWindow() -eq $script:fixtureWindow }
    $topMostToggle.Checked = $false
    [RecorderExternalTestNative]::FocusWindow($form.Handle)
    Wait-ForWindowState { [RecorderExternalTestNative]::FocusWindow($form.Handle); [RecorderForeground]::BelongsTo($form.Handle) }
    Assert (-not $form.TopMost -and -not $script:externalWindowPending) 'User disabled topmost, but old suspension restored it'
    Open-CurrentLogLocation -Folder
    [RecorderExternalTestNative]::FocusWindow($form.Handle)
    Wait-ForWindowState { [RecorderExternalTestNative]::FocusWindow($form.Handle); [RecorderForeground]::BelongsTo($form.Handle) }
    Assert (-not $form.TopMost) 'Opening externally with topmost disabled enabled it'
    $topMostToggle.Checked = $true
    Open-CurrentLogLocation
    Wait-ForWindowState { [RecorderExternalTestNative]::FocusWindow($script:fixtureWindow); [RecorderForeground]::GetForegroundWindow() -eq $script:fixtureWindow }
    $click = [Windows.Forms.Message]::Create($form.Handle, 0x201, [intptr]1, [intptr]0)
    $spaceFilter.PreFilterMessage([ref]$click) | Out-Null
    Assert ($form.TopMost -and -not $script:externalWindowPending) 'Explicit return interaction did not restore topmost'
    Assert ($script:currentRound -eq $round -and $script:pendingSteps[0] -eq $next -and $script:undoSpace -eq $undo -and [IO.File]::ReadAllText($script:activeLogPath) -eq $before) 'Window activation changed recording or progress'
    Assert ($script:recorderModalDepth -eq 0 -and -not $script:launchingExternalWindow) 'Window activation scope leaked'
    Write-Output 'PASS: reused process, launch failure, disabled topmost, explicit interaction and unchanged records/rounds/undo'
}
finally {
    if ($script:fixtureWindow -and $script:fixtureWindow -ne [intptr]::Zero) { [RecorderExternalTestNative]::PostMessage($script:fixtureWindow, 0x10, [intptr]::Zero, [intptr]::Zero) | Out-Null }
    if ($script:fixtureProcess) {
        if (-not $script:fixtureProcess.WaitForExit(3000)) { $script:fixtureProcess.Kill() }
        $script:fixtureProcess.Dispose()
    }
    if ($form) { $form.Close(); $form.Dispose() }
    $env:APPDATA = $originalAppData
}
