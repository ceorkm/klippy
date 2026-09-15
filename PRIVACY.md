# Privacy Policy

**Last updated: 14 September 2026**

Klippy is a clipboard manager for macOS. It keeps a history of what you copy so
you can get it back later.

## The short version

Your clipboard history never leaves your Mac. There is no account, no server,
no analytics, and no tracking. We cannot see anything you copy, because none of
it is ever sent to us.

## What Klippy stores, and where

Klippy saves the things you copy to a database on your own Mac:

```
~/Library/Application Support/Klippy/
```

That includes text, images, file references, and the name of the app a clip
came from. It stays on your machine. Deleting a clip in Klippy removes it from
that database, and "Delete all history" in Settings empties it.

Klippy also keeps small preference values (your chosen skin, panel width,
keyboard shortcuts) in the standard macOS preferences store. These are settings
only. No clipboard content is kept there.

## What Klippy does not store

Klippy skips anything an app marks as private. Password managers such as
1Password, Bitwarden and Keychain flag their copies as concealed, and Klippy
ignores those copies rather than recording them. This follows the convention
published at [nspasteboard.org](http://nspasteboard.org). You can turn this off
in Settings, but it is on by default.

You can also mark any individual clip as secret by hand, which hides its
contents in the list.

## The one network feature

Klippy has a setting called **Load link previews**. When it is on and you copy
a web link, Klippy asks that website for its preview image, the same way a
messaging app shows a thumbnail when you paste a link.

What this means in practice:

- The request goes to the website you copied, and nowhere else.
- The website can see that someone asked it for a preview. That is an ordinary
  web request from your Mac, and it carries no identifier we attach.
- Nothing is sent to us or to any third party. There is no proxy or middleman.
- Downloaded previews are cached on your Mac and are cleared when you turn the
  setting off.

Brand icons for common sites are built into the app, so those need no network
request at all.

If you would rather Klippy never touch the network, switch **Load link
previews** off in Settings. Everything else keeps working.

## Permissions

Klippy needs no Accessibility permission, no Screen Recording permission, and
no Full Disk Access. Its keyboard shortcuts use a system API that does not
require granting it control of your Mac.

## Children

Klippy is not directed at children and collects nothing from anyone.

## Changes

If this policy changes, the updated version will be posted here with a new date
at the top.

## Contact

Questions about this policy can be raised as an issue at
<https://github.com/ceorkm/klippy/issues>.
