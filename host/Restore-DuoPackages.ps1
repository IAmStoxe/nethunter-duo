[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Manifest,
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

$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$lines = Get-Content -LiteralPath $manifestPath
$metadata = @{}
$entries = [System.Collections.Generic.List[object]]::new()
foreach ($rawLine in $lines) {
    if ($rawLine -match '^#\s+(build|serial|user)\t(.+)$') {
        $metadata[$Matches[1]] = $Matches[2].Trim()
        continue
    }
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $fields = $rawLine -split "`t", 3
    if ($fields.Count -lt 2) { throw "Malformed restore line: $rawLine" }
    $packageName = $fields[0].Trim()
    $action = $fields[1].Trim()
    if ($packageName -notmatch '^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$') {
        throw "Invalid package name in restore manifest: $packageName"
    }
    if ($action -notin @('default-state', 'enable')) { throw "Invalid restore action for $packageName" }
    $entries.Add([pscustomobject]@{ Package = $packageName; Action = $action })
}
foreach ($required in @('build', 'serial', 'user')) {
    if (-not $metadata.ContainsKey($required)) { throw "Restore manifest is missing $required metadata." }
}
if ($entries.Count -eq 0) { throw 'The restore manifest has no package entries.' }

if ((Invoke-Adb -Arguments @('get-state')) -ne 'device') {
    throw 'The selected ADB target is not online and authorized.'
}
$build = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.incremental')).Trim()
$serial = (Invoke-Adb -Arguments @('get-serialno')).Trim()
$userIdText = (Invoke-Adb -Arguments @('shell', 'am', 'get-current-user')).Trim()
if ($build -ne $metadata.build -or $serial -ne $metadata.serial -or $userIdText -ne $metadata.user) {
    throw 'The connected build, serial, or Android user does not match this restore manifest.'
}

Write-Host "Restore plan for $($entries.Count) package(s), user ${userIdText}:"
foreach ($entry in $entries) { Write-Host "  $($entry.Action) $($entry.Package)" }
if (-not $Apply) {
    Write-Host 'Dry run only. Re-run with -Apply to restore these packages.'
    return
}

foreach ($entry in $entries) {
    Invoke-Adb -Arguments @('shell', 'pm', $entry.Action, '--user', $userIdText, $entry.Package) | Write-Host
    $enabled = Invoke-Adb -Arguments @('shell', 'pm', 'list', 'packages', '--user', $userIdText, '-e', $entry.Package)
    if (($enabled -split "`n") -notcontains "package:$($entry.Package)") {
        throw "Package was not restored to the enabled set: $($entry.Package)"
    }
}
Write-Host 'Package states restored. Reboot Android and run the complete smoke test.'

