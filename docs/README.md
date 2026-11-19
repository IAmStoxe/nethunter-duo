# NetHunter Duo handbook

Stock Android runs the display, touch, audio, and camera stack. The custom kernel supplies device drivers, the Magisk toolkit exposes them through Android root-shell commands, and the Kali ARM64 chroot provides Linux programs on the same kernel. The Duo Technician launcher offers touch controls for common tasks.

| I want to… | Start here |
|---|---|
| SSH from a configured Duo to a server | [First SSH session](operation/field-guide.md#ssh-from-the-duo) |
| Use the Duo as a USB accessory | [USB profiles and ADB restoration](operation/usb-profiles.md) |
| Set up a matching Duo | [Installation](installation/install.md) |
| Recover a failed boot | [Rollback and recovery](installation/recovery.md) |
| Check what actually worked on hardware | [Compatibility and test evidence](reference/compatibility.md) |
| Build the kernel, toolkit, or launcher | [Cached source builds](development/build.md) |
| Prepare a public release | [Publishing](development/publishing.md) |

Host commands assume the repository root as the working directory. Device commands identify the Android or Kali shell where they run.
