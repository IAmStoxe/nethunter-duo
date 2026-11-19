# Compatibility and verification

Test device: Surface Duo 1, Android 12 `2022.902.48`, kernel build `#8`, toolkit `1.4.1`. A compiled module establishes availability. A loaded module establishes kernel compatibility. End-to-end results below identify the hardware or host used.

Toolkit source version 1.4.2 adds checks for every required SSH setting. The 1.4.2 policy checker passed offline regression tests. The hardware results below were recorded with 1.4.1.

The tested boot image had SHA-256 `bcaa35980b491e6b2b2e1249830454d56ad919369ab9ab452b7408d06316aca6`. Its kernel Image had SHA-256 `429e0b8afc889fbdd6e10ddb97d75b457d9c29a444161465fc4d2ee58c2162e3`. The active boot block matched the image after an ordinary reboot. Record your own build digests when using a different ramdisk or toolchain.

The build is intentionally split into a stock-compatible kernel image, 150
opt-in in-tree modules, and one separately rebuilt internal Qualcomm WLAN
module. Optional groups are not loaded at boot, which preserves Android's
normal hardware ownership and battery behavior.

| Capability | Implementation | Toolkit command | Current evidence |
|---|---|---|---|
| Stock Android hardware | Microsoft SM8150 display, touch, fold, modem, audio, camera, power and vendor modules retained | `duo-doctor` | Final image persistently boots from slot `b`; all 2,194 audited stock-module requirements match, required vendor modules load, and the runtime fault scan is clean |
| Full Kali environment | Kali Rolling ARM64 chroot and `kali-nethunter-full` | `duo-kali shell`, `duo-kali verify` | Installed and package database verified on the development Duo |
| SSH and KeX | OpenSSH server/client, mosh, TigerVNC/KeX; root SSH is refused unless effective policy is key-only | `host/Configure-DuoSsh.ps1`, `duo-kali ssh start`, `duo-kali kex start` | Key-only root SSH authenticated over RNDIS after the ED25519 host key was verified; KeX binaries are installed but its GUI remains a manual test |
| Internal Wi-Fi monitor/injection | Kali QCACLD patch plus Duo compatibility fixes | `duo-wifi monitor`, `duo-wifi test` | Final module is 417/417 ABI-compatible; channel-149 monitor mode and a harmless broadcast probe completed successfully in firmware on the final candidate |
| External monitor-mode Wi-Fi | mac80211 plus common Atheros, Ralink/MediaTek, Realtek and Zydas USB drivers | `duo-modprobe wifi` | Built and hashed; individual physical adapters remain separate tests |
| USB HID keyboard/mouse | Isolated configfs `g2` boot keyboard and relative mouse; Android `g1`/ADB restored by session-aware watchdog | `duo-hid type`, `duo-hid key`, `duo-hid mouse` | Windows started the composite parent and both interfaces, captured the exact harmless keyboard marker and a real relative pointer move, then returned to ADB on kernel `#8` |
| Device-mode USB utilities | Isolated configfs `g3` profiles for ACM, ECM/EEM, RNDIS/NCM, read-only file-backed storage, MIDI and USB Audio Class 2 | `duo-usb enable PROFILE TIMEOUT` | ACM, NCM, read-only storage, MIDI and UAC2 started on Windows; RNDIS passed DHCP/ping/key-only SSH; ECM/EEM gadget paths work but Windows lacks their class drivers; every profile restored ADB |
| Bluetooth Arsenal transports | USB HCI, UART, virtual HCI, RFCOMM, BNEP and HIDP | `duo-modprobe bluetooth` | Built and hashed; physical adapters and Arsenal UI remain separate tests |
| SDR | RTL2832 SDR/DVB, RTL-SDR tuners, Airspy, HackRF and MSI2500 | `duo-modprobe sdr` | Modules build; Kali has `rtl_test` and `hackrf_info`; physical receivers remain separate tests |
| CAN/CARsenal | CAN RAW/BCM/GW, vcan/vxcan/slcan and common USB CAN drivers | `duo-modprobe can` | ABI-neutral namespace patch passes the stock audit and vcan looped a `DE AD BE EF` frame; physical adapters remain separate tests |
| Embedded/serial work | CDC ACM and broad FTDI, CP210x, CH341, PL2303, Keyspan, TI, Qualcomm and modem serial drivers | `duo-modprobe serial` | Core serial modules previously loaded; expanded set is built and hashed |
| USB networking/modems | EEM, MBIM, QMI WWAN, RNDIS host and SMSC Ethernet | `duo-modprobe network` | Core network modules previously loaded; expanded set is built and hashed |
| Local/remote storage | UAS, ISO/UDF/NTFS/SquashFS, NBD, NFSv2/v3/v4, CIFS and iSCSI | `duo-modprobe storage`, `duo-modprobe remote` | Representative local and remote modules load on the final candidate; live remote endpoints remain environment-specific tests |
| USB over IP | USB/IP core, host and virtual host controller | `duo-modprobe usbip` | Built and hashed; endpoint testing remains |
| Network lab | macvlan/macvtap, VXLAN, GRE, IPIP, ipset and fq_codel | `duo-modprobe lab` | macvlan, VXLAN, ipset and fq_codel load on the final candidate with stock VETH/bonding/dummy/mirred settings preserved |
| Audio and camera | Stock Android HAL and kernel paths retained | `duo-doctor`, `android/runtime-smoke.sh` | Services and ALSA devices present; audible playback, microphone capture and saved-photo tests remain manual |
| One-tap Android console | Native, dependency-light Duo-aware launcher with guarded root actions and static shortcuts | `android-app/build.sh` | Final source builds and lints cleanly on the build host; the APK installs, launches and renders on the development Duo without a recorded process crash |
| Reversible OEM cleanup | Per-user package disablement with a device inventory and restore manifest | `host/Capture-DuoState.ps1`, `host/Apply-DuoDebloat.ps1` | On the development Duo, 14 selected apps stayed disabled after reboot and the complete runtime smoke test passed. A restore manifest was recorded. |

The final full image passed the temporary-boot procedure in
[Installation](../installation/install.md), was installed through recovery `fastbootd`, and
passed a normal persistent reboot plus the complete runtime smoke test.
“Built and hashed” means the exact module is present in the v1.4.1 payload and
its kernel ABI passed; it does not claim that every third-party USB product has
been physically tested.
