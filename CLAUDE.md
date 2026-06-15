# CLAUDE.md — azure-vpn-packaging

## Purpose

Repackage the Mac App Store **Azure VPN Client** into a portable `.zip` + `.dmg`
so it can be installed on a Mac with no App Store access — specifically a
**Parallels macOS VM** (Apple Silicon VMs can't sign into the App Store, iCloud,
or FairPlay services).

## How it works (the key facts)

Verified by inspecting the installed bundle at `/Applications/Azure VPN Client.app`:

- **No FairPlay DRM** — the Mach-O has no `LC_ENCRYPTION_INFO`/`cryptid` segment.
  Unlike iOS apps, this MAS app ships unencrypted, so a copied bundle is runnable.
- **Validly Apple-signed** — `Authority=Apple Mac OS Application Signing`,
  Team `UBF8T346G9` (Microsoft), bundle id `com.microsoft.AzureVpnMac`. Gatekeeper
  `accepted`; the signature survives a `ditto`/`hdiutil` round-trip.
- **Universal binary** (x86_64 + arm64) — runs on Intel-emulated or Apple Silicon VMs.
- Uses a **Network Extension** (`packet-tunnel-provider`), sandbox, app groups —
  these come from the signature, not the receipt, so they work on the copy.

This was confirmed working on the user's Parallels VM.

## Files

- `package-azure-vpn.sh` — rebuild script. Run on the **host Mac** that installed
  the app from the App Store, after an update. Reads the app's
  `CFBundleShortVersionString` and produces `AzureVPNClient-<version>.{zip,dmg}`
  (default `~/Desktop`, override with the first positional arg) and verifies the
  signature round-trips. Pass `--release` to also publish a GitHub release tagged
  `v<version>` with both artifacts as assets (needs an authenticated `gh`). Warns
  loud if a future update adds FairPlay encryption.
- `README.md` — full rationale + VM install steps + fallback options.

## Update workflow

1. Update Azure VPN Client from the Mac App Store on the host.
2. `./package-azure-vpn.sh` (optionally pass an output dir, or `--release` to
   publish a versioned GitHub release).
3. Copy the fresh `.dmg` into the VM, drag to `/Applications`,
   `xattr -dr com.apple.quarantine "/Applications/Azure VPN Client.app"`, launch,
   approve the VPN extension in System Settings.

## The one risk to watch

If a future update enforces strict App Store **receipt validation** at launch,
the copied bundle quits (exit 173) and bounces to the App Store. It currently
doesn't. Fallback then: configure the Azure point-to-site VPN natively via
**IKEv2** (System Settings → VPN) or **OpenVPN** (OpenVPN Connect + downloaded
profile). That fallback only fails if the gateway is locked to Microsoft Entra
(Azure AD) auth, which requires the Azure VPN Client specifically.

## Gotchas

- Unpack the zip with `ditto -x -k`, **not** `unzip` — `unzip` mangles the
  framework symlinks inside the bundle.
- `hdiutil create` prints a benign `Authentication error` for the root-owned
  bundle; the DMG is still created correctly (script ignores it).
