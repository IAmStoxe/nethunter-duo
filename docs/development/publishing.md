# Publishing checklist

The working directory may contain private recovery material and large upstream
binaries. Push source and documentation to Git. Attach the project-built kernel, module ZIP, launcher and their SHA-256 manifest to a versioned GitHub Release. Keep stock boot images, proprietary recovery files, third-party APKs, and private captures off the release.

1. Work from a checkout of [NetHunter Duo](https://github.com/IAmStoxe/nethunter-duo).
2. Review `.gitignore` and stage the intended source changes.
3. Run `kernel/scripts/public-audit.sh`. Set `DUO_PRIVATE_PATTERNS` to an
   additional `rg` regular expression containing any private SSIDs, hostnames,
   usernames, or device identifiers known to the repository owner.
4. Inspect the staged file list and staged diff.
5. Confirm that no boot image, APK, rootfs, recovery image, Windows image,
   kernel module, capture, serial number, SSID, host address, or user path is
   staged.
6. Confirm the repository license and retain upstream copyright/license
   notices for every derived patch before release.

```bash
DUO_PRIVATE_PATTERNS='example-ssid|example-host' kernel/scripts/public-audit.sh
git status --short
git diff --cached --stat
```

In a fresh Linux checkout, run `bash tests/check-checkout.sh`. It checks the executable bits used by the handbook, invokes entry points without a connected device, and exercises the SSH policy checker with valid and invalid settings. When staging a new executable on Windows, use `git add --chmod=+x -- path/to/script` and inspect its index mode with `git ls-files --stage -- path/to/script`.

The included GitHub Actions workflow repeats shell syntax checks, validates
the pinned config and manifest, cross-compiles the ARM64 helper programs,
builds and lints the Android launcher from source, and runs the publication
audit on pushes and pull requests. The generated APK remains excluded from the
repository and is not uploaded as a CI artifact.
