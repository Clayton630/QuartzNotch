<h1 align="center">QuartzNotch</h1>

<p align="center">
  <img src="docs/quartznotch-icon.png" alt="QuartzNotch App Icon" width="160" />
</p>

QuartzNotch is a fork of BoringNotch focused on smoother interactions, richer live activities, and a more compact, adaptive notch experience.

## Changelog

- Made the notch more compact, with dynamic width that adapts to displayed content.
- Introducing a new page navigation system that is smoother and more intuitive.
- Added a third page with quick timers and a fully functionnal clipboard manager.
- Added a new toolbar capsule for quick access to key features and actions.
- Merged music providers so no manual provider selection is needed anymore.
- Added a new track-skipping animation inspired by iOS Dynamic Island behavior.
- Slightly refined the notch shape.
- Added a new semi Liquid Glass background option
- Completely revamped the files shelf for a better experience
- Improved the Settings experience overall.
- Updated default options for a better out-of-the-box experience.
- Refined media page and controls
- Added a dedicated Live Activities category in Settings.
- Revamped the charging live activity, now with an adaptive tinting.
- Added a new animated lock screen live activity.
- Added a shelf live activity showing how many files are in it.
- Added an expandable Bluetooth devices live activity.
- Added an expandable timer live activity with synchronised trackpad vibrations.
- Added a focus mode live activity
- Added quick actions to the Now Playing live activity (hover on the left side to show sneak peek, and hover on the right side to quickly play/pause).
- Added support for displaying two live activities at the same time.
- Overhauled and improved animations across the app.

## Installation

System requirements:
- macOS 14 or later
- Apple Silicon or Intel Mac

> [!IMPORTANT]
> This build is unsigned with an Apple Developer certificate.
> On first launch, macOS may block it as an unidentified developer app.
> You can allow it from `System Settings > Privacy & Security > Open Anyway`.

## Build From Source

```bash
git clone https://github.com/Clayton630/QuartzNotch
cd codex
open boringNotch.xcodeproj
```

Build and run from Xcode (`Cmd + R`).
