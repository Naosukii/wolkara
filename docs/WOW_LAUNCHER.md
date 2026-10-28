# Wolkara launcher

Current branch: `main`, based on the touch-controller implementation
at `b55084a` (2026-10-06). The name, original W/portal icon and home heading are
now Wolkara. The engine, Xcode targets and bundle IDs retain their existing names
to preserve signing configuration and installed data. The development history
and validation below distinguish tested results from pending device checks.

Branch: `feature/wow-launcher`, based on `feature/iphone-support` at
`05035ccbbf33565ab36abdb1d5e43a6b53cc816b`. This is an early, working prototype,
not a complete replacement for Battle.net. The existing runtime and execution
modes are unchanged. No game files, signing identities or accounts are bundled.

## Available now

The app opens directly into a native WoW home screen with edition selection,
automatic updates and one primary action. `feature/wow-home` continues from
`feature/keyboard-dictation` at `e5ecdb6` and makes this the only normal launcher:
all interface copy is English, with one game heading and no adventure slogans.
Download language remains independently selectable. Startup preparation, elapsed
time, failure and session end stay in the same home card; no separate loading
screen or general application library is exposed. Settings retains diagnostics;
there is no startup-mode picker. About includes the bundled MIT copyright/license and
third-party notices, plus an independent-project attribution.

Development launches with explicit arguments retain their diagnostic screen.
The runtime, authorization and per-process preparation requirements are unchanged.
The keyboard fix remains inherited; native mouse work remains on its own branch.
Ordinary icon launches select Developer service in the integrated target and
External JIT in the diagnostics/sideload target, before memory reservation.
An old saved Local signing selection cannot accidentally block an ordinary
launch. Explicit development arguments retain the previous resolver and can
still select another mode. Hiding the selector does not remove enrolment, JIT
or memory requirements; see [the distribution plan](WOLKARA_DISTRIBUTION.md).

- Remembers Forever Beta, Classic Era, Classic, Retail or Retail Beta, region
  and language. Forever currently maps to `wow_classic_beta`; a listed edition
  is not a claim of runtime compatibility.
- Checks at opening, foregrounding and before Play. An outdated installed copy
  **starts updating automatically**. A missing edition offers Install; an
  unverifiable installation offers Repair. Interrupted explicit installations
  are remembered and resumed, including after reopening the process.
- Shows preparation, existing-data verification, downloading, file installation
  and activation progress. Play stays disabled until the current published build
  and its original executable pass verification. A failed check never counts as
  up to date. No game starts automatically unless the user requested Play.
- Keeps settings and addons. The updater writes into a private APFS clone and
  switches the whole installation in one filesystem operation only after all
  required content is present and verified. An interrupted update leaves the
  active installation in place.
- Downloads while the app is open. Backgrounding cancels the current transfer;
  verified objects are checkpointed and reused next time. The same applies to
  returning after a network failure. This is not an iOS background-download
  service. Keep the app open while updating.
- Developer service still prepares executable memory at each launch. Updating
  files does not remove or cache that separate runtime operation.

Play checks `.build.info` and the selected executable on ordinary launches.
Updates compare required objects against a persistent verification inventory;
unchanged verified CASC payload is not reread. Installing this launcher revision
does not create that inventory retroactively: the first update of an imported
copy still scans its required content. Settings → **Verify and repair game files**
forces a complete check, including when the installed build is current. Repair
requests survive interruption and never silently resume as a cached update.
The general library is no longer reachable from the user interface, so it no
longer provides a manual launch path around the home screen's update check.
The internal library model still resolves installations and profiles.

## Update implementation

`Manifest.m` reads text metadata, BLTE, install and encoding manifests with
bounds, decompression limits and content checksums. `CASC.m` adds download
manifests, CDN archive indexes and local v7 CASC index/container storage. It
selects standard macOS ARM64 content for the region/language, excluding optional
HighRes/Alternate/feature packs. Encrypted assets are retained as opaque original
bytes; encrypted loose-file extraction is rejected. No content keys, login
credentials or game code are supplied by Tolkara.

`Client.m` uses Blizzard's public HTTPS services, bounded responses and verified
Range requests. It reuses a connection pool and groups adjacent archive objects
into requests of up to 16 MiB (larger individual objects remain bounded at
256 MiB). Every selected object is checked before being passed to storage.
Metadata caches are content-addressed and reverified. Protocol sources and
licences from TACTSharp, CascLib and lookup3 are recorded in `NOTICE.md`;
no .NET runtime is embedded.

