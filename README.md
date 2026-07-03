<h1 align="center">QuartzNotch</h1>

<p align="center">
  <img src="docs/quartznotch-icon.png" alt="QuartzNotch app icon" width="160" />
</p>

<p align="center">
  A macOS notch companion with media controls, Live Activities, calendar events, quick tools, and Lock Screen integrations.
</p>

---

## About

QuartzNotch turns the area around your MacBook notch into a small interactive space for everyday controls and glanceable information.

It includes a compact media player, customizable pages, a shelf for files, quick timers, clipboard tools, calendar events, camera preview, Live Activities, Lock Screen widgets, and a Liquid Glass-inspired visual style.

QuartzNotch started as a fork of Quartz Notch and has since evolved with a redesigned interface, new Lock Screen features, custom layout behavior, and many visual refinements.

## Features

- Compact notch interface with multiple customizable pages
- Music controls and Now Playing information
- Lock Screen Live Activities for music and timers
- Fullscreen album artwork on the Lock Screen
- Calendar and reminder events inside the notch
- File shelf and quick sharing tools
- Quick timers and clipboard utilities
- Camera preview with configurable click behavior
- Bluetooth, battery, focus, timer, shelf, and media Live Activities
- Liquid Glass-style appearance option
- Light/Dark adaptive app icon support
- Customizable toolbar and page order

## What’s New in 0.4.1

* A significantly more pronounced Liquid Glass design throughout the app
* A new real-time synchronized audio visualizer, similar to the one used in the iPhone’s Dynamic Island
* A complete redesign of the lyrics experience, with full-screen Apple Music-style lyrics on the Lock Screen
* Added a quick volume control
* Added a “Buy Me a Coffee” button in the About section for anyone who would like to support the app’s development — completely optional, of course
* Full app localization in multiple languages
* Reworked animations, especially for locking and unlocking the interface
* The music source badge displayed on album artwork can now be disabled for a cleaner, more minimal look
* Initial codebase cleanup, which should slightly improve the app’s performance and efficiency
* Full compatibility with macOS 27
* Fixed every bug I was able to identify — please report any issues you encounter
* Improved the Calendar user experience
* Much more

## Requirements

- macOS 14 or later
- Apple Silicon or Intel Mac
- Xcode 16 or later if you want to build from source

## Download

The latest release is available from GitHub Releases:

https://github.com/Clayton630/QuartzNotch/releases

> [!IMPORTANT]
> Current builds are not notarized with an Apple Developer ID.
> On first launch, macOS may block the app as coming from an unidentified developer.
> If you trust the build, open `System Settings > Privacy & Security` and choose `Open Anyway`.

## Build From Source

Clone the repository:

```bash
git clone https://github.com/Clayton630/QuartzNotch.git
cd QuartzNotch
```

Open the project in Xcode:

```bash
open QuartzNotch.xcodeproj
```

Then build and run the `QuartzNotch` scheme from Xcode with `Cmd + R`.

You can also build from Terminal:

```bash
xcodebuild \
  -project QuartzNotch.xcodeproj \
  -scheme QuartzNotch \
  -configuration Debug \
  build
```

## Release Packaging

Release builds are generated with the release script:

```bash
bash Configuration/release/make_release.sh \
  --version 0.4.1 \
  --build 1035 \
  --oss \
  --sparkle-account quartznotch_clayton
```

This creates the app, packages it into a DMG, and prints the Sparkle appcast enclosure metadata.

## Repository Structure

```text
QuartzNotch/              Main macOS app source
QuartzNotchXPCHelper/     Helper service used by the app
QuartzNotchScreenSaver/   Screen saver / backdrop component
Configuration/            Release, DMG, and Sparkle tooling
mediaremote-adapter/      MediaRemote bridge used for media integration
updater/                  Sparkle appcast
.github/                  GitHub issue templates
```

Some internal target names still use `QuartzNotch` because QuartzNotch began as a fork. The public app name is QuartzNotch.

## Contributing

Bug reports and feature requests are welcome through GitHub Issues.

Please read `CONTRIBUTING.md` before opening an issue.

## License

QuartzNotch is distributed under the GNU General Public License v3.0.

See `LICENSE` for the full license text.
