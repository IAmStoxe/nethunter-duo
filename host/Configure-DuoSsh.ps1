[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PublicKey,
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

$keyPath = (Resolve-Path -LiteralPath $PublicKey).Path
$nonEmptyLines = @(Get-Content -LiteralPath $keyPath | Where-Object { $_ -match '\S' })
if ($nonEmptyLines.Count -ne 1) { throw 'The public-key file must contain exactly one non-empty line.' }
$key = $nonEmptyLines[0].Trim()
$keyPattern = '^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+/=]+(\s+.*)?$'
if ($key -notmatch $keyPattern) { throw 'Unsupported or malformed OpenSSH public key.' }

if ((Invoke-Adb -Arguments @('get-state')) -ne 'device') {
    throw 'The selected ADB target is not online and authorized.'
}
$build = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.incremental')).Trim()
if ($build -ne '202209020048') { throw "Expected Duo build 202209020048; found $build." }
$rootId = Invoke-Adb -Arguments @('shell', 'su', '-c', 'id')
if ($rootId -notmatch 'uid=0') { throw "Magisk root is unavailable: $rootId" }

$keyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $keyPath).Hash.ToLowerInvariant()
$remoteKey = "/data/local/tmp/duo-ssh-$($keyHash.Substring(0, 12)).pub"
Write-Host "Public-key file SHA-256: $keyHash"
Invoke-Adb -Arguments @('push', $keyPath, $remoteKey) | Write-Host
try {
    Invoke-Adb -Arguments @('shell', 'su', '-c', "duo-kali ssh authorize '$remoteKey'") | Write-Host
} finally {
    Invoke-Adb -Arguments @('shell', 'su', '-c', "rm -f '$remoteKey'") | Out-Null
}
Invoke-Adb -Arguments @('shell', 'su', '-c', 'duo-kali ssh start') | Write-Host
Write-Host 'Record and verify this SSH host-key fingerprint on first connection:'
Invoke-Adb -Arguments @('shell', 'su', '-c', 'duo-kali ssh fingerprint') | Write-Host

