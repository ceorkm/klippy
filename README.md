<div align="center">

<img src="Klippy/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="120" alt="Klippy">

# Klippy

**Everything you copy, kept and searchable, without ever leaving your Mac.**

<a href="https://apps.apple.com/us/app/clipboard-manager-klippy/id6812303323">
  <img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-mac-app-store/black/en-us" height="54" alt="Download on the Mac App Store">
</a>

<br>

<img src="https://img.shields.io/github/v/release/ceorkm/klippy?style=flat-square&color=2E3B2A&labelColor=1a1a1a" alt="Latest release">
<img src="https://img.shields.io/badge/macOS-13%2B-2E3B2A?style=flat-square&labelColor=1a1a1a" alt="macOS 13+">
<img src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-2E3B2A?style=flat-square&labelColor=1a1a1a" alt="SwiftUI and AppKit">
<img src="https://img.shields.io/github/license/ceorkm/klippy?style=flat-square&color=2E3B2A&labelColor=1a1a1a" alt="MIT licence">

<br><br>

<img src="docs/hero.png" width="100%" alt="Klippy panel showing clipboard history, search and images">

</div>

<br>

## See it work

https://github.com/ceorkm/klippy/raw/main/docs/demo.mp4

If your browser does not play that inline, [download the clip](docs/demo.mp4).

<br>

## What it does

|   | |
|:---:|:---|
| <img src="docs/icons/clipboard-list.svg" width="22"> | **Keeps your history.** Every copy lands in a searchable list, grouped by day. Text, images, files, colours. Click one to put it back on the clipboard. |
| <img src="docs/icons/blend.svg" width="22"> | **Sorts it for you.** Klippy reads what you copied and files it: links, images, files, colours, code, emails, API keys, card numbers, JSON, phone numbers, addresses. |
| <img src="docs/icons/search.svg" width="22"> | **Finds anything.** Search months of history, or narrow by kind, by date, or by the app you copied from. |
| <img src="docs/icons/pin.svg" width="22"> | **Pin, save, merge.** Pin a clip to the top. Save one with a name. Select several and merge them into one clip, then open it later to get the pieces back. |
| <img src="docs/icons/keyboard.svg" width="22"> | **Stays out of the way.** `⌃⌘V` opens the panel. `⌃⌘1` to `⌃⌘0` recall a clip instantly. `⌃⌘↓` walks back through recent ones. Every shortcut is rebindable. |
| <img src="docs/icons/palette.svg" width="22"> | **Looks how you want.** Seven skins, two flat and five photographic, or drop in a picture of your own. Two widths, three text sizes. |

<br>

## Privacy

This is a clipboard manager, so it is worth being specific.

|   | |
|:---:|:---|
| <img src="docs/icons/wifi-off.svg" width="22"> | Your history lives in `~/Library/Application Support/Klippy` and is never uploaded. No account, no server, no analytics. |
| <img src="docs/icons/shield-check.svg" width="22"> | Anything a password manager marks as concealed is skipped, not recorded. This follows the [nspasteboard.org](http://nspasteboard.org) convention and is on by default. Throwaway copies marked transient are always skipped too. |
| <img src="docs/icons/bookmark.svg" width="22"> | Mark any clip secret to hide it in the list, or tell Klippy never to record whole categories such as card numbers. |
| <img src="docs/icons/image.svg" width="22"> | No Accessibility permission, no Screen Recording, no Full Disk Access. The global shortcuts use a system API that needs none of them. |

**The one network feature.** "Load link previews" asks a site you copied for its own preview image, the way a chat app shows a thumbnail. The request goes to that site and nowhere else. Links that carry a sign-in token or act the moment they open, such as a password reset, are never fetched. Turn the setting off and Klippy never touches the network at all.

Full details in [PRIVACY.md](PRIVACY.md).

<br>

## Install

**[Get it on the Mac App Store](https://apps.apple.com/us/app/clipboard-manager-klippy/id6812303323)**, free, sandboxed and updated automatically.

Or grab the [latest release](https://github.com/ceorkm/klippy/releases/latest). The disk image is signed with a Developer ID, notarized by Apple and stapled, so it opens with no warning and verifies even offline.

<br>

## Build it

```sh
git clone https://github.com/ceorkm/klippy.git
cd klippy
xcodebuild -project Klippy.xcodeproj -scheme Klippy -configuration Debug build
```

Or open `Klippy.xcodeproj` in Xcode and press Run.

```sh
xcodebuild test -project Klippy.xcodeproj -scheme Klippy -destination 'platform=macOS'
```

`package.sh` builds, signs, notarizes and staples a DMG. It reads the signing identity from `.release.env`, which is not committed. Copy `.release.env.example` and fill in your own.

<br>

## How it is put together

| Piece | Job |
| --- | --- |
| `Managers/ClipboardManager` | Watches the pasteboard, stores clips, handles copy-back |
| `Utils/ContentClassifier` | Decides what a clip is, using rules rather than a model |
| `Utils/SearchEngine` | Search and filtering over Core Data |
| `Utils/ClipboardPrivacy` | What must never be written down |
| `Views/PanelController` | Owns the menu bar item, the panel and the global shortcuts |
| `Views/KlippyPanel` | The panel itself |
| `Utils/Skin` | Colour tokens for the skins |

Storage is Core Data on SQLite in WAL mode, with writes on a background context so the panel never waits on the disk. Capture waits for the clipboard to stop moving before reading it, so one copy is one clip however many times the app you copied from rewrites the pasteboard.

<br>

## Licence

MIT. See [LICENSE](LICENSE).

Brand marks shown beside copied links remain the trademarks of their owners and appear only to identify the site a link points to. Interface icons in this document are [Lucide](https://lucide.dev), ISC licensed.

<div align="center"><br><sub>Built in SwiftUI and AppKit. No Electron.</sub></div>
