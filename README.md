# Vortex

A personal macOS utility that lives in the notch and the menu bar: a quick timer, clipboard history, a shelf for files, screenshot tasks and keys for Claude.

- macOS 14+, Apple silicon
- Works offline; all data stays on this Mac

## Getting started

```sh
brew install xcodegen
make open
```

Then press Run in Xcode. The app is signed with the Personal Team only (see CLAUDE.md).

| Command | What it does |
| --- | --- |
| `make project` | regenerate Vortex.xcodeproj from project.yml |
| `make open` | regenerate and open in Xcode |
| `make build` | compile the app without signing |
| `make test` | run package tests |
| `make check` | make sure no network code lives outside Secrets |

Project settings live in project.yml — changes made in the Xcode UI are lost on the next `make project`.

Docs: [module map](docs/README.md) · [plan](docs/plan.md) · [spec](docs/spec.ru.md)
