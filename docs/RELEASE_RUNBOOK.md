# Android Release Runbook

This is the canonical procedure for building and publishing a signed DuckMusic APK to GitHub and ECS from Windows PowerShell.

## Release targets

```text
GitHub repository: git@github.com:John9816/music.git
GitHub branch:     master
GitHub tag:        v<versionName>
ECS host:          api.751152.xyz
ECS SSH user:      root
ECS SSH port:      22
ECS update dir:    /opt/website/updates
ECS base URL:      https://api.751152.xyz/updates
Local SSH key:     $HOME/.ssh/id_ed25519
Android package:   com.music.player
Release cert SHA-256:
c6821dcc9ac2395eb9a810f1b9ff250a3a7186ab899fdd8de772d852cf542a72
```

The app checks ECS first and falls back to GitHub Releases.

## 1. Set release variables

Run these commands from the repository root. Change only the version values for each release.

```powershell
$VersionName = "1.1.22"
$VersionCode = 33
$ReleaseBranch = "codex/release-$VersionName"
$ApkName = "DuckMusic-v$VersionName.apk"
$ReleaseDir = Join-Path $PWD "app\build\outputs\apk\release"
$ApkPath = Join-Path $ReleaseDir $ApkName
$ManifestPath = Join-Path $ReleaseDir "latest.json"
$EcsHost = "api.751152.xyz"
$EcsUser = "root"
$EcsPort = 22
$EcsDir = "/opt/website/updates"
$SshKey = Join-Path $HOME ".ssh\id_ed25519"
```

## 2. Prepare the release branch

Start from an up-to-date `master`. Do not stage `.claude/settings.local.json`, signing files, `local.properties`, or unrelated worktree changes.

```powershell
git status --short --branch
git switch master
git pull --ff-only origin master
git switch -c $ReleaseBranch
```

Update `app/build.gradle`:

```groovy
versionCode 33
versionName "1.1.22"
```

Rules:

- `versionCode` must be greater than every published build number.
- `versionName` must be new.
- The release tag must be exactly `v$VersionName`.

## 3. Build and validate locally

The local `keystore.properties` and referenced keystore file must exist. They are git-ignored and must never be committed.

```powershell
.\gradlew.bat :app:testDebugUnitTest :app:lintRelease :app:assembleRelease --no-daemon --console=plain
```

Stage the release filename and locate the newest Android build-tools:

```powershell
Copy-Item (Join-Path $ReleaseDir "app-release.apk") $ApkPath -Force

$BuildTools = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory |
    Where-Object Name -Match '^\d+\.\d+\.\d+$' |
    Sort-Object { [version]$_.Name } |
    Select-Object -Last 1
$ApkSigner = Join-Path $BuildTools.FullName "apksigner.bat"
$Aapt = Join-Path $BuildTools.FullName "aapt.exe"
```

Verify signature, package, version, and checksum:

```powershell
& $ApkSigner verify --verbose --print-certs $ApkPath
& $Aapt dump badging $ApkPath | Select-Object -First 1
Get-FileHash $ApkPath -Algorithm SHA256
Get-Content -Raw (Join-Path $ReleaseDir "output-metadata.json")
```

Do not publish unless all of these are true:

- Gradle reports `BUILD SUCCESSFUL`.
- Package name is `com.music.player`.
- APK version matches `$VersionCode / $VersionName`.
- Certificate SHA-256 matches the permanent release certificate above.

## 4. Generate latest.json without BOM

```powershell
$Manifest = [ordered]@{
    version = $VersionName
    buildNumber = $VersionCode
    downloadUrl = "https://api.751152.xyz/updates/$ApkName"
    description = "DuckMusic $VersionName"
    forceUpdate = $false
    minBuildNumber = 0
} | ConvertTo-Json

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ManifestPath, $Manifest + [Environment]::NewLine, $Utf8NoBom)
Get-Content -Raw $ManifestPath | ConvertFrom-Json
Get-FileHash $ManifestPath -Algorithm SHA256
```

