Option Explicit

Dim shell, fileSystem, scriptFolder, launcherPath, powershellPath, shortcutPath, shortcut
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptFolder = fileSystem.GetParentFolderName(WScript.ScriptFullName)
launcherPath = scriptFolder & "\RecorderLauncher.ps1"
If Not fileSystem.FileExists(launcherPath) Then
    MsgBox "Recorder launcher not found: " & launcherPath, vbCritical, "Cannot create shortcut"
    WScript.Quit 1
End If

powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
If Not fileSystem.FileExists(powershellPath) Then
    MsgBox "Windows PowerShell not found: " & powershellPath, vbCritical, "Cannot create shortcut"
    WScript.Quit 1
End If

shortcutPath = shell.SpecialFolders("Desktop") & "\Earphone Log Time Recorder.lnk"
Set shortcut = shell.CreateShortcut(shortcutPath)
shortcut.TargetPath = powershellPath
shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & launcherPath & Chr(34)
shortcut.WorkingDirectory = scriptFolder
shortcut.IconLocation = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\shell32.dll, 44"
shortcut.Description = "Record earphone test event timestamps"
shortcut.Save

MsgBox "Desktop shortcut created. Double-click Earphone Log Time Recorder to start.", vbInformation, "Done"
