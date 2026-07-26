# wPlayer Release and Signing Guide

This document covers AppGallery release identity, release signing and source-publication safety. General environment,
unsigned build and device-development instructions are in [BUILDING.md](BUILDING.md).

## Non-negotiable safety rules

- Never commit signing passwords, private keys, certificate stores, Profiles, certificate files or machine-specific
  signing paths.
- Never paste KeyStore or key passwords into chat, source files, shell history or logs.
- Enter both passwords locally through DevEco Studio.
- Preserve the exact encrypted password strings written by DevEco Studio; do not derive, decrypt or replace them.
- Keep release and debug identities separate.
- Do not copy release material to a repository, temporary artifact, agent memory or another machine without explicit
  authorization.

## Release material

On each authorized Windows development machine, the user places the dedicated release files outside the repository
under:

```text
C:\Users\<user>\.ohos\release
```

For the current release identity:

- `wplayer-release.p12`: private release KeyStore;
- `wplayer-release.cer`: AppGallery Connect release certificate issued from the CSR;
- `wplayer-releaseRelease.p7b`: release Profile for `com.wabebabo.wplayer`;
- `wplayer-release.csr`: retained certificate request, not a signing input after certificate issuance.

The current KeyStore alias is `wplayerRelease`; the signing algorithm is `SHA256withECDSA`.

Before publishing, verify that the `.cer`, `.p7b`, bundle name, KeyStore alias and `.p12` belong to the same release
identity.

## Local profile shape

DevEco Studio writes local signing objects directly into the tracked root `build-profile.json5`. A configured
development machine therefore keeps this file intentionally dirty.

Use separate local entries:

- product `default` selects signing configuration `default`;
- product `release` selects signing configuration `release`.

The portable committed file retains both product mappings but has exactly one empty `app.signingConfigs: []`.

## Release build

Before building:

1. Confirm product `release` selects the dedicated `release` signing entry.
2. Confirm that entry uses the dedicated AppGallery identity rather than a generated debug identity.
3. Stop the Hvigor daemon if signing or product selection has changed.
4. Build the release product in release mode:

   ```powershell
   devecocli build --product release --build-mode release
   ```

The custom `assembleReleaseSignedApp` Hvigor task may also be used from DevEco Studio after selecting product
`release` and Build Mode `release`. It verifies:

- the `release` product selects a local signing configuration named `release`;
- generated metadata reports release build mode;
- generated metadata reports `debug: false`.

Do not infer release readiness from an output filename alone.

## Release verification

Verify the generated release artifact and metadata, then test it on an authorized target:

```powershell
hdc list targets -v
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.wabebabo.wplayer
```

Inspect startup and playback logs. Verify the release scenarios selected from
[agents/TEST_MATRIX.md](agents/TEST_MATRIX.md).

Do not automatically uninstall an application after a signing mismatch. An uninstall deletes its local data and
requires user approval.

## Preparing a source commit

Follow the authoritative “提交前清理签名” procedure in [BUILDING.md](BUILDING.md). For a release-configured
machine, preserve both local debug and release entries in the external backup and confirm neither entry remains in
the staged portable representation.

Never stage the restored local version.

## Backup responsibility

The user is responsible for backing up:

- the release `.p12`;
- its alias;
- both passwords;
- the `.cer`;
- the `.p7b`.

Maintain at least two encrypted backups in separately controlled locations. Agents must not create, copy or move
these backups without explicit authorization.
