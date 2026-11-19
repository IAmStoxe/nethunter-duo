[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Serial,
    [string]$Adb = 'C:\Tools\platform-tools\adb.exe',
    [string]$Target = '169.254.55.1',
    [string]$User = 'root',
    [Parameter(Mandatory)]
    [ValidatePattern('^SHA256:[A-Za-z0-9+/]{43}$')]
    [string]$ExpectedHostKeySha256,
    [string]$ExpectedUnamePattern = '4\.14\.190-duo-p-0_0_0\+',
    [ValidateRange(30, 3600)]
    [int]$ActiveSeconds = 75
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
$hostKeyCommand = 'duo-kali exec cat /etc/ssh/ssh_host_ed25519_key.pub'
$deviceHostKey = (& $Adb -s $Serial shell su -c $hostKeyCommand 2>&1) -join ' '
if ($LASTEXITCODE -ne 0 -or $deviceHostKey -notmatch '^ssh-ed25519 [A-Za-z0-9+/=]+(?:\s+.*)?$') {
    throw "Could not read the Kali ED25519 host key over authorized ADB: $deviceHostKey"
}
$command = "duo-usb enable rndis $ActiveSeconds"
$activation = & $Adb -s $Serial shell su -c $command 2>&1
if ($LASTEXITCODE -ne 0 -and (Get-AdbState) -eq 'device') {
    throw "RNDIS activation failed: $($activation -join ' ')"
}

$deadline = (Get-Date).AddSeconds(25)
$rndisDevices = @()
do {
    $rndisDevices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1D6B&PID_0106' })
    if ($rndisDevices.Count -gt 0) { break }
    Start-Sleep -Milliseconds 300
} while ((Get-Date) -lt $deadline)
if ($rndisDevices.Count -eq 0) { throw 'The RNDIS gadget did not enumerate.' }
Start-Sleep -Seconds 3
$rndisDevices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_1D6B&PID_0106' })
$rndisDevices | Select-Object Status, Class, FriendlyName, InstanceId |
    Format-Table -AutoSize
if ($rndisDevices.Where({ $_.Class -eq 'Net' -and $_.Status -eq 'OK' }).Count -eq 0) {
    throw 'Windows did not start the RNDIS network interface.'
}

$deadline = (Get-Date).AddSeconds(25)
$sourceAddress = $null
do {
    $adapter = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -match 'Remote NDIS' -and $_.Status -eq 'Up' } |
        Select-Object -First 1
    if ($adapter) {
        $address = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -like '169.254.*' } |
            Select-Object -First 1
        if ($address) {
            $sourceAddress = $address.IPAddress
            break
        }
    }
    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)
if (-not $sourceAddress) { throw 'RNDIS did not receive a preferred link-local address.' }
$pingOutput = (& ping.exe -n 2 -w 3000 -S $sourceAddress $Target 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0 -or $pingOutput -notmatch "Reply from $([regex]::Escape($Target)):") {
    throw "RNDIS ping failed: $pingOutput"
}
Write-Host "RNDIS ping from $sourceAddress to $Target passed."

$knownHosts = [IO.Path]::GetTempFileName()
try {
    $keyFields = $deviceHostKey -split '\s+'
    Set-Content -LiteralPath $knownHosts `
        -Value "$Target $($keyFields[0]) $($keyFields[1])" -Encoding ascii
    $fingerprintOutput = (& ssh-keygen.exe -lf $knownHosts 2>&1) -join ' '
    if ($LASTEXITCODE -ne 0 -or $fingerprintOutput -notmatch [regex]::Escape($ExpectedHostKeySha256)) {
        throw "SSH host-key mismatch: $fingerprintOutput"
    }
    Write-Host "SSH host key verified: $ExpectedHostKeySha256"

    $sshOutput = & ssh.exe -o BatchMode=yes -o IdentitiesOnly=no `
        -o ConnectTimeout=8 -o ConnectionAttempts=3 `
        -o "UserKnownHostsFile=$knownHosts" -o StrictHostKeyChecking=yes `
        "$User@$Target" `
        'echo DUO_SSH_OK; id -u; uname -a; command -v nmap; command -v tmux' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Authenticated SSH failed: $($sshOutput -join ' ')" }
    $sshOutput | Write-Host
    if (($sshOutput -join "`n") -notmatch '(?m)^DUO_SSH_OK\r?\n0(?:\r?$)') {
        throw 'SSH completed without the root success marker.'
    }
} finally {
    Remove-Item -LiteralPath $knownHosts -Force -ErrorAction SilentlyContinue
}

Wait-Adb ($ActiveSeconds + 40)
Start-Sleep -Seconds 2
$uname = (& $Adb -s $Serial shell uname -a 2>$null) -join ' '
if ($uname -notmatch $ExpectedUnamePattern) {
    throw "Unexpected kernel after RNDIS restore: $uname"
}
Write-Host "RNDIS restored ADB on the expected candidate kernel: $uname"
