# ECS Update Hosting

For the complete build, GitHub, ECS, verification, and rollback procedure, use [RELEASE_RUNBOOK.md](RELEASE_RUNBOOK.md).

The app checks `https://api.751152.xyz/updates/latest.json` first and falls back to GitHub when the ECS file is missing or unavailable.

## ECS files

The Java API now serves the update directory itself. Use `/opt/website/updates` on the ECS host:

```nginx
location /updates/ {
    proxy_pass http://127.0.0.1:8090;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

The directory must contain `latest.json` and the matching signed APKs. The manifest format is:

```json
{
  "version": "1.0.5",
  "buildNumber": 6,
  "downloads": {
    "arm64-v8a": "https://api.751152.xyz/updates/DuckMusic-v1.0.5-arm64-v8a.apk",
    "armeabi-v7a": "https://api.751152.xyz/updates/DuckMusic-v1.0.5-armeabi-v7a.apk",
    "x86_64": "https://api.751152.xyz/updates/DuckMusic-v1.0.5-x86_64.apk"
  },
  "description": "DuckMusic 1.0.5",
  "forceUpdate": false,
  "minBuildNumber": 0
}
```

## GitHub Actions secrets

Add these repository secrets before pushing a release tag:

```text
ECS_HOST              ECS public IP or hostname
ECS_PORT              SSH port, normally 22
ECS_USER              SSH deployment user
ECS_SSH_PRIVATE_KEY   private key for that user
ECS_KNOWN_HOSTS       output of ssh-keyscan -H <host> -p <port>
ECS_UPDATE_DIR        /opt/website/updates
ECS_UPDATE_BASE_URL   https://api.751152.xyz/updates
```

The upload step is optional. Without these secrets, the workflow still publishes the GitHub Release and the app falls back to it.
