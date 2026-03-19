## Android APK build (GitHub Actions)

Workflow: `Android APK`

### How to run

- Go to **Actions** → **Android APK** → **Run workflow**
- Choose `variant`: `debug`, `release`, or `both` (default)
- The workflow reads `app/build.gradle` automatically and uses the current `versionName` for artifact names
- For `1.0.1`, make sure `app/build.gradle` contains `versionName "1.0.1"` and `versionCode 2`

### Build version `1.0.1`

- Commit the version change in `app/build.gradle`
- Push branch normally to get CI artifacts
- Create and push tag `v1.0.1` to trigger GitHub Release publishing
- The workflow will reject a tag that does not match `versionName`

### Optional release signing secrets

- `ANDROID_KEYSTORE_BASE64`: Base64 content of your `.jks` or `.keystore` file
- `ANDROID_KEYSTORE_PASSWORD`: Keystore password
- `ANDROID_KEY_ALIAS`: Key alias
- `ANDROID_KEY_PASSWORD`: Key password
- If these secrets are absent, the workflow still builds a release APK, but it will be unsigned by default

### Artifacts

- `music-player-v<version>-debug`: `app/build/outputs/apk/debug/*.apk`
- `music-player-v<version>-release`: `app/build/outputs/apk/release/*.apk`
