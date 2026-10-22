$ErrorActionPreference = 'Stop'
$originalAppData = $env:APPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('RecorderDialogTest-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$env:APPDATA = $testRoot
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RecordTime.ps1'))
    $source = $source.Replace('[System.Windows.Forms.Application]::Run($form)', '').Replace('$PSScriptRoot', "'" + $PSScriptRoot.Replace("'", "''") + "'")
    . ([scriptblock]::Create($source))
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class RecorderDialogTestNative {
 public delegate bool Callback(IntPtr window, IntPtr state);
 [DllImport("user32.dll")] public static extern bool EnumWindows(Callback callback, IntPtr state);
 [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr window, uint command);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr window);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
 [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr dialog, int item);
 public static bool IsAbove(IntPtr popup, IntPtr owner) {
  for (IntPtr current = GetWindow(owner, 3); current != IntPtr.Zero; current = GetWindow(current, 3)) {
   if (current == popup) return true;
  }
  return false;
 }
 public static IntPtr FindOwnedPopup(IntPtr owner, string title) {
  IntPtr found = IntPtr.Zero;
  EnumWindows(delegate(IntPtr window, IntPtr state) {
   if (!IsWindowVisible(window) || GetWindow(window, 4) != owner) return true;
   StringBuilder text = new StringBuilder(512);
   GetWindowText(window, text, text.Capacity);
   if (title == null || text.ToString() == title) { found = window; return false; }
   return true;
  }, IntPtr.Zero);
  return found;
 }
}
'@
    function Test-ManagedDialog {
        param([scriptblock]$Action, [string]$Title, [string]$Value, [switch]$Cancel, [Windows.Forms.Form]$Owner = $form)
        $state = @{ Seen = $false; Error = $null }
        $timer = New-Object Windows.Forms.Timer
        $timer.Interval = 80
        $timer.Add_Tick({
            $popup = @([Windows.Forms.Application]::OpenForms | Where-Object { $_.Text -eq $Title }) | Select-Object -First 1
            if (-not $popup) { return }
            $timer.Stop(); $state.Seen = $true
            try {
                Assert ($popup.Owner -eq $Owner -and $popup.Modal -and $popup.TopMost -eq $Owner.TopMost) 'Input dialog owner/topmost state is incorrect'
                Assert (-not [RecorderDialogTestNative]::IsWindowEnabled($Owner.Handle)) 'Modal owner remains clickable'
                Assert ([RecorderDialogTestNative]::IsAbove($popup.Handle, $Owner.Handle)) 'Input dialog is behind its owner'
                $Owner.BringToFront()
                Assert ([RecorderDialogTestNative]::IsAbove($popup.Handle, $Owner.Handle)) 'Activating owner hid its input dialog'
                $key = [Windows.Forms.Message]::Create($popup.Handle, 0x100, [intptr]119, [intptr]0)
                Assert (-not $spaceFilter.PreFilterMessage([ref]$key)) 'Main shortcut intercepted dialog input'
                $input = $popup.Controls.Find('DialogInput', $true)[0]
                $input.Text = $Value
                Assert ($input.Width -gt 300 -and $popup.AcceptButton.Bottom -le $popup.AcceptButton.Parent.Height) 'Input dialog controls clipped'
                if ($Cancel) { $popup.CancelButton.PerformClick() } else { $popup.AcceptButton.PerformClick() }
            }
            catch { $state.Error = $_; $popup.DialogResult = 'Cancel'; $popup.Close() }
        }.GetNewClosure())
        $timer.Start()
        try { & $Action }
        finally { $timer.Stop(); $timer.Dispose() }
        if ($state.Error) { throw $state.Error }
        Assert ($state.Seen) ('Expected input dialog did not open: ' + $Title)
        Assert ($Owner.Enabled) 'Owner did not recover after input dialog closed'
    }
    function Test-NativeDialog {
        param([scriptblock]$Action, [string]$Title, [int]$Command = 1)
        $state = @{ Seen = $false; Error = $null }
        $timer = New-Object Windows.Forms.Timer
        $timer.Interval = 100
        $timer.Add_Tick({
            $popup = [RecorderDialogTestNative]::FindOwnedPopup($form.Handle, $Title)
            if ($popup -eq [intptr]::Zero) { return }
            $button = [RecorderDialogTestNative]::GetDlgItem($popup, $Command)
            # Windows can give a single acknowledgement button IDCANCEL.
            if ($button -eq [intptr]::Zero -and $Command -eq 1) { $button = [RecorderDialogTestNative]::GetDlgItem($popup, 2) }
            if ($button -eq [intptr]::Zero) { return }
            $timer.Stop(); $state.Seen = $true
            try {
                Assert ([RecorderDialogTestNative]::IsAbove($popup, $form.Handle)) 'Native dialog is behind the main form'
                Assert (-not [RecorderDialogTestNative]::IsWindowEnabled($form.Handle)) 'Native dialog did not disable its owner'
            }
            catch { $state.Error = $_ }
            finally { [RecorderDialogTestNative]::PostMessage($button, 0xF5, [intptr]::Zero, [intptr]::Zero) | Out-Null }
        }.GetNewClosure())
        $timer.Start()
        try { & $Action | Out-Null }
        finally { $timer.Stop(); $timer.Dispose() }
        if ($state.Error) { throw $state.Error }
        Assert ($state.Seen) ('Expected owned native dialog did not open: ' + $Title)
        Assert ([RecorderDialogTestNative]::IsWindowEnabled($form.Handle)) 'Main form did not recover after native dialog'
    }
    $form.Show(); $form.Activate()
    [Windows.Forms.Application]::DoEvents()
    $nameInput.Text = 'A'; $addButton.PerformClick()
    Add-StepButton -Name 'A' | Out-Null
    Sync-Steps
    $script:activeLogPath = Join-Path $testRoot 'records.txt'
    [IO.File]::WriteAllText($script:activeLogPath, '')
    Reset-StepProgress -Round 3
    $case = 0
    foreach ($theme in @('Classic', 'Workbench')) {
        Set-LayoutTheme -Theme $theme
        foreach ($topmost in @($true, $false)) {
            $case++
            $topMostToggle.Checked = $topmost
            $wantedProfile = 'DialogProfile' + $case
            Test-ManagedDialog -Title '另存测试方案' -Value $wantedProfile -Action { $saveProfile.PerformClick() }
            Assert ($script:activeProfile -eq $wantedProfile -and $script:profiles.ContainsKey($wantedProfile)) 'Save-as action did not save input value'
            Assert ($form.TopMost -eq $topmost -and $topMostToggle.Checked -eq $topmost -and $themeTopmostItem.Checked -eq $topmost) 'Dialog changed the topmost setting'
            Test-ManagedDialog -Title '另存测试方案' -Value 'MustNotSave' -Cancel -Action { $saveProfile.PerformClick() }
            Assert ($script:activeProfile -eq $wantedProfile -and -not $script:profiles.ContainsKey('MustNotSave')) 'Cancel changed the active profile'
            $wantedName = 'Renamed' + $case
            Test-ManagedDialog -Title '重命名按钮' -Value $wantedName -Action { $actionPanel.Controls[0].ContextMenuStrip.Items[3].PerformClick() }
            Assert ($script:buttonNames[0] -eq $wantedName -and $script:stepNames[0] -eq $wantedName) 'Rename did not update button and step'
            $nameInput.Text = ''
            Test-NativeDialog -Title '按钮名称不能为空' -Action { $addButton.PerformClick() }
            Test-NativeDialog -Title '删除按钮' -Command 7 -Action { $actionPanel.Controls[0].ContextMenuStrip.Items[4].PerformClick() }
            Assert ($script:buttonNames.Count -eq 1) 'Declined deletion removed the button'
            Test-NativeDialog -Title '打开记录文件' -Command 2 -Action { Select-LogFile -Mode Open }
            Test-NativeDialog -Title '新建记录文件' -Command 2 -Action { Select-LogFile -Mode New }
            Assert ($script:currentRound -eq 3 -and [IO.File]::ReadAllBytes($script:activeLogPath).Length -eq 0) 'Dialog interaction wrote records or reset rounds'
            Assert ($form.TopMost -eq $topmost -and $script:recorderModalDepth -eq 0) 'Dialog did not restore topmost or leaked a modal scope'
            Write-Output ('PASS: ' + $theme + ' topmost=' + $topmost + ' dialog ownership and actions')
        }
    }
    $topMostToggle.Checked = $true
    Test-NativeDialog -Title '保存方案' -Command 7 -Action { Save-ProfileAs -Name 'DialogProfile1' }
    Assert ($script:activeProfile -eq 'DialogProfile4') 'Declined overwrite switched profiles'
    $outer = New-Object Windows.Forms.Form
    $outer.Text = 'Nested dialog owner'; $outer.TopMost = $true
    $outer.Add_Shown({
        try {
            Test-ManagedDialog -Owner $outer -Title 'Nested input' -Value 'nested' -Action { $script:nestedInputResult = Show-RecorderInputDialog -Owner $outer -Title 'Nested input' -Prompt 'Nested' }
        }
        catch { $script:nestedDialogError = $_ }
        finally { $outer.Close() }
    })
    try { $outer.ShowDialog($form) | Out-Null }
    finally { $outer.Dispose() }
    if ($script:nestedDialogError) { throw $script:nestedDialogError }
    Assert ($script:nestedInputResult -eq 'nested' -and $form.TopMost) 'Nested input dialog failed or disabled topmost'
    Write-Output 'PASS: actual owned dialogs stay above topmost/non-topmost main window in both layouts; save-as, cancel, rename, messages, confirmations, file pickers and nested dialogs'
}
finally {
    if ($form) { $form.Close(); $form.Dispose() }
    $env:APPDATA = $originalAppData
}
