[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Serial,
    [string]$Adb = 'adb',
    [ValidateRange(25, 120)][int]$ActiveSeconds = 60,
    [string]$ExpectedUnamePattern = '4\.14\.190-duo-p-0_0_0\+'
)

$ErrorActionPreference = 'Stop'
if ((& $Adb -s $Serial get-state) -ne 'device') { throw 'Authorize the selected Duo in ADB first.' }
$before = (& $Adb -s $Serial shell uname -a) -join ' '
if ($LASTEXITCODE -ne 0 -or $before -notmatch $ExpectedUnamePattern) { throw 'Unexpected starting kernel.' }
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object Windows.Forms.Form
$form.Text = 'Surface Duo keyboard delivery'
$form.Width = 540
$form.Height = 200
$form.StartPosition = 'CenterScreen'
$label = New-Object Windows.Forms.Label
$label.SetBounds(12,12,500,55)
$label.Text = 'Click Start, then use the Duo to type DUO_HID_REPORT_OK into the box. Keep this window focused. Switching windows cancels the test.'
$box = New-Object Windows.Forms.TextBox
$box.SetBounds(12,72,490,24)
$box.MaxLength = 17
$box.Enabled = $false
$start = New-Object Windows.Forms.Button
$start.SetBounds(12,110,100,30)
$start.Text = 'Start'
$form.Controls.AddRange(@($label,$box,$start))
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 1000
$state = @{ started = $false; result = 'Cancelled'; expires = $null }
$start.Add_Click({
    $box.Enabled = $true
    [void]$box.Focus()
    if (-not $box.Focused) { return }
    $start.Enabled = $false
    $state.started = $true
    $state.expires = (Get-Date).AddSeconds($ActiveSeconds)
    try {
        & $Adb -s $Serial shell "su -c 'duo-hid enable $ActiveSeconds'" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'HID activation failed.' }
        $timer.Start()
    } catch {
        $state.result = $_.Exception.Message
        $form.Close()
    }
})
$box.Add_TextChanged({
    if ($state.started -and $box.Focused -and $box.Text -ceq 'DUO_HID_REPORT_OK') {
        $state.result = 'Matched'
        $form.Close()
    }
})
$form.Add_Deactivate({ if ($state.started -and $form.Visible) { $form.Close() } })
$timer.Add_Tick({
    if ((Get-Date) -ge $state.expires) {
        $state.result = 'Timed out waiting for the marker.'
        $form.Close()
    }
})
try { [void]$form.ShowDialog() } finally { $timer.Dispose(); $form.Dispose() }
if (-not $state.started) { throw 'Test cancelled before activation.' }

# Activation is asynchronous. Wait beyond the watchdog before checking USB.
$remaining = [int][math]::Ceiling(($state.expires - (Get-Date)).TotalSeconds)
if ($remaining -gt 0) { Start-Sleep -Seconds $remaining }
$deadline = (Get-Date).AddSeconds(30)
do {
    $connected = @(& $Adb devices) -contains "$Serial`tdevice"
    if ($connected) { break }
    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)
if (-not $connected) { throw 'ADB did not return after the watchdog.' }
$after = (& $Adb -s $Serial shell uname -a) -join ' '
if ($after -ne $before) { throw 'Kernel changed during the test.' }
if ($state.result -ne 'Matched') { throw $state.result }
Write-Host 'Keyboard marker received in the focused textbox. ADB restored.'
