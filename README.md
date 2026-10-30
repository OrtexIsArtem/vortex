# Vortex

A macOS utility that lives in your MacBook's notch, or in the menu bar on a Mac without one. Hover over the notch and it opens with the tools you reach for a dozen times a day.

- **Timer**: set the minutes on a drum, and watch the countdown in the notch. When time is up, it plays a sound, flashes and shows a notification.
- **Clipboard**: your last copies plus pinned ones. Text, links, images and files.
- **Shelf**: put files aside and drag them out later, into any app. Unpinned files clear after a day.
- **Tasks**: a shortcut freezes the screen; frame an area and press Return. You get a task with the screenshot, its recognized text and the page address from your browser.
- **Keys for Claude**: keep database URLs, API tokens and passwords in the macOS keychain. Claude Code runs commands with `{{key}}` placeholders through a local MCP server, and never sees a value. Vortex asks you once per key per session.
- **Keyboard cleaning**: lock every key while you wipe the keyboard.

Vortex speaks English and Ukrainian, and follows light and dark mode.

## Privacy
- Vortex works offline: no analytics, no auto-updates, no network access. Its only listener is the MCP server for Claude Code, on 127.0.0.1 only and guarded by a token.
- Your data stays in `~/Library/Application Support/Vortex`. Secrets stay in your login keychain.
- Text recognition runs on your Mac.

## Permissions
On first launch, Vortex walks you through the permissions it can use. Every one of them is optional:

| Permission | Used for |
| --- | --- |
| Notifications | the timer's end, Claude's key requests while the window is closed |
| Accessibility | keyboard cleaning |
| Screen Recording | tasks from the screen |

A feature whose permission is off shows a yellow warning. Click it to turn the permission on.

## Requirements
macOS 14 or later, on Apple silicon.

## Install

### Download a release (no Xcode needed)
1. Download `Vortex-<version>.zip` from [Releases](https://github.com/OrtexIsArtem/vortex/releases), unzip it, and move **Vortex** to **Applications**.
2. Open Vortex. macOS will say it can't verify the developer: Vortex isn't notarized by Apple, because that needs a paid developer account. Click **Done**.
3. Open **System Settings › Privacy & Security**. Scroll to **Security** and click **Open Anyway** next to "Vortex was blocked". Confirm with your password.

   In Terminal you can do the same in one line: `xattr -dr com.apple.quarantine /Applications/Vortex.app`.
4. Vortex shows its setup. To have it start with your Mac, turn on **Open at login** there, or later in Settings.

After an update, macOS may treat the new version as a different app for **Accessibility** and **Screen Recording**. If a yellow warning appears, open it and switch Vortex off and on again in System Settings.

### Build it yourself
With Xcode installed:
```sh
brew install xcodegen
git clone https://github.com/OrtexIsArtem/vortex.git && cd vortex
cp Config/Local.xcconfig.example Config/Local.xcconfig   # put your team ID in it, or leave it as is
make install
```
`make install` builds a release, puts it in **Applications** and opens it. With a team ID (a free Personal Team works), your permissions survive rebuilds. Without one, the build is signed ad hoc, so macOS asks for the permissions again after each rebuild.

For daily use, prefer `make install` over a Run in Xcode. A debug session ends when the Mac sleeps for a while, and the app ends with it.

[CONTRIBUTING.md](CONTRIBUTING.md) explains how to work on the code.

## Claude Code
In Vortex, open **Keys** and press **Connect**, or run the command it shows you once in Terminal. Claude Code then lists your keys by name and can use them in commands.

## License
[MIT](LICENSE)
