# Klippy

Everything you copy, kept and searchable, without ever leaving your Mac.

Klippy is a clipboard manager that lives in the menu bar. Press Ctrl-Cmd-V and
everything you have copied is right there, sorted and searchable. Native SwiftUI
and AppKit. No Electron, no account, no server, no telemetry.

Requires macOS 13 or later.

## What it does

**Keeps your history.** Every copy lands in a searchable list, grouped by day.
Text, images, files, colours. Click one to put it back on the clipboard.

**Sorts it for you.** Klippy reads what you copied and files it: links, social
links, images, files, colours, code, emails, API keys, card numbers, JSON,
Markdown, numbers, dates, phone numbers, addresses, IP addresses. Filter by any
of them, or by date, including a custom range.

**Pin, save, merge.** Pin a clip to keep it at the top. Save one with a name.
Select several and merge them into a single clip, then expand it again later to
see the parts.

**Gets out of your way.** Ctrl-Cmd-V opens the panel. Ctrl-Cmd-1 through 0
recall a slot directly. Ctrl-Cmd-Down walks back through recent clips. Every
shortcut can be rebound in Settings.

**Looks how you want.** Seven skins, two flat and five photographic, or your own
picture, plus panel width and text size.

## Privacy

This is a clipboard manager, so it is worth being specific.

- Your history is stored in `~/Library/Application Support/Klippy` and is never
  uploaded anywhere. There is no server and no account.
- Klippy skips anything an app marks as concealed, so password managers are
  ignored rather than recorded. This follows the
  [nspasteboard.org](http://nspasteboard.org) convention and is on by default.
- Throwaway copies that automation tools mark as transient are never recorded.
- You can mark any clip secret by hand to hide its contents in the list, and
  tell Klippy to never record whole kinds of thing, such as card numbers.
- Klippy needs no Accessibility permission, no Screen Recording permission and
  no Full Disk Access. The global shortcuts use a system API that does not
  require handing over control of your Mac.

**The one network feature.** "Load link previews" in Settings asks a site you
copied for its own preview image, the way a chat app shows a thumbnail. The
request goes to that site and nowhere else. Links that carry a credential or
act the moment they load, such as a password reset or a sign-in link, are never
fetched, so a preview can never burn a one-time link. Turn the setting off and
Klippy never touches the network at all.

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
| `Utils/ClipboardPrivacy` | What must never be written down |
| `Views/PanelController` | Owns the menu bar item, the panel and the global shortcuts |
| `Views/KlippyPanel` | The panel itself |
| `Utils/Skin` | Colour tokens for the skins |

Storage is Core Data on SQLite in WAL mode, with writes on a background context
so the panel never waits on the disk. Capture waits for the clipboard to stop
moving before reading it, so one copy is one clip however many times the app
you copied from rewrites the pasteboard.

## Licence

MIT. See [LICENSE](LICENSE).

Brand marks shown beside copied links remain the trademarks of their owners and
appear only to identify the site a link points to.
