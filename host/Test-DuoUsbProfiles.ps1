[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Serial,
    [string]$Adb = 'C:\Tools\platform-tools\adb.exe',
    [ValidateRange(10, 120)]
    [int]$ActiveSeconds = 18,
    [string]$MassImageDevicePath = '/data/local/tmp/duo-fs-smoke.iso',
    [string]$ExpectedUnamePattern = '4\.14\.190-duo-p-0_0_0\+',
    [string[]]$Profiles = @('acm', 'ecm', 'ncm', 'eem', 'mass', 'midi', 'uac2')
)

$ErrorActionPreference = 'Stop'

$profilePid = @{
    acm  = '0105'
    rndis = '0106'
    ecm  = '0107'
    ncm  = '0108'
    eem  = '0109'
    mass = '010A'
    midi = '010B'
    uac2 = '010C'
}

function Get-AdbState {
    try {
        $output = & $Adb -s $Serial get-state 2>$null
        if ($LASTEXITCODE -eq 0) { return ($output | Select-Object -First 1) }
    } catch {
        return ''
    }
    return ''
}

function Wait-AdbDevice([int]$TimeoutSeconds = 40) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if ((Get-AdbState) -eq 'device') { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "ADB did not return within $TimeoutSeconds seconds"
}

function Wait-ProfileDevice([string]$UsbPid, [int]$TimeoutSeconds = 15) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match "VID_1D6B&PID_$UsbPid" })
        if ($devices.Count -gt 0) {
            # Composite child functions can arrive shortly after the parent.
            # Give Windows PnP a brief settling window, then return the full set.
            Start-Sleep -Seconds 2
            return @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
                Where-Object { $_.InstanceId -match "VID_1D6B&PID_$UsbPid" })
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    return @()
}

$results = [System.Collections.Generic.List[object]]::new()
Wait-AdbDevice

foreach ($profile in $Profiles) {
    if (-not $profilePid.ContainsKey($profile)) {
        throw "Unknown profile: $profile"
    }
    $usbPid = $profilePid[$profile]
    $argument = if ($profile -eq 'mass') { " $MassImageDevicePath" } else { '' }
    Write-Host "Activating $profile (PID $usbPid)..."
    $command = "duo-usb enable $profile $ActiveSeconds$argument"
    $ErrorActionPreference = 'Continue'
    $activation = & $Adb -s $Serial shell su -c $command 2>&1
    $activationExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    $devices = @(Wait-ProfileDevice -UsbPid $usbPid)
    # adbd can lose the transport before the host receives the shell's exit
    # packet. Treat actual USB enumeration as authoritative in that race.
    if ($activationExit -ne 0 -and $devices.Count -eq 0) {
        throw "$profile activation failed: $($activation -join ' ')"
    }
    if ($devices.Count -eq 0) {
        $results.Add([pscustomobject]@{
            Profile = $profile; PID = $usbPid; Detected = $false
            Status = 'Missing'; Class = ''; Name = ''; InstanceId = ''
        })
    } else {
        foreach ($device in $devices) {
            Write-Host "  $($device.Status) $($device.Class) $($device.FriendlyName)"
            $results.Add([pscustomobject]@{
                Profile = $profile; PID = $usbPid; Detected = $true
                Status = [string]$device.Status; Class = [string]$device.Class
                Name = [string]$device.FriendlyName; InstanceId = [string]$device.InstanceId
            })
        }
    }

    # Enumeration proves ADB went away. Wait for the bounded watchdog to put
    # Android's untouched g1 gadget back, then ensure the kernel did not change.
    Wait-AdbDevice -TimeoutSeconds ($ActiveSeconds + 30)
    # adbd can accept a transport just before the watchdog finishes unbinding
    # g3 and clearing its session files. Avoid racing the next profile against
    # those final restore steps.
    Start-Sleep -Seconds 2
    $uname = (& $Adb -s $Serial shell uname -a 2>$null) -join ' '
    if ($uname -notmatch $ExpectedUnamePattern) {
        throw "Unexpected kernel after $profile restore: $uname"
    }
    Write-Host "$profile restored ADB on the expected candidate kernel."
}

$results | Sort-Object Profile, Class, Name |
    Format-Table Profile, PID, Detected, Status, Class, Name, InstanceId -AutoSize

if ($results.Where({ -not $_.Detected }).Count -gt 0) {
    throw 'One or more USB profiles did not enumerate.'
}
