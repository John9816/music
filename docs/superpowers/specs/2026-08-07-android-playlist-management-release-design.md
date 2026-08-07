# Android Playlist Management Release Design

## Scope

This Android-only release adds complete deletion workflows for the user's
playlist library, makes the toolbox the sole entry point for live TV, removes
playlist import from the toolbox, and fixes source-specific playback clocks.
No desktop or iOS artifacts will be published.

## Playlist Deletion

The playlist directory supports owned and favorited playlists. Each row exposes
a single delete action. A manage action enters selection mode, where users can
select individual rows, select all visible rows, and delete the selection after
confirmation.

Deleting an owned or imported playlist calls the existing user-playlist delete
endpoint. Deleting a favorited remote playlist calls the existing remove
favorite endpoint. Batch deletion invokes those existing operations
sequentially, preserves failed rows, reports the failure count, and reloads the
library once at the end. This avoids requiring a backend deployment.

Owned and imported playlist detail pages also support single-track deletion and
selection-mode batch deletion through the existing playlist-item endpoint.
Remote favorite playlist contents remain read-only because the app must not
modify a third-party playlist.

## Navigation

Live TV is removed from the mobile bottom navigation and desktop sidebar. The
toolbox remains the single live TV entry and passes the global player pause
callback before opening a channel. The toolbox removes its playlist-import
card, while playlist import remains available from the library and playlist
management surfaces.

## Playback Clock

QQ and Kuwo streams already bypass the experimental streaming cache, but custom
request headers still cause just_audio to route media through its localhost
header proxy. On iOS, macOS, and Android, the player sends headers through the
native media implementation instead. NetEase keeps its compatible automatic
cache path. Windows and other unsupported platforms retain proxy-based header
delivery.

## Testing

Widget tests cover single and bulk playlist deletion, owned-track deletion,
navigation without a live tab, and toolbox contents. Unit tests cover API delete
paths and platform proxy/cache policies. Full `flutter test`, `flutter analyze`,
Android release build, package metadata, and production signature checks gate
publication.

## Release

The release uses `android-ecs-v<version>`. CI publishes the universal APK and
ECS `latest.json`, and creates the legacy `flutter-v<version>` GitHub Release so
installed 1.1.27 clients can update. The public tag is pushed only after an
explicit final review of version, build number, commit, tag, platform, and
assets.
