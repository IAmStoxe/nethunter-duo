# Installing on Surface Duo 1

This project targets only Surface Duo 1 on final stock build `2022.902.48`
(`ro.build.version.incremental=202209020048`) with kernel release
`4.14.190-duo-p-0_0_0+`. A successful compile or ABI audit is not sufficient
evidence that a boot image is safe to install.

## Before installing

1. Back up user data before bootloader unlocking, which resets the device. Start with an unlocked, Magisk-rooted Duo and authorized ADB. Record the current slot and retain its exact boot image as well as the stock image.
2. Keep an untouched boot image from the exact installed firmware and record
   its SHA-256 outside the phone.
3. Download the matching Microsoft recovery image and current Android SDK
   Platform Tools. Microsoft recommends at least 40% charge and the original
   or an equivalent known-good USB data cable for recovery.

Microsoft's recovery procedure:
<https://support.microsoft.com/surface/recover-surface-duo-if-it-won-t-start>

## Use a prebuilt release

On an x86-64 Linux or WSL2 machine, check out the Git tag for your selected [release](https://github.com/IAmStoxe/nethunter-duo/releases). Download the kernel Image, Magisk module ZIP, launcher APK, and `SHA256SUMS` from that release into a new directory. From that directory run `sha256sum --check SHA256SUMS`. Every entry must report `OK`.

Back at the root of the tagged checkout, set the directory containing those downloads and repack the kernel with your own matching Magisk-patched boot image. This creates a candidate file on the computer.

```bash
release_dir=/absolute/path/to/nethunter-duo-release
kernel/scripts/package-test-boot.sh \
  /path/to/your-matching-magisk-boot.img \
  "$release_dir/nethunter-duo-kernel-2022.902.48-arm64.Image" \
  /path/to/Magisk.apk \
  "$release_dir/duo-technician-test.img"
```

Keep the printed candidate digest for the temporary boot check below. Keep the original boot image separately. The raw `.Image` is the Linux kernel payload. Fastboot needs the repacked `.img` with your device's ramdisk and device tree.

On the Duo, install `duo-technician-magisk.zip` from **Magisk → Modules → Install from storage** and reboot to activate it. Open the optional `DuoTechnician-1.0.0-debug.apk` with Android's package installer. This is the debug-signed preview launcher. Continue with [Activate and verify](#activate-and-verify) and [Candidate preflight](#candidate-preflight) before trying the new kernel.

For a source build, capture the live firmware config and vendor modules and follow the [Docker build guide](../development/build.md). The following host commands are an alternative to the on-phone installers.

## Toolkit and Kali setup

### From Linux or WSL2

Use the same terminal and `DUO_KERNEL_ROOT` as in the [build guide](../development/build.md#install-the-outputs). Check the firmware, root access and battery first. Expect build `202209020048`, UID 0, and at least 40% battery. With one authorized Duo connected, install the ZIP using its digest recorded at build time.

```bash
adb shell getprop ro.build.version.incremental
adb shell su -c id
adb shell dumpsys battery
```

```bash
toolkit="$DUO_KERNEL_ROOT/dist/technician-full/duo-technician-magisk.zip"
read -rp 'Recorded toolkit SHA-256: ' digest
if [[ $digest =~ ^[a-fA-F0-9]{64}$ ]] && printf '%s  %s\n' "$digest" "$toolkit" | sha256sum --check --strict -; then
  adb push "$toolkit" /data/local/tmp/duo-technician-"$digest".zip &&
    adb shell "su -c 'magisk --install-module /data/local/tmp/duo-technician-$digest.zip'" &&
    adb shell rm -f "/data/local/tmp/duo-technician-$digest.zip"
fi
```

For the optional launcher, compare `sha256sum android-app/dist/DuoTechnician-1.0.0-debug.apk` with its recorded digest before running `adb install -r android-app/dist/DuoTechnician-1.0.0-debug.apk`. For the pinned NetHunter apps, place the APKs named in [the manifest](../../apps/SHA256SUMS) under `apps/` and run `android/install-verified-apps.sh`.

### From Windows PowerShell

If using the Windows installer, place the built ZIP and optional launcher in a local folder. The example uses `C:\duo-release`. Supply the recorded digest for each file. Omit `-AppsDirectory` to skip third-party apps, or omit both launcher arguments to skip the custom launcher.

```powershell
.\host\Install-DuoToolkit.ps1 `
  -ToolkitZip C:\duo-release\duo-technician-magisk.zip `
  -ToolkitSha256 EXPECTED_64_HEX_SHA256 `
  -AppsDirectory .\apps `
  -TechnicianApp C:\duo-release\DuoTechnician-1.0.0-debug.apk `
  -TechnicianAppSha256 EXPECTED_64_HEX_SHA256 `
  -Adb C:\path\to\adb.exe `
  -DeviceSerial DEVICE_SERIAL
```

The installer requires an authorized ADB device, final build `202209020048`,
Magisk root, and at least 40% battery. The toolkit always requires an
independently recorded SHA-256. The custom app is installed only when both its
path and digest are supplied. The installer removes its temporary upload and
does not reboot automatically.


### Activate and verify

After a successful module install, reboot Android to activate it. Obtain the pinned NetHunter, Terminal, KeX, and Store APKs from the [official store](https://store.nethunter.com/repo/). For a fresh Kali environment, use the [NetHunter Chroot Manager](https://www.kali.org/docs/nethunter/nethunter-chroot-manager/) to install the full ARM64 rootfs. The toolkit expects `/data/local/nhsystem/kali-arm64/bin/bash`. From an Android root shell run `duo-kali verify` before the runtime test. Back up an existing chroot through the manager before replacing it.

## Candidate preflight

On the working Duo, record the firmware and slot with `adb shell getprop ro.build.version.incremental` and `adb shell getprop ro.boot.slot_suffix`. Match the saved rollback file's digest against the actual boot block. For example, if the device reports `_b`, use `adb shell su -c 'sha256sum /dev/block/by-name/boot_b'`. Substitute the slot reported by your device.

The release workflow must report zero missing and zero mismatched symbols for
both the stock vendor-module audit and the rebuilt QCACLD WLAN module. Verify
the boot image, kernel, module ZIP, and rollback-image hashes before connecting
the phone.

From Android, use `adb reboot bootloader` to enter Boot Select. With exactly one fastboot device attached, inspect rather than alter A/B state:

```bash
fastboot devices
fastboot getvar product
fastboot getvar current-slot
fastboot getvar slot-count
fastboot getvar slot-successful:a
fastboot getvar slot-successful:b
fastboot getvar slot-unbootable:a
fastboot getvar slot-unbootable:b
```

Android documents these A/B variables and notes that ordinary partition
flashing defaults to the current slot:
<https://source.android.com/docs/core/ota/ab/ab_implement>

## Temporary boot first

Do not run a flash command for a new candidate. From the bootloader used for preflight, boot the image in RAM:

```bash
fastboot devices
fastboot boot /path/to/duo-technician-test.img
```

On Windows, `host/Boot-DuoCandidate.ps1` performs the hash and A/B-state checks
above and then issues only the temporary `boot` command. It contains no flash,
erase, or slot-changing operation.

```powershell
.\host\Boot-DuoCandidate.ps1 -ImagePath C:\path\to\candidate.img -ExpectedSha256 EXPECTED_64_HEX_SHA256 -Fastboot C:\path\to\fastboot.exe -DeviceSerial DEVICE_SERIAL
```

The Surface Duo community's device-specific boot-image guide uses the same
temporary-boot method before installation:
<https://github.com/WOA-Project/SurfaceDuo-Guides/blob/main/Install/DualBoot.md#testing-the-newly-made-image>

After Android is fully available, record the kernel release and run the smoke
test. It checks stock-module loading, managed Wi-Fi, optional module loading,
SocketCAN loopback, the Kali chroot, audio/camera services, and kernel fault
logs:

```bash
adb wait-for-device
adb shell uname -a
android/runtime-smoke.sh
```

Also perform the hardware tests the script cannot prove: unlock both screens,
fold/unfold behavior, audible speaker playback, microphone capture, a saved
camera photo, USB-C charging/data, actual HID keystroke delivery, and any
external Wi-Fi, Bluetooth, SDR, serial, storage, or CAN adapter you intend to
use.

## Persistent installation through fastbootd

Review [rollback and recovery](recovery.md) before the first partition write.
Only consider a persistent installation after all checks pass and the rollback
image remains available. Re-read `current-slot` immediately before any manual
write. This repository intentionally does not automate flashing a boot slot.

On Surface Duo 1, bootloader fastboot can accept `fastboot boot` yet reject a
persistent write with `Error flashing partition : Device Error`. The
device-specific installation path is recovery's userspace fastboot
(`fastbootd`). From a working Android boot, the direct transition is:

```bash
adb reboot fastboot
fastboot getvar is-userspace   # must report: yes
fastboot getvar current-slot
fastboot getvar unlocked
fastboot flash boot /path/to/validated-boot.img
fastboot reboot
```

`fastboot flash boot` selects the current A/B slot. Stop if `is-userspace` is
not `yes`, the slot differs from the preflight record, or the device is not
unlocked. If the direct transition is unavailable, follow the Duo community
guide: boot stock recovery, open its menu with Power plus Volume Up, and select
**Enter fastboot**. After installation, verify the running kernel and hash the
active boot block, then perform one ordinary reboot and repeat the runtime
smoke test.