`Updater.m`:

1. Locks the updater and records a snapshot keyed by product, build and locale
   under `.tolkara-updates` beside `World of Warcraft`. APFS clones share old
   blocks without permitting writes to alter the old installation. Symlinks
   outside the installation and unsupported files fail the update.
2. Reuses receipts for unchanged content and verifies objects without a valid
   receipt, then computes missing objects. It checks space for
   missing objects, loose files and a 1 GiB margin; filesystem write errors also
   stop activation. Bootstrap manifests and the root manifest are included.
3. Appends new encoded objects to new CASC segments and checkpoints local indexes
   every 64 MiB and on a handled interruption. The latest two index generations
   are retained. A forced process kill may lose the current uncheckpointed batch;
   it cannot activate a partial installation. Resume reuses valid receipts and
   checks objects whose receipt is absent or invalid.
4. Installs original loose files with exact size/content hashes. It never
   patches or re-signs the game's executable. Existing WTF and Interface folders
   are refreshed from the old root immediately before activation, preserving
   edits made while paused. Only when Config.wtf is absent, initial portal and
   locale settings are created to avoid the unsupported region picker.
5. Rechecks the published version and unchanged source metadata, then uses an
   atomic directory swap to activate metadata, executable and data together.
   Its own replaced snapshot is removed after success. Other editions and
   existing unreferenced data are retained; data compaction is not implemented.

### Persistent verification (2026-10-07)

`Data/data/.wolkara-verified` is a local, versioned, checksummed inventory with
compact 25-byte records: the full encoded key, indexed location and encoded
size. A record is reusable only if its current local index entry still matches
and its segment's filesystem identity, size, nanosecond mtime and nanosecond
ctime match. Same-size writes with restored mtime, replacement files, deletion,
truncation and symlinks do not authorize cached reuse. The cache reader bounds
its file size and record count and rejects malformed/checksum-invalid records;
a missing or rejected cache falls back to normal payload verification.

Cloning changes inode identity. Before cloning, the updater captures validated
receipts; after its APFS clone it rebinds only segments whose source stayed
unchanged and whose clone has the same content size/mtime. It saves receipts
after planning, before activation and on handled interruptions, only for durable
indexed content. New downloads still pass their original encoded checksums.
Reading bytes for loose-file extraction still verifies them, and the original
executable is still checked against the current manifest. If a segment's
metadata changes during the transaction, the updater rechecks every previously
trusted extent in that segment against its full encoded key and chunk checksums.
Only a successful check with stable metadata can refresh its receipts; missing,
unstable or checksum-invalid data still prevents activation. Other segments keep
their receipts. WTF and Interface preservation is unchanged.

The inventory is a performance cache, not protection against deliberate local
cache forgery or storage corruption that leaves all filesystem metadata intact.
Use **Verify and repair game files** to force payload checks. Normal updates
still read manifests, indexes and the small inventory and visit required keys;
they do not promise constant-time planning or eliminate startup memory preparation.

Validation uses our own synthetic fixtures: cold adoption, warm reuse, a new
patch, cancellation/resume, clone/swap, changed segments, corrupt/missing
receipts, malformed metadata, full repair and interrupted repair. A 16 MiB
fixture reads 16,781,056 payload/envelope bytes cold and **zero** on the warm
planning pass (metadata reads are excluded). ASan/UBSan checks, the simulator
home/repair flow and a signed arm64 device build pass. This optimization has
not yet been measured against the full game installation on the physical iPhone.

The first device trial reported repeated **CASC data changed during the update**
while resuming the 70235 → 70245 patch. The original guard aborted on any metadata
difference, including in its own append segment, without checking whether the
stored content was still valid. Metadata-only recovery now avoids that false
positive without discarding staging or disabling checksum validation. Synthetic
tests reproduce the old failure and cover recovery during resume/activation,
appending across a 64 MiB checkpoint, retained warm receipts after reopening,
and refusal of actual corruption. Xcode now logs update phase transitions,
errors and verification byte counters; segment rechecks log the segment number.
A subsequent Xcode console observation confirmed `data.075` was rechecked and
the physical update reached `activate` then `complete` (67,488,524,145 bytes
read, 44,033,527 reused). The exact source of the metadata change remains
unidentified; a later warm patch and post-update gameplay need separate tests.

