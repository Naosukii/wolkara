# Build and run Wolkara

This guide is for the Wolkara fork and its integrated Developer service build.
It builds our generic runtime, then downloads the selected WoW client directly
on the iPhone/iPad. WoW and Battle.net do not need to be installed on your Mac.

## Requirements

- An Apple silicon Mac, Xcode with support for your device's iOS version,
  XcodeGen and Python 3. Install Xcode's requested platform components first.
- Your own Apple developer signing. The integrated app and its tunnel need
  Network Extension, increased-memory-limit and extended-address-space
  capabilities. Use a paid developer membership for this workflow; free
  Personal Team signing is not a validated alternative for this build.
- A connected, unlocked device with Developer Mode enabled and the Mac trusted.
  The recorded phone testing is on an iPhone 16 Pro Max running iOS 27.
- Enough free device storage for the edition and its updates. The tested
  Forever installation is roughly 70 GB; the required size changes by build.
- Your own game account and access to the selected edition/beta.

## 1. Clone and configure

```bash
git clone https://github.com/fJavierLasso/wolkara.git
cd wolkara
brew install xcodegen
cp local.env.example local.env
```

Edit the ignored `local.env` with your own values:

```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID
TOLKARA_BUNDLE_ID=local.wolkara.yourname
TOLKARA_KEYCHAIN_GROUP=local.wolkara.yourname.authorization
DEVICE=YOUR_DEVICE_UDID
TOLKARA_MODE=developer-service
NATIVE_GUEST_SHIMS=GENERIC
GUEST_EXE=
```

Find the team in Xcode → Settings → Accounts and the device identifier with
`xcrun devicectl list devices`. Keep those values local; do not commit them.
Use identifiers unique to your team. The extension's identifier is derived from
the app identifier automatically. Leave experimental adapters and captures unset.

## 2. Open Xcode and Run

```bash
tools/generate.sh
open Tolkara.xcodeproj
```

Select the **Tolkara** scheme and your physical iPhone/iPad destination, then
press **Run**. The app installed on the device is called **Wolkara**. Do not run
`LocalAuthorizationTunnel` or `StorageProbe` as the application.

Automatic signing must succeed for both `Tolkara` and `LocalAuthorizationTunnel`.
If Xcode needs account/capability setup, fix Signing & Capabilities for both
before retrying. Keep **Debug executable** and **Metal API Validation** off;
the generated shared scheme already does this. Store persistent personal
settings in `local.env`, because regeneration replaces manual project edits.

If the device requests developer trust, use Settings → General → VPN & Device
Management. Enable Developer Mode under Privacy & Security if needed.

## 3. Authorize this installation once

After the app is installed, keep the device unlocked and connected. From the
same checkout, run:

```bash
tools/enroll.sh
```

Approve the system pairing prompt on the device. The command must finish with
**Verified enrollment imported**. It stores this installation's authorization
in the device-only Keychain. Do not share pairing records or authorization files.
Changing the bundle ID or Keychain group requires enrolling again.

Reopen Wolkara normally afterwards. When first launching the game, allow its
local VPN-style tunnel if iOS asks. It is used to reach the device's developer
service for memory preparation, not to stream the game from the Mac.

## 4. Install an edition and play

Choose **Forever · Beta** for the edition with recorded gameplay, then your
region and download language (English, Spanish, or German) and **Install**.
Keep Wolkara in the foreground while downloading.
It checks for updates when opened and before launch, and installs required
updates before enabling Play. If interrupted, reopen and retry to resume.

After **Ready to play**, press **Play** and allow memory preparation to finish.
Log in manually using your eligible account. Touch controls appear without a
physical controller; the upper toolbar opens the keyboard, trackpad and settings.

The full first-download flow is still under physical-device validation. If it
fails, record Settings → Technical details; do not delete the app or its data as
an initial troubleshooting step. See [fresh-install testing](FRESH_INSTALL_TEST.md).

## Updating Wolkara itself

Close the game, pull the source changes, regenerate the project and Run again
with the same bundle ID, team and Keychain group. This replaces the app while
keeping its game data. Game updates happen inside Wolkara; source/app updates
still require rebuilding. Signing and authorization requirements remain separate.

When upgrading an earlier build after the Wolkara rename, keep your existing
bundle ID and Keychain group. Saved touch layouts and verified-download receipts
are read from their former storage keys and saved under the new names. The old
keys remain only as migration inputs; they are not used for new installations.

The existing setup has launched without the Mac and after reboot. Cellular-only
startup remains unresolved; see [the iPhone notes](IPHONE.md). Build success or
a simulator pass is not proof of game execution on another device/signing setup.
