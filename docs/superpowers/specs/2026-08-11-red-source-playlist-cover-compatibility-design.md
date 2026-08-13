# Red-source playlist cover compatibility

## Problem

Some NetEase playlist responses expose their image URL as `picUrl` or
`coverImgUrl` instead of the canonical `coverUrl`. `Playlist.fromV1` currently
reads only `coverUrl`, so the UI receives a null URL and renders its normal
placeholder without making an image request.

## Design

Normalize the image field at the `Playlist` API-model boundary. Keep
`coverUrl` as the canonical and highest-priority field, then fall back to
`picUrl` and finally `coverImgUrl`. Empty and whitespace-only values do not
block a later fallback.

No changes are needed in `PlaylistCard`, `AsyncCover`, caching, request
headers, or platform network policy.

## Verification

Model tests cover each supported field, whitespace fallback, and canonical
field priority. Existing model and widget tests provide regression coverage
for other sources and playlist rendering.
