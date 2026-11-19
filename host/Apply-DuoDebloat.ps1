[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Plan,
    [Parameter(Mandatory)][string] $CaptureDirectory,
    [switch] $Apply,
    [string] $Adb = 'adb',
    [string] $DeviceSerial
)

$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)

    $prefix = @()
    if ($DeviceSerial) { $prefix = @('-s', $DeviceSerial) }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Adb @prefix @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) {
        throw "adb $($Arguments -join ' ') failed:`n$($output -join "`n")"
    }
    return ($output -join "`n").Trim()
}

$planPath = (Resolve-Path -LiteralPath $Plan).Path
$captureRoot = (Resolve-Path -LiteralPath $CaptureDirectory).Path
$capturePath = Join-Path $captureRoot 'capture.json'
if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) {
    throw "Missing capture metadata: $capturePath"
}
$capture = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json

if ((Invoke-Adb -Arguments @('get-state')) -ne 'device') {
    throw 'The selected ADB target is not online and authorized.'
}
$build = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.incremental')).Trim()
$serial = (Invoke-Adb -Arguments @('get-serialno')).Trim()
$userIdText = (Invoke-Adb -Arguments @('shell', 'am', 'get-current-user')).Trim()
if ($build -ne '202209020048' -or $build -ne [string] $capture.build) {
    throw "Build mismatch: device=$build capture=$($capture.build)"
}
if ($serial -ne [string] $capture.serial) {
    throw 'The connected device serial does not match the reviewed capture.'
}
if ($userIdText -notmatch '^\d+$' -or [int] $userIdText -ne [int] $capture.userId) {
    throw "Android user mismatch: device=$userIdText capture=$($capture.userId)"
}
$userId = [int] $userIdText

$homeResult = Invoke-Adb -Arguments @('shell', 'cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME')
$homePackage = (($homeResult -split "`n")[-1].Trim() -split '/')[0]
$protectedDynamic = @{}
if ($homePackage -match '^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$') {
    $protectedDynamic[$homePackage] = 'current HOME activity'
}
$roleState = Invoke-Adb -Arguments @('shell', 'dumpsys', 'role')
$currentRole = 'unknown role'
foreach ($line in $roleState -split "`n") {
    if ($line -match '^\s*name=(android\.app\.role\.[A-Z0-9_]+)\s*$') {
        $currentRole = $Matches[1]
        continue
    }
    if ($line -match '^\s*holders=(.+?)\s*$') {
        foreach ($match in [regex]::Matches($Matches[1], '[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+')) {
            $protectedDynamic[$match.Value] = "role holder: $currentRole"
        }
    }
}
$ime = (Invoke-Adb -Arguments @('shell', 'settings', 'get', 'secure', 'default_input_method')).Trim()
$imePackage = ($ime -split '/')[0]
if ($imePackage -match '^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$') {
    $protectedDynamic[$imePackage] = 'current input method'
}
$webViewState = Invoke-Adb -Arguments @('shell', 'dumpsys', 'webviewupdate')
foreach ($line in $webViewState -split "`n") {
    if ($line -match '^\s*(Current|Preferred) WebView package.*?\(([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+),') {
        $protectedDynamic[$Matches[2]] = "$($Matches[1].ToLowerInvariant()) WebView provider"
    } elseif ($line -match '^\s*Valid package ([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+) ') {
        $protectedDynamic[$Matches[1]] = 'valid installed WebView provider'
    }
}
$overlayState = Invoke-Adb -Arguments @('shell', 'cmd', 'overlay', 'list', '--user', "$userId")
foreach ($line in $overlayState -split "`n") {
    if ($line -match '^\s*\[x\]\s+([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)\s*$') {
        $protectedDynamic[$Matches[1]] = 'enabled runtime overlay'
    }
}
$protectedExact = @(
    'android',
    'com.android.bluetooth',
    'com.android.camera2',
    'com.android.externalstorage',
    'com.android.keychain',
    'com.android.managedprovisioning',
    'com.android.networkstack',
    'com.android.nfc',
    'com.android.packageinstaller',
    'com.android.permissioncontroller',
    'com.android.phone',
    'com.android.providers.downloads',
    'com.android.providers.media',
    'com.android.providers.settings',
    'com.android.server.telecom',
    'com.android.settings',
    'com.android.shell',
    'com.android.systemui',
    'com.android.vending',
    'com.google.android.gms',
    'com.google.android.gsf',
    'com.microsoft.launcher'
)
$protectedPatterns = @(
    '^com\.android\.(cellbroadcast|emergency|inputmethod|location|ons|providers\.telephony|se|telephony|wifi)(\.|$)',
    '^com\.google\.android\.(cellbroadcast|networkstack|permissioncontroller|providers|webview)(\.|$)',
    '^com\.microsoft\.(camera|deviceintegration|duo|surface|setupwizard)(\.|$)'
)

