# Register Explorer "Open with NOE" for this build of noe.exe (current user, no admin).
#   powershell -File install-context-menu.ps1
#   powershell -File install-context-menu.ps1 -Uninstall

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$exe = Join-Path $PSScriptRoot "build\noe.exe"
$keys = @(
    "HKCU:\Software\Classes\Directory\shell\NOE",
    "HKCU:\Software\Classes\Directory\Background\shell\NOE"
)

if ($Uninstall) {
    foreach ($key in $keys) {
        if (Test-Path $key) {
            Remove-Item -Path $key -Recurse -Force
        }
    }
    Write-Host "Removed Explorer 'Open with NOE'."
    exit 0
}

if (-not (Test-Path $exe)) {
    Write-Error "build\noe.exe not found. Run .\build.sh first."
}

$exe = (Resolve-Path $exe).Path
$command = "`"$exe`" `"%V`""

foreach ($key in $keys) {
    New-Item -Path $key -Force | Out-Null
    New-Item -Path "$key\command" -Force | Out-Null
    Set-ItemProperty -Path $key -Name "(default)" -Value "Open with NOE"
    Set-ItemProperty -Path $key -Name "Icon" -Value $exe
    Set-ItemProperty -Path "$key\command" -Name "(default)" -Value $command
}

Write-Host "Installed Explorer 'Open with NOE' -> $exe"
Write-Host "Right-click a folder, or empty space inside a folder. On Windows 11, use Show more options if it is not in the compact menu."
