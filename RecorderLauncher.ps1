$ErrorActionPreference = 'Stop'

try {
    & (Join-Path $PSScriptRoot 'RecordTime.ps1')
}
catch {
    $errorText = ($_ | Out-String).Trim()
    $errorPath = Join-Path $env:LOCALAPPDATA 'EarphoneLogTimeRecorder\startup-error.log'
    $message = "The recorder could not start.`r`n`r`n$errorText`r`n`r`nDetails saved to:`r`n$errorPath"

    try {
        $errorDirectory = Split-Path -Parent $errorPath
        if (-not (Test-Path -LiteralPath $errorDirectory)) {
            New-Item -ItemType Directory -Path $errorDirectory -Force | Out-Null
        }
        [System.IO.File]::AppendAllText(
            $errorPath,
            ('[{0}] {1}{2}{3}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $errorText, [Environment]::NewLine, [Environment]::NewLine),
            (New-Object System.Text.UTF8Encoding($false))
        )
    }
    catch {
        $message += "`r`n`r`nCould not write the error log: $($_.Exception.Message)"
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            'Earphone Log Time Recorder - Startup Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        [Console]::Error.WriteLine($message)
    }

    exit 1
}
