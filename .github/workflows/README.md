## Android APK build (GitHub Actions)

Workflow: `Android APK`

### How to run

- Go to **Actions** → **Android APK** → **Run workflow**
- Choose `variant`: `debug`, `release`, or `both` (default)
- The workflow reads `app/build.gradle` automatically
- Normal branch push or manual run only performs the build verification and does not upload artifacts
- For `1.0.2`, make sure `app/build.gradle` contains `versionName "1.0.2"` and `versionCode 3`

### Build version `1.0.2`

- Commit the version change in `app/build.gradle`
- Push branch normally to verify the build
- Create and push tag `v1.0.2` to publish `.apk` files on the GitHub Release page
- The workflow will reject a tag that does not match `versionName`

### Optional release signing secrets

- `ANDROID_KEYSTORE_BASE64`: Base64 content of your `.jks` or `.keystore` file
- `ANDROID_KEYSTORE_PASSWORD`: Keystore password
- `ANDROID_KEY_ALIAS`: Key alias
- `ANDROID_KEY_PASSWORD`: Key password
- If these secrets are absent, the workflow still builds a release APK, but it will be unsigned by default

### Release assets

- `app/build/outputs/apk/debug/*.apk`
- `app/build/outputs/apk/release/*.apk`
- These files are uploaded only to GitHub Release when the ref is a `v*` tag
