# Using the Duo in the field

## SSH from the Duo

Open NetHunter Terminal and choose the Kali shell. From an Android terminal, run `su` and then `duo-kali shell` to reach the same environment. In Kali, replace the example account and hostname with your own.

```sh
ssh technician@server.example
```

On first connection, compare the displayed server host-key fingerprint with the one supplied by its administrator. For key authentication, generate a dedicated key in Kali with `ssh-keygen -t ed25519` and enroll the public key with your server. Keep the private key on the Duo. The outgoing connection only needs the client.

On the server, run `tmux new -As field` to create or reattach a session. Detach with Ctrl-b followed by d. After a Wi-Fi interruption, reconnect over SSH and repeat the tmux command.

## Device health and launcher

Run `duo-doctor` and `duo-modprobe verify` in an Android root shell for device health and module integrity. Run `duo-kali verify` for the Kali package and command inventory. In Kali, `ip route`, `ss -t`, and `df -h` show routes, TCP connections, and storage. Use the Duo Technician launcher for health checks or SSH and KeX controls. Spanning the launcher opens a separate output pane.

## SSH into the Duo

With toolkit 1.4.2, rerun public-key authorization when upgrading from 1.4.1 to apply the explicit public-key authentication method. From Linux or WSL2, push your client's **public** key over authorized ADB and configure SSH from an Android root shell:

```bash
adb push ~/.ssh/id_ed25519.pub /data/local/tmp/duo-client.pub
adb shell "su -c 'duo-kali ssh authorize /data/local/tmp/duo-client.pub'" &&
  adb shell "su -c 'duo-kali ssh start'" &&
  adb shell "su -c 'duo-kali ssh fingerprint'"
adb shell rm -f /data/local/tmp/duo-client.pub
```

Alternatively, use the Windows helper to install one reviewed OpenSSH public key,
force root SSH to public-key-only authentication, start the chroot daemon, and
print the host-key fingerprint:

```powershell
.\host\Configure-DuoSsh.ps1 `
  -PublicKey C:\path\to\technician-key.pub `
  -Adb C:\path\to\adb.exe -DeviceSerial DEVICE_SERIAL
```

The helper never accepts or copies a private key. It removes the temporary
device-side public-key file even when configuration fails. Record the printed
host-key fingerprint and verify it from SSH clients.


On the host, connect with `ssh root@DUO_ADDRESS` using the authorized key. For a direct cable connection use the [RNDIS profile](usb-profiles.md). In an Android root shell, use `duo-kali ssh status` to inspect the daemon and `duo-kali ssh stop` when finished.

## Optional package cleanup

Capture the exact package, overlay, role, audio, camera, and enabled-state
inventory before considering any OEM package change:

```powershell
.\host\Capture-DuoState.ps1 -Adb C:\path\to\adb.exe -DeviceSerial DEVICE_SERIAL
```

The capture is private and written under `.work/device-state/`. Review its
`packages-microsoft.txt` and `microsoft-package-details.txt`, copy
`debloat-plan.example.tsv` to a private plan, and add only packages whose role
has been established. The applier checks the exact build, device serial,
Android user, current HOME package, and a protected core-package set. It is a
dry run unless `-Apply` is supplied:

```powershell
.\host\Apply-DuoDebloat.ps1 `
  -Plan C:\private\duo-reviewed-plan.tsv `
  -CaptureDirectory .\.work\device-state\CAPTURE_TIMESTAMP `
  -Adb C:\path\to\adb.exe -DeviceSerial DEVICE_SERIAL

# Repeat only after reviewing the printed plan:
.\host\Apply-DuoDebloat.ps1 <same parameters> -Apply
```

Each applied change uses `pm disable-user --user CURRENT_USER`; system APKs are
not deleted. A restore manifest is updated after every successful change. Use
`Restore-DuoPackages.ps1` first as a dry run and then with `-Apply` to return
the packages to their captured enabled/default states. Reboot and run the full
runtime smoke test after either operation.
