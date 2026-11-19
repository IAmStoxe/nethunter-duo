[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Serial,
    [string]$Adb = 'C:\Tools\platform-tools\adb.exe',
    [ValidateRange(10, 120)]
    [int]$ActiveSeconds = 15,
    [string]$ExpectedUnamePattern = '4\.14\.190-duo-p-0_0_0\+'
)

$ErrorActionPreference = 'Stop'

function Get-AdbState {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $state = & $Adb -s $Serial get-state 2>$null
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -eq 0) { return ($state | Select-Object -First 1) }
    return ''
}

function Wait-Adb([int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if ((Get-AdbState) -eq 'device') { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "ADB did not return within $TimeoutSeconds seconds."
}

Wait-Adb 30
$command = "duo-hid enable $ActiveSeconds"
$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $activation = & $Adb -s $Serial shell su -c $command 2>&1
    $activationExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousPreference
}

$deadline = (Get-Date).AddSeconds(20)
$devices = @()
do {
    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1D6B&PID_0104' })
    if ($devices.Count -gt 0) { break }
    Start-Sleep -Milliseconds 300
} while ((Get-Date) -lt $deadline)
if ($activationExit -ne 0 -and $devices.Count -eq 0) {
    throw "HID activation failed: $($activation -join ' ')"
}
Start-Sleep -Seconds 2
$devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_1D6B&PID_0104' })
$devices | Sort-Object Class, FriendlyName |
    Format-Table Status, Class, FriendlyName, InstanceId -AutoSize

if ($devices.Where({ $_.Class -eq 'Keyboard' -and $_.Status -eq 'OK' }).Count -eq 0) {
    throw 'Windows did not start the HID keyboard interface.'
}
if ($devices.Where({ $_.Class -eq 'Mouse' -and $_.Status -eq 'OK' }).Count -eq 0) {
    throw 'Windows did not start the HID mouse interface.'
}
if ($devices.Where({ $_.Class -eq 'USB' -and $_.Status -eq 'OK' }).Count -eq 0) {
    throw 'Windows did not start the HID composite parent.'
}

Wait-Adb ($ActiveSeconds + 30)
Start-Sleep -Seconds 2
$uname = (& $Adb -s $Serial shell uname -a 2>$null) -join ' '
if ($uname -notmatch $ExpectedUnamePattern) {
    throw "Unexpected kernel after HID restore: $uname"
}
Write-Host "HID keyboard/mouse restored ADB on the expected candidate kernel: $uname"
