Option Explicit

Dim shell, fileSystem, scriptPath, scriptFolder, powershellPath, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptPath = WScript.ScriptFullName
scriptFolder = fileSystem.GetParentFolderName(scriptPath)
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
If Not fileSystem.FileExists(scriptFolder & "\RecordTime.ps1") Then
    MsgBox "Recorder script not found:" & vbCrLf & scriptFolder & "\RecordTime.ps1", vbCritical, "Earphone Log Time Recorder"
    WScript.Quit 1
End If
If Not fileSystem.FileExists(powershellPath) Then
    powershellPath = "powershell.exe"
End If

command = Chr(34) & powershellPath & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -STA -File " & Chr(34) & scriptFolder & "\RecorderLauncher.ps1" & Chr(34)
On Error Resume Next
shell.Run command, 0, False
If Err.Number <> 0 Then
    MsgBox "Could not start the recorder: " & Err.Description, vbCritical, "Earphone Log Time Recorder"
End If
