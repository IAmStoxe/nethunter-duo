# Rollback and recovery

| Symptom | Next action |
|---|---|
| ADB disappears during a timed USB session | Wait for the profile timer, reconnect the cable, and check `adb devices`. |
| The Duo shows Boot Select | Select **Start** for normal Android. Bootloader commands use `fastboot devices`. ADB becomes available again when Android starts and the host is authorized. |
| Neither tool sees the Duo | Check whether the host detects any USB device, then try a known-good data cable and a direct port. If Windows sees the Duo, check which driver is bound for its current mode. |
| A boot write reports “Device Error” | Treat the partition as unverified. RAM-boot the retained known-good image and compare the active boot partition's SHA-256 with your pre-write record. A matching hash confirms the old image survived. |
| The candidate fails to boot | In bootloader mode, temporarily boot the exact saved rollback image. Once Android works, restore that image to the previously recorded slot using the verified fastbootd procedure below. |

## Restore the previous boot image

Use the rollback image from this device and firmware. Verify its digest against your saved record. Follow the [persistent installation procedure](install.md#persistent-installation-through-fastbootd) using the rollback image in place of the candidate. Confirm the current slot matches your record before writing. After reboot, compare the active boot partition digest with the rollback digest and confirm Android boots normally. Restoring a boot image leaves separately installed apps, the Kali filesystem, and Magisk module data on the device.

## Recover through stock recovery

If Android cannot boot and you have no usable rollback boot, use Microsoft's matching recovery package. Select **Recovery mode** at Boot Select, then **Apply update from ADB** in Android Recovery for the official recovery ZIP. Follow the device-specific instructions for the button sequence and sideload procedure. [Microsoft Surface Duo recovery](https://support.microsoft.com/en-us/surface/recover-surface-duo-if-it-won-t-start).
