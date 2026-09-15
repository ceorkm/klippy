# Klippy

A clipboard manager for macOS that lives in the menu bar. Everything you copy
stays on your Mac.

Native SwiftUI and AppKit, no Electron, no account, no telemetry.

Requires macOS 13 or later.

## What it does

**Keeps your history.** Every copy lands in a searchable list, grouped by day.
Text, images, files, colours. Click one to put it back on the clipboard.

**Sorts it for you.** Klippy reads what you copied and files it: links, social
links, images, files, colours, code, emails, API keys, card numbers, JSON,
Markdown, numbers, dates, phone numbers, addresses, IP addresses. Filter by any
of them, or by date, including a custom range.

**Pin, save, merge.** Pin a clip to keep it at the top. Save one to snippets
with a name. Select several and merge them into a single clip, then expand it
again later to see the parts.

**Gets out of your way.** Ctrl-Cmd-V opens the panel. Ctrl-Cmd-1 through 0
recall a slot directly. Ctrl-Cmd-Down walks back through recent clips. Every
shortcut can be rebound in Settings.

**Looks how you want.** Seven skins, two flat and five photographic, plus panel
width and text size.

## Privacy

This is a clipboard manager, so it is worth being specific.

- Your history is stored in `~/Library/Application Support/Klippy` and is never
  uploaded anywhere. There is no server and no account.
- Klippy skips anything an app marks as concealed, so password managers like
  1Password and Bitwarden are ignored rather than recorded. This follows the
  [nspasteboard.org](http://nspasteboard.org) convention and is on by default.
- You can mark any clip secret by hand to hide its contents in the list.
- Klippy needs no Accessibility permission, no Screen Recording permission and
  no Full Disk Access. The global shortcuts use a system API that does not
  require handing over control of your Mac.

**The one network feature.** "Load link previews" in Settings asks a site you
copied for its own preview image, the way a chat app shows a thumbnail. The
request goes to that site and nowhere else. Brand icons for common sites are
built into the app so those need no request at all. Turn the setting off and
Klippy never touches the network.

Full details in [PRIVACY.md](PRIVACY.md).

## Build it

```sh
git clone https://github.com/ceorkm/klippy.git
cd klippy
xcodebuild -project Klippy.xcodeproj -scheme Klippy -configuration Debug build
```

Or open `Klippy.xcodeproj` in Xcode and press Run.

Tests:

```sh
xcodebuild test -project Klippy.xcodeproj -scheme Klippy -destination 'platform=macOS'
```

## Release

`package.sh` builds, signs with a Developer ID certificate, notarizes and
staples a DMG. It reads the signing identity from `.release.env`, which is not
committed. Copy `.release.env.example` and fill in your own values.

## How it is put together

| Piece | Job |
| --- | --- |
| `Managers/ClipboardManager` | Watches the pasteboard, stores clips, handles copy-back |
| `Utils/ContentClassifier` | Decides what a clip is, using rules rather than a model |
| `Utils/SearchEngine` | Search and filtering over Core Data |
| `Views/PanelController` | Owns the menu bar item, the panel and the global shortcuts |
| `Views/KlippyPanel` | The panel itself |
| `Utils/Skin` | Colour tokens for the seven skins |
| `Utils/SiteIcon` | Brand icons for copied links |

Storage is Core Data on SQLite in WAL mode, with writes on a background context
so the panel never waits on the disk.

## Credits

Brand icons come from [Simple Icons](https://github.com/simple-icons/simple-icons),
released under CC0-1.0. Each brand's mark remains the trademark of its owner and
is used here only to identify that site.

## Licence

MIT. See [LICENSE](LICENSE).

## The mascot

Klippy's mark is not an image file. It lives in `design/mark/klippy.py` as
geometry: `sample(t)` returns a pose, `svg(pose)` draws it, and the PNGs and the
menu bar icon are that SVG rasterised. Shapes, colours and expressions are
catalogues, so adding one is a row in a table.

    cd design/mark
    python3 test_klippy.py        # the engine
    python3 build_showcase.py     # writes showcase.html
    python3 test_showcase.py      # checks the page and the engine still agree

The face model, eyes as holes in a mask, the head as a sphere the eyes ride on,
and solving eye placement once at import rather than every frame, is taken from
[jeremy-prt/bloub](https://github.com/jeremy-prt/bloub) (MIT), an SVG recreation
of the x.ai avatar. Their write-up on why a per-frame solver makes eyes tremble
is worth reading.
