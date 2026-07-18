## Android APK build (GitHub Actions)

Workflow: `Android APK`

### How to run

- Go to **Actions** → **Android APK** → **Run workflow**
- Choose `variant`: `debug`, `release`, or `both` (default)
- The workflow reads `app/build.gradle` automatically
- Normal branch push or manual run only performs the build verification and does not upload artifacts
- For `1.0.3`, make sure `app/build.gradle` contains `versionName "1.0.3"` and `versionCode 4`

### Build version `1.0.3`

- Commit the version change in `app/build.gradle`
- Push branch normally to verify the build
- Create and push tag `v1.0.3` to publish the signed APK on the GitHub Release page
- The workflow will reject a tag that does not match `versionName`

### Required release signing secrets

- `ANDROID_KEYSTORE_BASE64`: Base64 content of your `.jks` or `.keystore` file
- `ANDROID_KEYSTORE_PASSWORD`: Keystore password
- `ANDROID_KEY_ALIAS`: Key alias
- `ANDROID_KEY_PASSWORD`: Key password
- `ANDROID_SIGNING_CERT_SHA256`: SHA-256 fingerprint of the permanent release certificate
- Version tags fail instead of publishing when any signing secret is missing or the fingerprint changes

### Release assets

- Production asset: `DuckMusic-v1.0.3.apk`
- Package name: `com.music.player`
- The APK is uploaded only for a matching `v*` tag after tests, Android Lint, package metadata, and certificate verification pass
