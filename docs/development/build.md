# Building NetHunter Duo with Docker

The release entry point is `kernel/scripts/build-release.sh`. Run it directly in a local Linux or WSL2 terminal. It uses the Docker builder for both kernel profiles and runs the module ABI checks on the host. For a quick check of the available Docker commands, run `kernel/scripts/docker-build.sh --help`.

## Requirements

- An x86-64 Linux machine or x86-64 WSL2 distribution with a working Docker engine
- Bash, Git, Android Platform Tools (`adb` and `fastboot`), kmod (`modprobe`), Go, zip and unzip in the Linux environment
- roughly 80 GB of free space for sources, output, and compiler downloads
- the stock `2022.902.48` `/proc/config.gz` included in `kernel/config/`
- a boot image obtained from the same firmware for local repacking
- Qualcomm Snapdragon LLVM for Android 8.0.6 from the [Surface Duo kernel instructions](https://github.com/microsoft/surface-duo-oss/blob/main/surfaceduo/kernel.md)

Open a terminal on that machine. In WSL2, clone the project under your Linux home directory (for example, `~/src/`). Keep the checkout, output, and cache on the Linux filesystem. Run the commands below in that same shell from the repository root.

Check `docker info` before starting. For the device capture, connect the Duo by USB and confirm that Linux `adb devices` lists it as `device`. On WSL2, attach it to the distribution first. Once you have the private ABI capture, subsequent builds can reuse it with the Duo unplugged. [Microsoft's WSL USB instructions](https://learn.microsoft.com/en-us/windows/wsl/connect-usb).

## Cached release workflow

Run commands from the repository root. The source pins live in [the Microsoft source manifest](../../kernel/microsoft-manifest/default.xml). Keep the large kernel working tree, build profiles, downloads and compiler cache together on the builder between runs. For an interactive session in the cached image, use `kernel/scripts/docker-build.sh shell`.

```bash
export DUO_PROJECT_ROOT="$(pwd)"
export DUO_KERNEL_ROOT="$HOME/src/surface-duo-kernel"
export DUO_SNAPDRAGON_LLVM_ARCHIVE=/path/to/snapdragon-llvm-8.0.6-linux64.tar.gz

kernel/scripts/capture-device-abi.sh .work/device-abi
kernel/scripts/build-release.sh \
  .work/device-abi/config.gz \
  .work/device-abi/modules
```

The capture is read-only on the connected device and refuses firmware other
than final Duo build `202209020048`. It stores proprietary inputs below the
Git-ignored `.work` directory. The release command then:

1. reuses or creates the pinned Ubuntu 20.04 builder and source checkout;
2. builds a conservative ABI-reference profile;
3. builds the full peripheral, field-storage, network-lab, radio, SDR, and
   ABI-neutral CAN profile;
4. rebuilds the official Kali-patched internal QCACLD injection module;
5. compares every required symbol CRC from the live OTA modules; and
6. stages the 150 in-tree modules, dependency map, hashes, metadata, and
   injection module under the cached `dist/technician-full` tree.

Set `DUO_BUILD_PROFILE` to keep independent outputs while testing fragments:

```bash
DUO_BUILD_PROFILE=technician-radio \
  kernel/scripts/docker-build.sh technician \
  kernel/config/stock-duo-p.config.gz \
  kernel/config/technician-peripherals.config \
  kernel/config/technician-extended.config \
  kernel/config/nethunter-radio.config \
  kernel/config/nethunter-can.config
```

The radio fragment includes Bluetooth Arsenal transports, mac80211 and common
USB Wi-Fi adapters with the pinned Kali injection patch, plus HackRF/MSI2500
SDR drivers. The CAN fragment adds CAN RAW/BCM/GW, vcan/vxcan/slcan, and common
USB CAN adapters. Its patch stores per-network-namespace CAN state through
`net_generic()` so enabling CAN does not resize the vendor-visible `struct
net`. Mesh mode is deliberately excluded because it changes
`LL_MAX_HEADER` in Microsoft's 4.14 tree; monitor mode and injection do not
depend on mesh.

The source repositories are fetched at the exact commits recorded in
`kernel/microsoft-manifest/default.xml`. The official Kali NetHunter kernel
builder is also pinned by `kernel/scripts/sync-source.sh`; its 4.14 injection
patch is applied reproducibly. The Docker image is reused unless the Dockerfile
changes; sources, build output, distribution files, downloads, and `ccache`
remain under `DUO_KERNEL_ROOT` between invocations.

Microsoft's build uses Qualcomm Snapdragon LLVM 8.0.6. The setup helper does
not redistribute it or trust a third-party mirror: it accepts the archive from
the official download, verifies SHA-256
`8dcd0979171fd71b8aa477543a6a434834d848e2231e012b6f459e87d3d26b9e`,
then reuses the extracted toolchain on later builds.

The `image` command compares the Dockerfile SHA-256 label and returns without a
build when the cached image matches. To force a Docker build, use
`rebuild-image`; Docker can still reuse unchanged layers. To discard build
output, remove a specific profile below `DUO_KERNEL_ROOT/out` and its matching
`dist` directory; do not delete the source or cache trees.

## Validation

The build script verifies the stock release string, module versioning, HID,
and requested fragment settings. Before packing an image, also run the stock
module ABI audit:

```bash
kernel/scripts/audit-stock-module-abi.sh \
  /path/to/ota-modules \
  /path/to/reference/Module.symvers \
  "$DUO_KERNEL_ROOT/out/technician/kernel/msm-4.14/Module.symvers"
```

Treat any changed or missing versioned symbol as a failed candidate. The
release script enforces this for both the stock vendor modules and rebuilt
QCACLD module. Repack
only with the matching stock/Magisk ramdisk and device tree, verify the output
hash, then test it with `fastboot boot` before any persistent write.

Create a local test image with explicit private inputs; none of them are added
to the source repository:

```bash
kernel/scripts/package-test-boot.sh \
  /path/to/matching-magisk-boot.img \
  "$DUO_KERNEL_ROOT/out/technician-full/kernel/msm-4.14/arch/arm64/boot/Image" \
  /path/to/Magisk.apk \
  "$DUO_KERNEL_ROOT/dist/technician-full/duo-technician-test.img"
```

The repacker unpacks its output again and byte-compares the ramdisk and every
device-tree component before emitting the image. A successful repack is still
only a candidate: complete the runtime gate before writing either boot slot.

## What is intentionally not published

Boot images, firmware, APKs, root filesystems, proprietary toolchain archives,
private host details, captures, and built kernel modules stay outside Git. The
public repository contains the exact source revisions, patches, config
fragments, build logic, and validation tooling needed to recreate them.

## Module payload and runtime policy

`stage-module-payload.sh` flattens the kernel modules only after checking for
filename collisions. It writes `modules.dep`, `modules.sha256`, and build
metadata so the Android loader can resolve dependencies and verify every file.
Large radio and peripheral groups load only when explicitly requested; they
are not auto-loaded at boot, preserving battery life and stock Android device
ownership.

Build the Magisk runtime toolkit from the staged payload with a local Go
toolchain (Go is used only for the static ARM64 helpers):

```bash
magisk/build-module.sh \
  "$DUO_KERNEL_ROOT/dist/technician-full/module-payload-<image-hash>" \
  "$DUO_KERNEL_ROOT/dist/technician-full/duo-technician-magisk.zip"
```

## Android launcher

Build with JDK 17 and Android SDK platform 34:

```bash
export ANDROID_SDK_ROOT=/path/to/Android/Sdk
bash android-app/build.sh
```

or from PowerShell:

```powershell
.\android-app\build.ps1
```

Both scripts download Gradle 8.9 only when absent, verify it against Gradle's
published SHA-256, reuse the Gradle/Maven cache, run Android lint, and place the
debug-signed APK in `android-app/dist/`. The APK is a local generated artifact
and is excluded from Git. Record the printed digest outside the repository and
pass it to `host/Install-DuoToolkit.ps1`; the installer will refuse an APK whose
bytes do not match that digest.

## Install the outputs

Record the SHA-256 printed by each packaging step. These paths apply to the build commands above.

| Build output | Local path | Used for |
|---|---|---|
| Boot image | `$DUO_KERNEL_ROOT/dist/technician-full/duo-technician-test.img` | RAM boot and, after verification, persistent install |
| Magisk toolkit | `$DUO_KERNEL_ROOT/dist/technician-full/duo-technician-magisk.zip` | Magisk module installation |
| Optional launcher | `android-app/dist/DuoTechnician-1.0.0-debug.apk` | Android package installation |

Use these files directly from Linux or WSL2. Follow [installation and validation](../installation/install.md) on the same computer.