$entries = [System.Collections.Generic.List[object]]::new()
$seen = @{}
foreach ($rawLine in Get-Content -LiteralPath $planPath) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $fields = $rawLine -split "`t", 2
    $packageName = $fields[0].Trim()
    $reason = if ($fields.Count -eq 2) { $fields[1].Trim() } else { '' }
    if ($packageName -notmatch '^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$') {
        throw "Invalid package name in plan: $packageName"
    }
    if (-not $reason) { throw "A review reason is required for $packageName" }
    if ($seen.ContainsKey($packageName)) { throw "Duplicate plan entry: $packageName" }
    $seen[$packageName] = $true
    if ($protectedDynamic.ContainsKey($packageName)) {
        throw "Refusing protected package: $packageName ($($protectedDynamic[$packageName]))"
    }
    if ($protectedExact -contains $packageName) {
        throw "Refusing protected package: $packageName"
    }
    foreach ($pattern in $protectedPatterns) {
        if ($packageName -match $pattern) { throw "Refusing protected package: $packageName" }
    }
    $entries.Add([pscustomobject]@{ Package = $packageName; Reason = $reason })
}
if ($entries.Count -eq 0) { throw 'The reviewed debloat plan contains no package entries.' }

$installedLines = Invoke-Adb -Arguments @('shell', 'pm', 'list', 'packages', '--user', "$userId")
$installed = @{}
foreach ($line in $installedLines -split "`n") {
    $name = ($line -replace "`r", '') -replace '^package:', ''
    if ($name) { $installed[$name] = $true }
}

Write-Host "Reviewed device: $($capture.model), build $build, user $userId"
Write-Host "Protected current HOME package: $homePackage"
Write-Host "Protected dynamic role/IME/WebView/overlay packages: $($protectedDynamic.Count)"
Write-Host "Plan contains $($entries.Count) explicit package(s)."
foreach ($entry in $entries) {
    if (-not $installed.ContainsKey($entry.Package)) { throw "Planned package is not installed: $($entry.Package)" }
    Write-Host "  $($entry.Package) - $($entry.Reason)"
}
if (-not $Apply) {
    Write-Host 'Dry run only. Re-run with -Apply after reviewing the list above.'
    return
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$restorePath = Join-Path $captureRoot "restore-packages-$timestamp.tsv"
Set-Content -LiteralPath $restorePath -Value @(
    "# Duo Technician restore manifest",
    "# build`t$build",
    "# serial`t$serial",
    "# user`t$userId",
    "# package`tprevious-action`treason"
) -Encoding UTF8

foreach ($entry in $entries) {
    $dump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $entry.Package)
    $match = [regex]::Match($dump, "(?s)User\s+${userId}:.*?enabled=(\d+)")
    if (-not $match.Success) { throw "Could not determine enabled state for $($entry.Package)" }
    $enabledState = [int] $match.Groups[1].Value
    if ($enabledState -notin @(0, 1)) {
        Write-Host "Already non-enabled; leaving unchanged: $($entry.Package) (state $enabledState)"
        continue
    }
    $restoreAction = if ($enabledState -eq 0) { 'default-state' } else { 'enable' }
    Add-Content -LiteralPath $restorePath -Value "$($entry.Package)`t$restoreAction`t$($entry.Reason)" -Encoding UTF8
    Write-Host "Disabling for Android user ${userId}: $($entry.Package)"
    Invoke-Adb -Arguments @('shell', 'pm', 'disable-user', '--user', "$userId", $entry.Package) | Write-Host
    $disabled = Invoke-Adb -Arguments @('shell', 'pm', 'list', 'packages', '--user', "$userId", '-d', $entry.Package)
    if (($disabled -split "`n") -notcontains "package:$($entry.Package)") {
        throw "Package did not enter the disabled set: $($entry.Package)"
    }
}

Write-Host "Debloat plan applied. Exact restoration manifest: $restorePath"
Write-Host 'Reboot Android and run the complete smoke test before treating the change as accepted.'

