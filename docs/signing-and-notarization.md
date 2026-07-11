# Developer ID Signing and Notarization

Public macOS distribution outside the App Store requires a Developer ID Application certificate and Apple notarization for a normal Gatekeeper experience.

## 1. Create the certificate

1. Join the Apple Developer Program with the Apple account that owns the app.
2. Open Certificates, Identifiers & Profiles in the Apple Developer portal.
3. Create a **Developer ID Application** certificate. If the portal requests a CSR, create one in Keychain Access with Certificate Assistant -> Request a Certificate From a Certificate Authority, then upload it.
4. Download the certificate and open it to install it in the login Keychain. Keep the private key on this Mac and backed up securely.

Verify:

```bash
security find-identity -v -p codesigning
```

The output must include `Developer ID Application: ... (TEAMID)`. An `Apple Development` identity is not sufficient for public DMG distribution.

## 2. Store notarization credentials

Create an app-specific password for the Apple account, then store it in Keychain. Do not put it in an environment file or repository.

```bash
xcrun notarytool store-credentials shadow-coach-notary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

An App Store Connect API key can also be used for automated CI releases.

## 3. Build, sign, submit, and staple

```bash
export SHADOW_COACH_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export SHADOW_COACH_NOTARY_PROFILE="shadow-coach-notary"
./scripts/package-dmg.sh
```

The packaging script builds with the hardened runtime, signs the app and DMG, submits the DMG with `notarytool`, waits for Apple's result, and staples the ticket.

## 4. Verify before release

```bash
codesign --verify --deep --strict --verbose=2 "build/Shadow Coach.app"
spctl --assess --type execute --verbose=4 "build/Shadow Coach.app"
xcrun stapler validate "build/Shadow Coach.dmg"
```

Test the DMG from a clean macOS user account or another Mac before uploading it to GitHub Releases.

## Secret handling

Never share or commit the certificate private key, `.p12` export, app-specific password, App Store Connect private key, or notarization profile contents.
