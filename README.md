# Azure VPN Client — package for App-Store-less Macs (Parallels VM)

The **Azure VPN Client** is Mac App Store only. A Parallels macOS VM (especially
Apple Silicon) **can't sign into the App Store**, so it can't install the app the
normal way. This repackages the already-installed app into a portable `.zip` /
`.dmg` you can drop onto the VM.

## Why it's possible

Inspected the installed bundle and confirmed:

- **No FairPlay DRM** — the Mach-O has no `LC_ENCRYPTION_INFO`/`cryptid`. Unlike
  iOS apps, this MAS app ships unencrypted, so a copied bundle is runnable.
- **Validly Apple-signed** — `Authority=Apple Mac OS Application Signing`,
  Gatekeeper `accepted`. The signature survives a `ditto`/`hdiutil` round-trip.
- **Universal binary** (x86_64 + arm64) — runs on Intel-emulated or Apple Silicon VMs.

The only thing that could break this: if a future update enforces strict App
Store **receipt validation** at launch (would quit with exit 173 and bounce to
the App Store). It currently doesn't. The build script also warns if a future
update adds FairPlay encryption.

## Build (run on the host Mac that has the app installed)

After an App Store update lands, just re-run:

```bash
./package-azure-vpn.sh
# or specify an output dir:
./package-azure-vpn.sh ~/Desktop
# build AND publish a GitHub release tagged with the app version:
./package-azure-vpn.sh --release
```

Reads the app's real version (`CFBundleShortVersionString`) and produces
`AzureVPNClient-<version>.zip` and `AzureVPNClient-<version>.dmg` (default:
`~/Desktop`), verifying the signature round-trips before finishing.

With `--release`, it also creates a GitHub release tagged `v<version>` and
uploads the `.zip` + `.dmg` as assets (requires an authenticated `gh` CLI). If
that tag already exists, the assets are re-uploaded with `--clobber`.

## Install on the Parallels VM

1. Transfer the `.dmg` (or `.zip`) into the VM (shared folder / AirDrop / drag-drop).
2. Install:
   - **DMG:** mount, drag the app to `/Applications`.
   - **ZIP:** unpack with `ditto` (not `unzip`, which mangles framework symlinks):
     ```bash
     ditto -x -k ~/Downloads/AzureVPNClient-<version>.zip /Applications/
     ```
3. Clear quarantine so Gatekeeper doesn't block it:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Azure VPN Client.app"
   ```
4. Launch. First connection prompts to approve the VPN/Network Extension in
   **System Settings → General → VPN & Device Management** (or **Network**). Approve it.

## Fallback if it ever refuses to launch (receipt validation)

The Azure VPN gateway usually also offers point-to-site over **IKEv2** and
**OpenVPN**, neither of which needs the Microsoft client:

- **IKEv2** → configure natively in **System Settings → VPN**.
- **OpenVPN** → download the OpenVPN profile from the Azure portal (VPN gateway →
  Point-to-site configuration → Download VPN client) and import into OpenVPN Connect.

This only falls short if the gateway is locked to **Microsoft Entra (Azure AD)**
auth, which requires the Azure VPN Client specifically.
