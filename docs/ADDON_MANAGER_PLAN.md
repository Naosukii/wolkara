# WoW Forever add-on manager: implementation plan

Status: proposal only; researched 2026-10-12. No add-on implementation or device
installation is part of this planning change.

## Intended result

Wolkara offers a native **Add-ons** screen for the selected WoW installation.
Users can discover a small curated catalog, install an author's compatible
release, import a ZIP from Files, update or pin installed packages, disable a
package, remove it, and restore its previous version. Game updates preserve these
packages and their settings.

Start with Forever Beta (`wow_classic_beta`). Build the storage and provider
interfaces around an explicit installation/product target so other editions can
be added later without sharing their add-on folders accidentally.

Recommended defaults: user chooses every installation; check for updates when
opening Add-ons; apply updates explicitly during the beta. Add-on server outages
do not block an otherwise valid game launch. A mutation already committing must
finish or recover before Play becomes available.

## Findings that determine the design

1. Forever support exists, but release selection matters. RestedXP's current
   [TOC](https://raw.githubusercontent.com/RestedXP/RXPGuides/main/RXPGuides.toc)
   includes interface `16001` and Forever-specific content references. Its
   [release notes](https://github.com/RestedXP/RXPGuides/releases) contain ongoing
   Forever fixes. A development-branch TOC is evidence to investigate the
   packaged release, not proof that every release asset supports Forever.
2. [Bagnon](https://www.curseforge.com/wow/addons/bagnon) lists a Forever release.
   Its [TOC](https://raw.githubusercontent.com/Jaliborc/Bagnon/master/Bagnon.toc)
   requires BagBrother, and its
   [packaging configuration](https://raw.githubusercontent.com/Jaliborc/Bagnon/master/.upconfig)
   names multiple modules. Installing one repository folder is insufficient.
3. GitHub public release assets can be queried without authentication. Asset
   metadata can include a digest; use it when present. Select ready-to-install
   assets rather than assuming a source-code archive is a distributable package.
   [GitHub release-assets API](https://docs.github.com/en/rest/releases/assets).
4. Direct CurseForge integration needs an approved developer API key. Author
   consent is part of the approval process. Its API exposes distribution
   availability, file metadata, dependencies and a download-URL endpoint. Use
   those supported interfaces; do not scrape download pages or construct CDN
   URLs from file IDs. [API access](https://support.curseforge.com/support/solutions/articles/9000208346-about-the-curseforge-api-and-how-to-apply-for-a-key),
   [API reference](https://docs.curseforge.com/rest-api/).
5. Wolkara already preserves `WTF` and `Interface` during game updates.
   [Updater.m](../launcher/WoW/Updater.m) locks
   `<game-root-parent>/.tolkara-updates/update.lock`, refreshes user folders in its
   staged installation, then swaps the whole game root. Add-on mutations must
   share this exact lock and re-resolve the active installation after acquiring
   it. A separate add-on-only lock would allow lost updates.

## First catalog

These are candidates with publisher evidence of Forever support, not a claim
that they have been tested inside Wolkara. Admit a specific downloadable package
only after checking its actual contents and dependencies.

| Add-on | Purpose | Publisher evidence | Initial position |
| --- | --- | --- | --- |
| [Bagnon](https://www.curseforge.com/wow/addons/bagnon) | Bags and inventory | Forever file listing; TOC includes `16001` | First package/dependency validation case |
| [RestedXP Guides](https://github.com/RestedXP/RXPGuides) | Leveling guides | Forever TOC entries and release fixes | First GitHub provider case |
| [Leatrix Plus](https://www.curseforge.com/wow/addons/leatrix-plus) | Optional quality-of-life features | Dedicated Forever release | Initial curated catalog |
| [Leatrix Maps](https://www.curseforge.com/wow/addons/leatrix-maps) | Map improvements | Dedicated Forever release | Initial curated catalog |
| [TomTom](https://www.curseforge.com/wow/addons/tomtom) | Waypoints and navigation | Forever release listing | Initial curated catalog |
| [Dialogue UI](https://www.curseforge.com/wow/addons/dialogueui) | Readable quest dialogue | Forever release listing | Initial curated catalog |

Recommend by relevant features, maintained Forever packages, dependency clarity,
and observed iPad usability. Show provider download counts only with their source
and scope: total project downloads across editions do not measure Forever use.
Keep catalog ordering editorial until comparable Forever-specific usage data
exists. Add further projects after checking their own publisher releases.

RestedXP's public repository currently carries
[CC BY-NC-SA 4.0](https://raw.githubusercontent.com/RestedXP/RXPGuides/main/LICENSE).
Fetch the author's public package directly and retain its notices. Paid guide
purchases, account access and activation remain with RestedXP. Existing user guide
files must survive updates, including files that are absent from the public ZIP.
Only catalog metadata and synthetic fixtures belong in this repository; actual
add-on packages stay in ignored local output or on the user's device.

## User flow

Add a visible **Add-ons** entry on the WoW home screen. It opens a native list
with **Recommended** and **Installed** sections, local name/category search, an
**Import ZIP** action, and an update check.

Each row shows purpose, author/source, installed or available version, Forever
support status, and its appropriate action. Details show release notes, required
dependencies, package size, source link and the compatibility evidence. Normal
actions are Install, Update, Pin, Disable, Remove and Restore previous version.

Use explicit states: Not installed, Downloading, Checking package, Installing,
Installed, Update available, Disabled in Wolkara, Unverified for this beta,
Incompatible, and Import required. Distinguish "publisher supports Forever" from
"tested on this iPad". Installed files do not prove that the user enabled the
add-on in WoW's own character-specific AddOns menu.

Allow catalog browsing before installing the game; require a valid selected game
installation before changing its files. Keep mutation controls unavailable while
the game updates, startup is preparing, or `sessionUsed` is true. Follow the
existing requirement to reopen Wolkara after a guest session before managing
files. A successful installation applies on the next normal game launch.

Disabling in Wolkara moves the package out of the game's scan directory for all
characters. The manager does not rewrite character-specific game enable settings
or enable gameplay features on the user's behalf. Provide a recovery action to
disable all managed packages while retaining settings and unmanaged add-ons.

## Download providers

### GitHub

- Accept a canonical public repository or release URL. Resolve owner/repository
  and immutable release/asset IDs through the official API.
- Enumerate releases and select a compatible packaged asset. Do not use
  `releases/latest` as the complete selection algorithm: a relevant beta may be
  a prerelease or use a different asset from the stable release.
- Store source-specific asset rules in the curated catalog. Ambiguous packages
  need an explicit file choice; missing packaged releases fall back to ZIP import.
- Cache metadata with ETags and honor rate limits. Public access is sufficient
  for v1; authenticated private repositories are outside initial scope.

### CurseForge

- Resolve known catalog project IDs and pasted CurseForge project links through
  supported metadata endpoints. Determine the Forever version type from provider
  metadata; do not hard-code an unverified numeric flavor ID.
- Filter files by Forever, selected release channel and published availability,
  then resolve required dependencies and the supported download URL. Never select
  a project's global main file merely because it is newest.
- Enable direct downloads only with approved API access and permitted
  distribution. Treat explicit denial as unavailable; follow documented provider
  behavior for nullable fields rather than assuming consent.
- For the existing self-built app, accept the builder's approved API credential
  through local configuration/import and keep it in the device Keychain. Never
  commit it or share a project secret in a distributable app binary. Confirm that
  credential use matches the approved API access model before enabling it.
- Without access, keep the curated entry useful with **Open source page** and
  **Import ZIP**. The user downloads the author's Forever package in the browser,
  then imports it through Files. This is a manual fallback, not one-click support.
- A hosted credential broker would be a separate later deployment decision;
  v1 does not require a backend or new Wolkara account.

### Imported ZIPs

Use `UIDocumentPickerViewController`, copy the selected archive into private
staging, and run the same validation and installation pipeline. Imports receive
local ownership records, but automatic update matching requires an unambiguous
publisher/project identity. Unmatched imports remain manually managed.

## Compatibility and package selection

Represent the target as installation identity, product ID, game build/version,
edition folder, expected interface version when known, and game locale.

For the researched Forever 1.60.1 line, publisher TOCs provide evidence for
interface `16001`. Keep that mapping versioned and tied to the game version;
unknown future beta versions must become unverified until checked. The shared
`_classic_beta_` folder name alone is not a compatibility signal.

Apply two checks: provider/author flavor metadata and the selected package's
relevant TOCs, including interface lists and flavor-specific TOCs. An interface
match establishes declared compatibility, not successful gameplay. Keep exact
asset IDs and the tested game build in any device verification record.

Prefer the newest compatible stable package. Offer an explicitly labeled beta
package when that is the author's available Forever build; alpha is an advanced
opt-in. Pinning holds an immutable installed asset. Never silently switch to a
Retail or Classic-only file, edit a TOC to force compatibility, or alter the
game's out-of-date-add-on setting.

Parse required and optional dependencies separately. Resolve required projects
through curated/provider identities and install the full dependency set as one
transaction. Missing mappings, cycles and folder conflicts need a clear error;
optional integrations do not become mandatory downloads. Handle a package that
ships several folders as one owned package, including Bagnon's modules.

Use the selected game locale, including `deDE`, for checks and testing. Preserve
publisher translations as shipped. Label missing/unknown German support honestly;
the manager does not translate guide content or rewrite add-on Lua.

## Storage and installation transaction

Resolve the target using the registered library installation and the product
mapping in [Manifest.m](../launcher/WoW/Manifest.m). The normal Forever location is
`Documents/World of Warcraft/_classic_beta_/Interface/AddOns`; imported game roots
must work through the same resolver.

Keep a versioned `.wolkara-addons.json` inside `AddOns`, recording package identity,
source, release/file/asset ID, selected channel, compatibility evidence, owned
folders, file hashes, installation generation, pinned state and disabled state.
It travels with `Interface` through game updates and swaps atomically with the
add-on files. Namespace caches, disabled payloads, previous package versions and
recovery journals by installation/product under
`Library/Application Support/Wolkara/AddOns/`.

Installation/update sequence:

1. Resolve an immutable package/dependency plan and download to private disk
   staging. Use a dedicated add-on HTTP client; retain the existing Blizzard
   client's restricted host/redirect behavior. Cache reusable verified archives.
2. Verify provider checksums when supplied and compute a local SHA-256 inventory.
   A locally computed checksum alone is not publisher authentication. Permit only
   bounded HTTPS redirects to provider download hosts, never forward an API key
   to a download host, and omit credentials/signed URL queries from logs.
3. Inspect every ZIP entry before extraction. Proposed v1 ceilings are 128 MiB
   compressed, 512 MiB expanded, 64 MiB per file and 20,000 entries, enforced
   against actual bytes as well as declared sizes. Validate these limits against
   the initial real packages during the first implementation milestone.
4. Reject traversal, absolute/drive paths, symlinks, special files, encrypted or
   unsupported ZIPs, duplicate normalized paths, case/Unicode collisions, and
   native executables/installers. Accept valid add-on folders with appropriate
   TOCs; normalize an unambiguous archive wrapper without changing package files.
   Keep all writes confined to staging and the resolved add-on directory.
5. Acquire the game's existing update lock, re-resolve the active root, recover
   any interrupted operation, and recheck session state, compatibility and local
   changes. Clone/copy the active `AddOns` tree into a same-volume candidate and
   apply the complete planned change there. Preserve unmanaged folders,
   untracked custom files and existing guide content. Conflicting user edits need
   a backup/choice rather than silent replacement. Check space for the candidate,
   downloads and retained previous version.
6. Write the candidate ownership manifest, persist a recovery journal, then
   activate candidate files and manifest with one directory swap, or a rename on
   first install. Record durable commit completion before pruning staging.
   Recovery inspects generation/manifests and completes or rolls back an
   interrupted commit before any new mutation or launch.

Use a maintained ZIP library instead of implementing a new ZIP parser.
[ZIPFoundation](https://github.com/weichsel/ZIPFoundation) is the proposed choice:
it supports iOS, entry-wise extraction and cancellation, and has an MIT license.
Pin a reviewed release and expose a small Objective-C-compatible Swift wrapper.
Wolkara still owns path validation, resource limits and confined writes. The
first milestone must prove integration with both app targets and standalone tests.

Removal affects recorded managed files only. Retain modified/untracked content
or ask for an explicit backup-and-remove choice. Preserve `WTF`, SavedVariables,
game configuration, CASC data and original executables. Keep one prior verified
package version for rollback; restoring it must not revert unrelated add-ons or
the game build. Disabled payloads stay outside `Interface/AddOns` and retain user
additions when re-enabled.

## Proposed code boundaries

| Area | Responsibility |
| --- | --- |
| `launcher/WoW/AddOns/Catalog.*` and bundled JSON | Curated identities, categories, source rules and evidence |
| `Models.*` / `Compatibility.*` / `TOC.*` | Target, release plan, dependency graph, TOC metadata and support status |
| `Providers/GitHub.*`, `Providers/CurseForge.*`, `HTTPClient.*` | Provider metadata, credentials, compatible asset selection and transfers |
| `PackageArchive.swift` | Bounded ZIP inspection/extraction through the pinned dependency |
| `Store.*` / `Installer.*` | Ownership, staging, shared lock, activation, recovery, disable/remove/rollback |
| `AddOnsViewController.*` | Catalog, installed list, import and explicit user actions |
| Existing WoW controller/updater integration | Selected installation, operation serialization, Play/session guards and preservation |

Keep the native controller thin. Validate catalog entries against a schema.
Separate source release identifiers from display versions, since publisher version
strings need not follow semantic-version ordering.

## Implementation milestones and completion criteria

1. **Prove package sources and target identity.** Inspect actual ready-to-install
   RestedXP and Bagnon Forever archives outside git; record asset/file IDs, layout,
   effective TOCs, dependencies and hashes. Establish whether approved CurseForge
   access is available. Prove the ZIP dependency builds in both targets. Complete
   when correct packages can be selected without executing a game or add-on.
2. **Build the local package engine.** Implement ZIP import, compatibility checks,
   ownership, shared locking, atomic installation, recovery and previous-version
   restore using synthetic fixtures. Complete when cancellation/failure never
   leaves a mixed active package or changes protected game/user files.
3. **Add source adapters.** Implement GitHub and CurseForge providers with injected
   transports, caching and dependency planning. GitHub live downloads require a
   verified packaged asset; CurseForge live downloads require approved access.
   Without it, clearly ship/import-test the manual fallback and keep direct
   CurseForge downloading marked pending.
4. **Add the native manager and curated catalog.** Integrate installation targeting,
   progress, errors, installed actions, pins and recovery controls. Make Bagnon
   and RestedXP the first package examples, then admit the other catalog candidates
   after package validation. Keep game launch independent of optional update checks.
5. **Validate on the connected iPad.** Update Wolkara in place, preserving its data.
   Manually verify appearance in WoW's AddOns menu, useful operation in Forever,
   German behavior, disable/restore and survival through a game update. Record
   exact game/add-on versions and observed results in `COMPATIBILITY.md`; publisher
   declarations alone never earn an iPad-tested label.

## Required verification

- Provider fixtures: wrong flavor, multiple assets, prerelease-only compatibility,
  unpublished/unavailable files, absent API access, distribution denial, missing
  checksums, corrupted downloads, redirects, rate limits and expired download URLs.
- Package fixtures: complete multi-folder packages, missing BagBrother-like
  dependencies, dependency cycles, source wrappers, malformed TOCs, wrong interface,
  traversals, symlinks, Unicode/case collisions, archive bombs and truncated ZIPs.
- Storage fixtures: manual add-ons, modified managed files, untracked paid/custom
  guide files, required shared modules, insufficient disk, lock contention and
  interruption at each commit boundary. Verify that WTF/SavedVariables and
  original executable hashes stay unchanged.
- Integration fixtures: installing/updating add-ons followed by a game update,
  game update followed by add-on recovery, background cancellation, target-edition
  isolation, and session/startup guards. Reuse the existing synthetic WoW updater
  tests rather than downloading a game in automated tests.
- UI fixtures: source availability, import flow, dependency explanation, progress,
  conflict resolution, missing game, beta labels, German metadata, large text and
  iPad popovers. Runtime tests currently need an installed iOS Simulator runtime;
  the previous work found none on this Mac.

The deliverable is complete when at least one verified GitHub package installs
directly, the Bagnon package installs with its required modules through an
available supported source or explicit ZIP import, recovery/preservation tests
pass, and device observations distinguish installation success from gameplay
compatibility. One-click CurseForge downloading remains a separate acceptance
item until approved API access and live source behavior are verified.