## 5. Publish ECS first

Upload to `/tmp`, compare hashes, then move the APK before `latest.json`. This prevents clients from seeing a manifest whose APK is not available yet.

```powershell
$RemoteManifest = "latest-$VersionName.json"

scp -i $SshKey -P $EcsPort $ApkPath "${EcsUser}@${EcsHost}:/tmp/$ApkName"
scp -i $SshKey -P $EcsPort $ManifestPath "${EcsUser}@${EcsHost}:/tmp/$RemoteManifest"

ssh -i $SshKey -p $EcsPort "${EcsUser}@${EcsHost}" "sha256sum /tmp/$ApkName /tmp/$RemoteManifest"
```

The remote hashes must match the local hashes. Back up the current manifest and perform the switch:

```powershell
$BackupName = "latest.json.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

ssh -i $SshKey -p $EcsPort "${EcsUser}@${EcsHost}" "cp -p $EcsDir/latest.json $EcsDir/$BackupName"
ssh -i $SshKey -p $EcsPort "${EcsUser}@${EcsHost}" "chmod 0644 /tmp/$ApkName"
ssh -i $SshKey -p $EcsPort "${EcsUser}@${EcsHost}" "mv -f /tmp/$ApkName $EcsDir/$ApkName"
ssh -i $SshKey -p $EcsPort "${EcsUser}@${EcsHost}" "chmod 0644 /tmp/$RemoteManifest"
ssh -i $SshKey -p $EcsPort "${EcsUser}@${EcsHost}" "mv -f /tmp/$RemoteManifest $EcsDir/latest.json"
```

Verify the real public path, including a full APK download:

```powershell
curl.exe -fsS "https://api.751152.xyz/updates/latest.json"
curl.exe -fsSI "https://api.751152.xyz/updates/$ApkName"

$PublicApk = Join-Path $env:TEMP "$ApkName-public.apk"
curl.exe -fsSL --max-time 120 -o $PublicApk "https://api.751152.xyz/updates/$ApkName"
Get-FileHash $PublicApk -Algorithm SHA256
```

The public APK hash must equal the local APK hash.

## 6. Commit and publish GitHub

Review and stage only intended release files. Use explicit paths when the worktree contains unrelated changes.

```powershell
git status --short
git diff --check
git add app/build.gradle
git add -p app/src
git diff --cached --check
git diff --cached --stat
git commit -m "Release ${VersionName}: <short release summary>"
git push -u origin $ReleaseBranch
```

Explicitly add any reviewed new files because `git add -p` does not automatically include untracked files. Use `git add app` only when every change under `app/` belongs to the release.

Fast-forward the reviewed release commit to `master`, then push the matching annotated tag:

```powershell
git switch master
git merge --ff-only $ReleaseBranch
git push origin master
git tag -a "v$VersionName" -m "DuckMusic v$VersionName"
git push origin "v$VersionName"
```

Pushing `v$VersionName` triggers `.github/workflows/android-debug-apk.yml`. The tag workflow validates the version and signing certificate, then creates the GitHub Release with `DuckMusic-v$VersionName.apk`.

## 7. Rollback ECS manifest

The previous APK remains available because each APK has a versioned filename. To roll back update discovery, restore the saved manifest:

```powershell
ssh -i $SshKey -p $EcsPort "${EcsUser}@${EcsHost}" "cp -p $EcsDir/$BackupName $EcsDir/latest.json"
curl.exe -fsS "https://api.751152.xyz/updates/latest.json"
```

## Fast checklist

1. Increase `versionCode` and `versionName`.
2. Run tests, Release Lint, and `assembleRelease`.
3. Verify package metadata, certificate, and SHA-256.
4. Upload APK and BOM-free `latest.json` to ECS temporary paths.
5. Compare hashes, back up the old manifest, then switch APK and manifest.
6. Verify the public manifest and full public APK hash.
7. Commit only intended files, merge to `master`, and push matching `v*` tag.
