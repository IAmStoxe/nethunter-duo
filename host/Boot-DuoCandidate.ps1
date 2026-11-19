[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ImagePath,

    [string] $ExpectedSha256,
    [string] $Fastboot = 'fastboot',
    [string] $DeviceSerial
)

$ErrorActionPreference = 'Stop'
$image = (Resolve-Path -LiteralPath $ImagePath).Path
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $image).Hash.ToLowerInvariant()
if ($ExpectedSha256 -and $actualHash -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "Candidate SHA-256 mismatch. Expected $ExpectedSha256; found $actualHash."
}

function Invoke-FastbootProcess {
    param(
        [string[]] $Arguments,
        [int] $TimeoutSeconds
    )

    $quotedArguments = @($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    })
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Fastboot
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Could not start fastboot.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "fastboot $($Arguments -join ' ') timed out after $TimeoutSeconds seconds."
        }
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $output = @(($stdout + $stderr) -split "`r?`n" | Where-Object { $_ -match '\S' })
        [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
    } finally {
        $process.Dispose()
    }
}

$deviceResult = Invoke-FastbootProcess -Arguments @('devices') -TimeoutSeconds 10
$deviceLines = @($deviceResult.Output | Where-Object { $_ -match '\S' })
if ($deviceResult.ExitCode -ne 0) { throw "fastboot devices failed (exit $($deviceResult.ExitCode)): $($deviceLines -join "`n")" }
$serials = @($deviceLines | ForEach-Object { ($_ -split '\s+')[0] })
if ($DeviceSerial) {
    if ($serials -notcontains $DeviceSerial) { throw "Fastboot target $DeviceSerial is not attached." }
    $serial = $DeviceSerial
} else {
    if ($serials.Count -ne 1) { throw "Expected exactly one fastboot device; found $($serials.Count)." }
    $serial = $serials[0]
}

function Invoke-Fastboot {
    param(
        [string[]] $Arguments,
        [int] $TimeoutSeconds = 15
    )

    $processArguments = @('-s', $serial) + $Arguments
    $result = Invoke-FastbootProcess -Arguments $processArguments -TimeoutSeconds $TimeoutSeconds
    if ($result.ExitCode -ne 0) {
        throw "fastboot $($Arguments -join ' ') failed:`n$($result.Output -join "`n")"
    }
    return ($result.Output -join "`n").Trim()
}

Write-Host "Candidate SHA-256: $actualHash"
Write-Host "Fastboot serial: $serial"
foreach ($variable in @(
    'product', 'unlocked', 'current-slot', 'slot-count',
    'slot-successful:a', 'slot-successful:b',
    'slot-unbootable:a', 'slot-unbootable:b'
)) {
    $value = Invoke-Fastboot -Arguments @('getvar', $variable)
    Write-Host $value
    if ($variable -eq 'unlocked' -and $value -match 'unlocked:\s*no') {
        throw 'The bootloader reports that it is locked.'
    }
}

Write-Host 'RAM-booting the candidate. No partition will be flashed or erased.'
Invoke-Fastboot -Arguments @('boot', $image) -TimeoutSeconds 120 | Write-Host

