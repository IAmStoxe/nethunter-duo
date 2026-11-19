[CmdletBinding()]
param(
    [string] $OutputDirectory,
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

if ((Invoke-Adb -Arguments @('get-state')) -ne 'device') {
    throw 'The selected ADB target is not online and authorized.'
}
$build = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.incremental')).Trim()
if ($build -ne '202209020048') {
    throw "Expected Surface Duo build 202209020048; found $build."
}
$userIdText = (Invoke-Adb -Arguments @('shell', 'am', 'get-current-user')).Trim()
if ($userIdText -notmatch '^\d+$') { throw "Invalid Android user ID: $userIdText" }
$userId = [int] $userIdText

if (-not $OutputDirectory) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $OutputDirectory = Join-Path $projectRoot ('.work\device-state\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$captureRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $captureRoot) {
    if (@(Get-ChildItem -LiteralPath $captureRoot -Force).Count -ne 0) {
        throw "Capture directory is not empty: $captureRoot"
    }
} else {
    New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
}

function Save-AdbOutput {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $value = Invoke-Adb -Arguments $Arguments
    Set-Content -LiteralPath (Join-Path $captureRoot $Name) -Value $value -Encoding UTF8
    return $value
}

$properties = Save-AdbOutput 'properties.txt' @('shell', 'getprop')
Save-AdbOutput 'packages-all.txt' @('shell', 'pm', 'list', 'packages', '--user', "$userId", '-f', '-U', '-i') | Out-Null
Save-AdbOutput 'packages-enabled.txt' @('shell', 'pm', 'list', 'packages', '--user', "$userId", '-e') | Out-Null
Save-AdbOutput 'packages-disabled.txt' @('shell', 'pm', 'list', 'packages', '--user', "$userId", '-d') | Out-Null
Save-AdbOutput 'packages-system.txt' @('shell', 'pm', 'list', 'packages', '--user', "$userId", '-s') | Out-Null
Save-AdbOutput 'packages-third-party.txt' @('shell', 'pm', 'list', 'packages', '--user', "$userId", '-3') | Out-Null
$microsoftPackages = Save-AdbOutput 'packages-microsoft.txt' @('shell', 'pm', 'list', 'packages', '--user', "$userId", 'com.microsoft')
Save-AdbOutput 'home-activity.txt' @('shell', 'cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME') | Out-Null
Save-AdbOutput 'overlays.txt' @('shell', 'cmd', 'overlay', 'list', '--user', "$userId") | Out-Null
# Android 12L's WebView shell command can select an implementation but has no
# read command. dumpsys is the stable read-only interface and includes the
# current/preferred package plus every valid provider.
Save-AdbOutput 'webview.txt' @('shell', 'dumpsys', 'webviewupdate') | Out-Null
Save-AdbOutput 'users.txt' @('shell', 'pm', 'list', 'users') | Out-Null
Save-AdbOutput 'services.txt' @('shell', 'service', 'list') | Out-Null
Save-AdbOutput 'audio.txt' @('shell', 'dumpsys', 'audio') | Out-Null
Save-AdbOutput 'camera.txt' @('shell', 'dumpsys', 'media.camera') | Out-Null

# This Duo build can mutate roles through `cmd role`, but exposes role holders
# only through dumpsys. Capture the complete role state rather than a subset.
Save-AdbOutput 'roles.txt' @('shell', 'dumpsys', 'role') | Out-Null

$settingNames = @(
    'default_input_method',
    'enabled_accessibility_services',
    'enabled_notification_listeners',
    'assistant'
)
$settingLines = foreach ($settingName in $settingNames) {
    $value = Invoke-Adb -Arguments @('shell', 'settings', 'get', 'secure', $settingName)
    "$settingName=$value"
}
Set-Content -LiteralPath (Join-Path $captureRoot 'secure-defaults.txt') -Value $settingLines -Encoding UTF8

$detailsPath = Join-Path $captureRoot 'microsoft-package-details.txt'
Set-Content -LiteralPath $detailsPath -Value '' -Encoding UTF8
foreach ($line in $microsoftPackages -split "`n") {
    $packageName = ($line -replace "`r", '') -replace '^package:', ''
    if ($packageName -notmatch '^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$') { continue }
    Add-Content -LiteralPath $detailsPath -Value "`n===== $packageName =====" -Encoding UTF8
    Add-Content -LiteralPath $detailsPath -Value (Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $packageName)) -Encoding UTF8
}

$capture = [ordered]@{
    schema = 1
    capturedUtc = (Get-Date).ToUniversalTime().ToString('o')
    build = $build
    userId = $userId
    productDevice = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.product.device')).Trim()
    model = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.product.model')).Trim()
    serial = (Invoke-Adb -Arguments @('get-serialno')).Trim()
}
$capture | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $captureRoot 'capture.json') -Encoding UTF8

$hashLines = Get-ChildItem -LiteralPath $captureRoot -File | Sort-Object Name | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    "$hash  $($_.Name)"
}
Set-Content -LiteralPath (Join-Path $captureRoot 'SHA256SUMS') -Value $hashLines -Encoding ASCII

Write-Host "Captured read-only Duo state in $captureRoot"
Write-Host 'Review packages-microsoft.txt and microsoft-package-details.txt before creating a debloat plan.'

