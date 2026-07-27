## Android APK build (GitHub Actions)

Canonical release procedure: [`docs/RELEASE_RUNBOOK.md`](../../docs/RELEASE_RUNBOOK.md).

Workflow: `Android APK`

### How to run

- Go to **Actions** → **Android APK** → **Run workflow**
- Choose `variant`: `debug`, `release`, or `both` (default)
- The workflow reads `app/build.gradle` automatically
- Pushes to `master`/`main` and manual runs perform build verification without publishing a Release
- Release branch pushes do not trigger this workflow
- Before publishing, increase both `versionName` and `versionCode` in `app/build.gradle`

### Publish a version tag

- Commit the release changes, including the version change in `app/build.gradle`
- Run the local release gate described in `docs/RELEASE_RUNBOOK.md`
- Merge and push the reviewed release commit to `master`
- Create and push tag `v<versionName>` to publish the signed APK on the GitHub Release page
- The workflow will reject a tag that does not match `versionName`

### Required release signing secrets

- `ANDROID_KEYSTORE_BASE64`: Base64 content of your `.jks` or `.keystore` file
- `ANDROID_KEYSTORE_PASSWORD`: Keystore password
- `ANDROID_KEY_ALIAS`: Key alias
- `ANDROID_KEY_PASSWORD`: Key password
- `ANDROID_SIGNING_CERT_SHA256`: SHA-256 fingerprint of the permanent release certificate
- Version tags fail instead of publishing when any signing secret is missing or the fingerprint changes

### Release assets

- Production asset: `DuckMusic-v<versionName>.apk`
- Package name: `com.music.player`
- The APK is uploaded only for a matching `v*` tag after tests, Android Lint, package metadata, and certificate verification pass
