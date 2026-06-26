# Brew Helper

Brew Helper is a macOS menu bar app for managing Homebrew packages and services.

It shows installed formulae, casks, taps, and services, and provides quick service start/stop controls from the main app and the menu bar.

## Requirements

- macOS
- Homebrew installed at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`

## Development

Open `brew-helper.xcodeproj` in Xcode and run the `brew-helper` scheme.

From the command line:

```sh
xcodebuild -project brew-helper.xcodeproj -scheme brew-helper -configuration Debug build
```

## Homebrew Tap Installation

This project is intended to be distributed from a personal Homebrew tap:

```sh
brew tap YOUR_GITHUB_USERNAME/tap
brew install --cask brew-helper
```

The current distribution is unsigned and not notarized. macOS may require manual approval the first time the app is opened.

## Release Checklist

1. Build the app in Release mode.
2. Compress `brew-helper.app` into a `.zip`.
3. Publish the `.zip` on a GitHub Release.
4. Update the cask in your Homebrew tap with the new `version`, `sha256`, and release URL.
5. Test install and uninstall with Homebrew.

## License

Add a license before publishing if you want others to use, modify, or redistribute this project.
