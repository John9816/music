# DuckMusic Figma Prototype Design

## Goal

Create an editable Figma Design file that communicates the full DuckMusic product across desktop and mobile, using the existing Flutter information architecture and design tokens as the source of truth.

## Scope

The prototype uses the default dark theme as its primary visual baseline: pure black background, layered glass surfaces, Apple-style semantic text colors, and the existing brand green `#2FD365`. A settings branch demonstrates theme switching without duplicating every screen for all five themes.

Desktop frames use `1440 x 900`; mobile frames use `390 x 844`.

Desktop screens:

- Home: greeting, daily radio hero, quick actions, trending songs, curated playlists.
- Discover: recommendation hero, daily recommendations, latest albums.
- Search: query field, source selector, segmented results, song/artist/playlist results.
- Library: favorites, history, downloads, playlists, import/create actions.
- Player: immersive cover atmosphere, record/cover, lyrics, queue, playback controls.
- Profile: account header, owned playlists, membership and account actions.
- Settings: appearance, notifications, storage, desktop integration, about.
- Books: book shelf, book detail, chapter reader.
- Tools: video parsing and AI drawing entry points.

Mobile screens:

- Home, Search, Library, Profile, and Player variants.
- Bottom navigation and persistent Mini Player states.

## Components

Reusable prototype components are represented as editable Figma components or component-like frames: desktop sidebar, mobile bottom navigation, Mini Player, GAppBar, section header, song row, playlist card, album/cover card, search field, segmented control, primary/secondary buttons, setting list tile, dialog, empty state, loading state, and player controls.

## Interactions

The primary clickable flow is Home → Search/Discover → result/detail → Player → Queue/Lyrics → Library/playlist. Secondary connections cover login, theme selection, notifications, storage, books, video parsing, and AI drawing. Buttons and navigation elements use descriptive labels; familiar icon actions use icon buttons with tooltips in the component notes.

## Data and content

Use realistic Chinese sample content based on the product domain: song titles, artists, playlists, book titles, settings labels, and status messages. External network data is not required for the prototype. Where a source screen uses cover imagery, use the existing branding asset or a neutral image placeholder in the editable frame, keeping the image region and cropping behavior representative.

## Validation

Build incrementally in Figma: inspect file and libraries first, create a wrapper/frame skeleton, populate sections one at a time, and capture screenshots after each major section. Validate that text is not clipped, the hierarchy remains editable, desktop/mobile navigation are distinct, and all primary prototype connections resolve to an existing frame.

## Out of scope

Implementing Flutter UI changes, wiring live API data, reproducing every song/playlist state, and creating five complete theme copies are outside this prototype task.
