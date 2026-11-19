# USB profiles

From the Duo's Android root shell, run `duo-usb profiles` for profile names. For example, `duo-usb enable acm 60` presents a serial device for one minute. Switching profiles temporarily disconnects USB ADB. Wait for the timer or run `duo-usb disable` on the Duo to restore Android USB.

| Profile | What the connected computer sees |
|---|---|
| `acm` | Serial port. Windows assigns the COM number. |
| `rndis` | Network adapter. With SSH configured, connect to the Duo at `169.254.55.1`. |
| `ncm` | CDC network adapter for hosts with an NCM driver. |
| `ecm`, `eem` | Alternate Ethernet interfaces. The Windows test host lacked the matching drivers. |
| `mass` | Read-only storage. Supply the absolute device-side backing image path after the timeout. |
| `midi`, `uac2` | MIDI or USB Audio Class 2 device. Built-in speaker and microphone checks are separate. |
| HID | Keyboard and mouse, managed separately with `duo-hid enable 30` and `duo-hid disable`. |

Use one profile at a time. The default Android USB configuration returns after the timed session. For sign-in and key setup see [SSH into the Duo](field-guide.md#ssh-into-the-duo).

## Host verification

The host-side smoke helpers use bounded gadget watchdogs and require ADB to
return on the same kernel after every test:

```powershell
.\host\Test-DuoUsbProfiles.ps1 `
  -Serial DEVICE_SERIAL -Adb C:\path\to\adb.exe

.\host\Test-DuoHid.ps1 `
  -Serial DEVICE_SERIAL -Adb C:\path\to\adb.exe

.\host\Test-DuoRndisSsh.ps1 `
  -Serial DEVICE_SERIAL -Adb C:\path\to\adb.exe `
  -ExpectedHostKeySha256 SHA256:RECORDED_ED25519_FINGERPRINT
```

The RNDIS test reads the public ED25519 host key over the already-authorized
ADB channel, checks its recorded fingerprint, waits for a preferred link-local
Windows address, sends a sourced ping, and then requires key-only SSH. The
HID test checks Windows keyboard and mouse enumeration.

For optional manual keyboard delivery testing, run `host/Test-DuoHidDelivery.ps1 -Serial DEVICE_SERIAL` in PowerShell. Click **Start** and use the Duo to enter the displayed marker while the textbox has focus. Switching windows cancels the capture. The helper waits for the watchdog to restore ADB. To check pointer motion, observe it separately during a timed HID session.
