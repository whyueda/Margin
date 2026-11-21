# Margin

A menu bar note taker for macOS 13 and later (Apple silicon and Intel).

## Install

Download the newest `Margin-<version>.dmg` from [Releases](../../releases/latest), open it and drag Margin onto Applications.
Margin checks for a newer release once a day and offers it from the menu bar icon (**Check for Updates…** checks right away).

## Build

```bash
./build.sh            # builds .build/Margin.app
./make_installer.sh   # builds dist/Margin-<version>.dmg
```

## Release a new version

1. Raise `CFBundleShortVersionString` and `CFBundleVersion` in `build.sh`.
2. Run `./release.sh "What changed"` — it builds the installer and publishes it as a GitHub release.