`Installation.m` checks the installed product and original executable.
`WoWViewController.m` serializes update jobs, discards stale UI/launch callbacks
when the screen or edition changes, and registers newly installed executables
with the existing library. Its normal flow needs no running Battle.net on a Mac
for downloading patches. It does not automate login or gameplay.

### Settings and add-ons backup and restore (2026-10-18)

`BackupManager.m` adds ZIP export and restore for `WTF/` (settings, macros, keybindings,
SavedVariables) and `Interface/AddOns/`:
- **Export**: Generates standard ZIP archives via `NSFileCoordinator` and APFS staging,
  presented through `UIActivityViewController` for saving to iCloud Drive, Files, or AirDrop.
- **Restore**: Discovers `WTF` and `Interface` folders within chosen backup archives,
  preserves existing settings in `.backup_pre_restore` before overwriting, and validates
  ZIP entries against path traversal attacks and disallowed binary executables.
- **Accessibility**: Available in both the main **Settings** sheet and the **Add-on Manager** toolbar.

## Remaining validation and limits

- Cellular-only startup failed on the user's first outdoor test (2026-10-04)
  before executable-memory preparation. This branch adds a bounded pre-auth TCP
  retry while preserving the route, so a temporary Mobile Data off/on sequence
  can be tested. It has **not yet been confirmed on the physical iPhone**. See
  [mobile-data recovery](IPHONE.md#starting-with-mobile-data-experimental-recovery).
  Playing anywhere remains an unmet requirement until cold startup and returning
  to mobile data both pass; testing without a Mac was not sufficient evidence.
- The user completed the pending patch on the physical iPhone. Readback verified
  the 1.60.1.70205 original executable against the Mac copy. Startup then stopped
  at a loader compatibility issue described below. Startup/gameplay after that
  fix and interruption/resumption on the device still need manual validation;
  matching files alone do not prove WoW accepts the updated CASC store on iOS.
- Fresh installation is implemented and tested with synthetic data, but a full
  fresh real-game download has not been validated. Other listed editions have
  metadata checks, not complete update/runtime coverage.
- Existing game language preferences are preserved; changing the download
  language is not a WoW settings editor. Download only a language matching the
  installation until switching languages is tested. Optional packs are not
  part of this standard-content updater.
- Transfers stop on protocol/storage errors and offer Retry. Oversized objects,
  unsupported local-index layouts and encrypted loose files fail explicitly.
  New upstream formats may require code changes. Obsolete data/abandoned build
  snapshots are not globally compacted automatically.
- Preparation time is unchanged. Local signing and the required final-page
  capture/signing workflow remain a separate investigation. A container for an
  old executable must never be reused for an updated one.

## AltStore PAL feasibility

The intended public distribution channel is **AltStore PAL**, not Classic.
There is currently **no demonstrated PAL-compatible native execution path** for
this launcher. The home screen and downloader do not solve that.

An [AltStore source](https://faq.altstore.io/developers/make-a-source) is a feasible
way to list and update this launcher: host its source JSON, artwork and release
packages, then users add the URL in [PAL's Sources tab](https://faq.altstore.io/altstore-pal/sources).
PAL still requires an Apple-notarized app/Alternative Distribution Package and
marketplace registration; a source is not an exemption. Classic sources instead
serve IPAs signed through the user's sideloading setup. Updating the launcher via
a source is distinct from the launcher's own WoW CDN updates. No source was
published and no notarization or distribution submission was performed here.

[AltStore's PAL distribution documentation](https://faq.altstore.io/developers/distribute-with-altstore-pal)
requires Apple notarization. [Apple's code-signing documentation](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web)
explains mandatory executable-code validation. Our engineering conclusion is
that installing the wrapper through PAL alone cannot be treated as permission
to execute a separately downloaded Mac client. No notarized build was submitted
or tested, and no PAL distribution or execution entitlement is claimed.

[AltStore's JIT guide](https://faq.altstore.io/altstore-classic/enabling-jit)
does describe a helper, StikDebug, distributed through PAL. Its documented target
apps are sideloaded through **AltStore Classic**, with a pairing setup involving
a Mac or PC. The helper's availability on PAL does not establish that this
wrapper installed through PAL can execute WoW.

Local signing remains a development experiment involving the user's own signed
page container, not a proven solution for marketplace distribution. Its keys or
third-party code must not be bundled into a public app. Replacing native execution
with interpretation would be a different engineering project with unproven WoW
compatibility and performance. “Install from PAL, choose an edition and play,
without setup or preparation” therefore remains an unresolved feasibility goal,
not a deliverable promised by this branch.

## Validation — 2026-10-03

The initial CDN transactions below were run on the Mac using the **same native
client/updater code** compiled into the iOS app. They do not establish gameplay
with the downloaded copy.

The user subsequently downloaded the pending patch inside Tolkara on the iPhone
16 Pro Max. Readback confirmed version 1.60.1.70205 and an executable whose SHA-256
exactly matches the original on the Mac. The startup log confirms successful
112,427,008-byte executable-memory preparation, followed by fixup stream rejection
before any guest entry. The rebase table ends at byte 136,456 immediately after a
complete opcode, without DONE; the loader was incorrectly treating that as
truncation. `GuestFixups.c` now accepts this valid end condition while retaining
all operand, target and work-budget checks. Synthetic tests cover valid final
opcodes, truncated operands, out-of-bounds targets and invalid opcodes under
ASan/UBSan. The unchanged readback executable now passes the loader-only probe:
241,069 rebases and 3,549 binds. This probe never executes game code. A new manual
device startup and gameplay test is still needed; the earlier two-hour gameplay
report was for the previous client.

Two isolated Forever 1.60.1.70205 transactions completed. Both verified
1,215,567 selected objects (67,079,188,425 encoded bytes), reused existing valid
content, downloaded 248,252,461 missing asset bytes and verified all 143 loose
files after activation. A deliberately absent Info.plist in each **test clone**
was restored through a verified archive range. The original Mac installation's
metadata and executable remained unchanged. No game was run. The second
transaction exercised batched range downloads and connection reuse. A final
transaction also verified the required root manifest and reused every selected
asset (zero missing asset bytes downloaded).

| Product | Published version observed | Result |
| --- | --- | --- |
| `wow_classic_beta` | 1.60.1.70205 | Verified config, install and encoding manifests; 143 selected install files; downloaded the 149,167,072-byte original executable. Its SHA-256 exactly matched the existing Mac original. Neither was executed or modified. |
| `wow` | 12.1.0.69933 | Verified config and install manifest; 142 selected install files. Runtime not tested. |
| `wow_classic` | 5.5.4.70032 | Verified config and install manifest; 141 selected install files. Runtime not tested. |
| `wow_classic_era` | 1.15.9.70003 | Verified config and install manifest; 141 selected install files. No new runtime test. |
| `wow_beta` | 12.0.1.66220 | Verified config and install manifest; 141 selected install files. Runtime not tested. |

The initial large-file decoder caused excessive temporary allocations. After
changing to one preallocated output buffer and non-copying chunk views, the
cached-encoding executable extraction used **464,437,248 bytes maximum RSS**
on the Mac (about 443 MiB), versus about 27 GB before. This is a Mac process
measurement, not an iPhone memory budget or a guarantee for larger builds.

- Focused manifest, client, installation and updater tests: **PASS**,
  `-Wall -Wextra -Werror`, ASan and UBSan. Synthetic fixtures cover truncation, bounds, decompression limits,
  checksums, unsafe paths, multi-chunk decoding, tag filtering, cache corruption,
  missing/changed/ambiguous build metadata, read-only inspection, changed original
  bytes, protocol failures and HTTPS-only selection. No third-party application
  data is in the tests. Updater fixtures also cover grouped archive downloads,
  corrupt ranges, pause/resume, source preservation, late upstream build changes,
  external symlinks, protected user paths, optional packs and fresh installs.
- UIKit fixture: **PASS** on iPhone 17 Pro / iOS 26.5 Simulator. Synthetic
  responses exercise automatic checks and installation of a detected patch
  without a Play tap, rapid edition changes, missing-install action, initial startup configuration, offline retry,
  pending launch cancellation in the background, verified launch callback and
  session-end blocking. No game code executes. The Spanish landscape layout was
  visually inspected using the fixture, with the Play button visible.
- Full integrated Tolkara build for generic iOS ARM64: **BUILD SUCCEEDED**.
  This was an unsigned compile check, with public system roots disabled for this
  test output. A separate private build with the existing development identity
  and `TOLKARA_SYSTEM_ROOTS=YES` also **BUILD SUCCEEDED**; its strict signature,
  unchanged keychain groups and 158 public root certificates were verified.
  The user installed the updater afterwards; see the physical patch report above.
- Full `tools/test_emulation.sh`: **FAIL**, at the previously documented
  `tests.test_sign_guest_local.AdhocTests.test_matches_codesign_byte_for_byte`
  comparison (`sgl-fixture.dylib` differs from `codesign -s -`). This same failure
  was already reproduced on the original base during the iPhone PR review.
  The launcher changes do not modify that signer. This failure remains unresolved.
  The startup-fix rerun reaches the same failure. Later suite steps do not run
  after it. Focused launcher and fixup tests pass independently.

## Reproduce

From the repository root (Xcode and XcodeGen required):

```sh
bash tools/test_wow_launcher.sh
bash tools/test_wow_launcher_ui.sh
bash tools/test_emulation.sh
# Focused fixup regression, also runnable after the unrelated signer failure:
xcrun clang -std=c11 -D_DARWIN_C_SOURCE -Wall -Wextra -Werror -O1 -g \
  -fsanitize=address,undefined -fno-omit-frame-pointer -Iruntime \
  runtime/GuestMemory.c runtime/GuestImage.c runtime/GuestFixups.c \
  tests/test_fixups.c -o build/emulation/test_fixups
build/emulation/test_fixups
# Loader-only validation of the user's unchanged original; no game execution:
tools/probe_guest.sh /path/to/original/executable --validate-fixups
tools/generate.sh
xcodebuild -project Tolkara.xcodeproj -scheme Tolkara -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/wow-launcher/DerivedData-iOS \
  CODE_SIGNING_ALLOWED=NO TOLKARA_SYSTEM_ROOTS=NO build

# Public metadata only; does not install anything.
build/wow-launcher/wow_cdn wow_classic_beta eu build/wow-launcher/forever

# Downloads encoding metadata and an original file into ignored build output.
build/wow-launcher/wow_cdn wow_classic_beta eu build/wow-launcher/forever \
  --stage 'World of Warcraft Beta.app/Contents/MacOS/World of Warcraft'

# Compile probe only: does not sign or execute a container on a device.
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -fobjc-arc \
  -Wall -Wextra -Werror -c tools/sign_guest_local.m \
  -o build/wow-launcher/sign_guest_local-ios.o
```

Generated plans, metadata and original files must stay in ignored `build/`,
or the app's private cache on a device. Never commit or distribute them.


## Unified home validation (2026-10-06)

The isolated UIKit fixture uses synthetic game metadata and never runs a game
or contacts Blizzard. It verifies English copy on a Spanish device, automatic
check/update, edition races, offline retry, background cancellation, startup
configuration, the verified Play gate and one-session restriction. Added cases
keep preparation and failure in the same navigation root, block repeat launch
and refresh during startup, preserve recoverable preflight retries, and check
that About contains the bundled upstream and dependency license notices.

The fixture now uses UIWindowScene for Xcode 27 / iOS 27 and requires its PASS
marker: simctl may return zero after the app crashes. Home, preparation and
failure layouts were rendered in an iPhone 16 Pro Max simulator. Physical
startup after this UI integration still requires a manual test. The new branch
is not installed while the user tests the separate keyboard correction.

Results with Xcode 27.0:
- `tools/test_wow_launcher_ui.sh`: PASS on iOS 27.0 Simulator.
- `tools/test_emulation.sh`: PASS in full. The older signing-test failure
  recorded above no longer reproduces with this toolchain; no signer changes
  were needed for this UI work.
- `tools/generate.sh`: PASS; both `LICENSE` and `NOTICE.md` are app resources.
- `xcodebuild -project Tolkara.xcodeproj -scheme Tolkara -configuration Debug
  -sdk iphoneos -destination generic/platform=iOS -derivedDataPath
  build/iphone-wow-home-signed ARCHS=arm64 TOLKARA_SYSTEM_ROOTS=YES build`:
  BUILD SUCCEEDED. Strict signature verification passed, and both license
  resources match the checked-in originals byte for byte.

The follow-up on `feature/touch-controller` adds an automatic virtual gamepad;
see [its layout, implementation and validation](TOUCH_CONTROLLER_PROPOSAL.md).


## Status text correction (2026-10-06)

The status row previously stretched the title against a 20-point spinner,
compressing a roughly 27.5-point line and clipping descenders in “Ready to play”.
The row now centers its arranged views and labels resist vertical compression.
The UIKit fixture checks text bounds at default and maximum accessibility sizes;
large content remains scrollable. This changes neither update nor launch logic.
