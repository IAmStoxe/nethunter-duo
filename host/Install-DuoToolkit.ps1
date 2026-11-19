[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ToolkitZip,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string] $ToolkitSha256,

    [string] $AppsDirectory,
    [string] $TechnicianApp,
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string] $TechnicianAppSha256,
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

$toolkit = (Resolve-Path -LiteralPath $ToolkitZip).Path
$toolkitHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $toolkit).Hash.ToLowerInvariant()
$expectedToolkitHash = $ToolkitSha256.ToLowerInvariant()
if ($toolkitHash -ne $expectedToolkitHash) {
    throw "Toolkit SHA-256 mismatch: expected $expectedToolkitHash, found $toolkitHash"
}
if ((Invoke-Adb -Arguments @('get-state')) -ne 'device') {
    throw 'The selected ADB target is not online and authorized.'
}

$build = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.incremental')).Trim()
if ($build -ne '202209020048') {
    throw "Expected Surface Duo build 202209020048; found $build."
}
$rootId = Invoke-Adb -Arguments @('shell', 'su', '-c', 'id')
if ($rootId -notmatch 'uid=0') {
    throw "Magisk root is unavailable: $rootId"
}

$batteryDump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'battery')
$levelMatch = [regex]::Match($batteryDump, '(?m)^\s*level:\s*(\d+)\s*$')
if (-not $levelMatch.Success) { throw 'Could not read battery level.' }
$batteryLevel = [int] $levelMatch.Groups[1].Value
if ($batteryLevel -lt 40) { throw "Battery is only $batteryLevel%; charge to at least 40%." }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($toolkit)
try {
    $entryNames = @($archive.Entries | ForEach-Object FullName)
    foreach ($required in @('module.prop', 'payload/build-info', 'payload/wlan-injection.sha256')) {
        if ($entryNames -notcontains $required) { throw "Toolkit archive is missing $required." }
    }
    $moduleEntry = $archive.GetEntry('module.prop')
    $reader = [System.IO.StreamReader]::new($moduleEntry.Open())
    try { $moduleProperties = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ($moduleProperties -notmatch '(?m)^id=duo-technician\s*$') {
        throw 'This is not a Surface Duo Technician Toolkit module.'
    }
} finally {
    $archive.Dispose()
}

if ($AppsDirectory) {
    $apps = (Resolve-Path -LiteralPath $AppsDirectory).Path
    $manifest = Join-Path $apps 'SHA256SUMS'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw "Missing app hash manifest: $manifest"
    }
    $requiredApps = @(
        'NetHunterStore.apk',
        'NetHunterTerminal.apk',
        'NetHunterKeX.apk',
        'NetHunter-2026.3.apk'
    )
    $expected = @{}
    foreach ($line in Get-Content -LiteralPath $manifest) {
        if ($line -match '^([0-9a-fA-F]{64})\s+(.+)$') {
            $expected[$Matches[2]] = $Matches[1].ToLowerInvariant()
        }
    }
    foreach ($name in $requiredApps) {
        $apk = Join-Path $apps $name
        if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw "Missing $apk" }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash.ToLowerInvariant()
        if (-not $expected.ContainsKey($name) -or $actual -ne $expected[$name]) {
            throw "SHA-256 check failed for $name"
        }
        Write-Host "Installing verified $name"
        Invoke-Adb -Arguments @('install', '-r', '--user', '0', $apk) | Write-Host
    }
}

if ([bool] $TechnicianApp -ne [bool] $TechnicianAppSha256) {
    throw 'Supply both -TechnicianApp and -TechnicianAppSha256, or neither.'
}
if ($TechnicianApp) {
    $technicianApk = (Resolve-Path -LiteralPath $TechnicianApp).Path
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $technicianApk).Hash.ToLowerInvariant()
    $expectedTechnicianHash = $TechnicianAppSha256.ToLowerInvariant()
    if ($actual -ne $expectedTechnicianHash) {
        throw "SHA-256 check failed for the Duo Technician app: expected $expectedTechnicianHash, found $actual"
    }
    Write-Host "Installing verified Duo Technician app ($actual)"
    Invoke-Adb -Arguments @('install', '-r', '--user', '0', $technicianApk) | Write-Host
}

$remoteZip = "/data/local/tmp/duo-technician-$($toolkitHash.Substring(0, 12)).zip"
Write-Host "Toolkit SHA-256: $toolkitHash"
Invoke-Adb -Arguments @('push', $toolkit, $remoteZip) | Write-Host
try {
    Invoke-Adb -Arguments @('shell', 'su', '-c', "magisk --install-module '$remoteZip'") | Write-Host
} finally {
    Invoke-Adb -Arguments @('shell', 'su', '-c', "rm -f '$remoteZip'") | Out-Null
}

Write-Host 'Toolkit installation completed. Reboot Android before using its commands.'

