# Signing and installation without an owned Mac

## Android

Mobile checks and builds produces a development-signed ARM64 APK. This is a
test artifact, not a Play-ready release. New CI machines may use different debug
keys, so it may not update an existing installation. Export data first and keep
models/maps separately before any necessary reinstall.

For a permanent identity, keep one private keystore under the owner's control.
Create it locally with a trusted Java keytool if one does not already exist:

```sh
keytool -genkeypair -keystore amid-release.jks -alias amid -keyalg RSA -keysize 4096 -validity 10000
```

Enter passwords interactively. Back up the keystore/passwords securely. Do not
commit them or send them in chat. Configure repository Actions Secrets:

| Secret | Value |
| --- | --- |
| ANDROID_KEYSTORE_BASE64 | Base64 bytes of the existing permanent keystore |
| ANDROID_KEYSTORE_PASSWORD | Keystore password |
| ANDROID_KEY_ALIAS | Existing alias |
| ANDROID_KEY_PASSWORD | Alias password |

After reviewed code reaches main, manually run **Signed Android candidate**.
It validates the source, builds signed APK and AAB, verifies them and uploads an
artifact with release-manifest.json and SHA256SUMS.txt. Missing secrets fail the
job; distribution signing never falls back to a development key. The temporary
keystore is removed on exit. No upload to Google Play happens automatically.

For local distribution builds, copy key.properties.example to key.properties
with real local values and set AMID_SIGNING=distribution. Environment variables
take precedence. Coordinate the distribution key and Play App Signing if users
must update across APK and Play channels.

## iPhone personal installation through Windows

Run **Mobile checks and builds** manually on the desired source ref, with
build_ios enabled. It uses a GitHub macOS runner and Xcode/iOS SDK 26 or later.
Download AMID_Offgrid_iOS_unsigned.ipa and its manifest from that exact successful
run. This file must still be signed before it can be installed.

Use official Sideloadly on Windows with the owner's Apple Account, connect and
trust the iPhone, and follow its Developer Mode / developer trust instructions.
A free personal signature normally expires after seven days. Renew using the
same Apple Account and Bundle ID and verify that local data survives. Do not put
Apple passwords in GitHub Secrets or this repository.

https://sideloadly.io/faq.html

The new 0.3.0 IPA's installation and renewal on a physical iPhone are not verified
until a device report exists. A previous release or successful unsigned compile
does not close that requirement.

## App Store and TestFlight

An owned Mac is unnecessary; membership, a registered Bundle ID, valid signing
certificate/private key, matching provisioning and App Store Connect access are
still required. Use ios/ExportOptions.plist.example as a starting point only;
replace placeholders in a temporary file and validate the actual team's profile,
entitlements and certificate. Build/archive/export on macOS and inspect signing.
An App Store Connect API key authorizes allowed uploads; it does not sign code.

No Apple certificate or membership has been supplied or assumed. Store upload
automation remains gated on those credentials and a validated signed build.
Personal sideloading is not App Store distribution. The standard membership
fee and organization-only waiver rules are documented by Apple:

https://developer.apple.com/help/account/basics/about-your-developer-account/
https://developer.apple.com/programs/whats-included/
https://developer.apple.com/help/account/membership/fee-waivers/

## Cost controls

The repository is private. Check included Actions resources and spending limits
before macOS builds; macOS is manual to avoid running on every PR. Artifact
retention is seven days. The workflows do not purchase memberships, change
repository visibility or submit a production release.
