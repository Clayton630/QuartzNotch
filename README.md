<p align="center">
  <img src="docs/quartznotch-icon.png" alt="QuartzNotch app icon" width="118" />
</p>

<h1 align="center">QuartzNotch</h1>

<p align="center">
  <strong>Your MacBook notch, turned into a living control surface.</strong>
</p>

<p align="center">
  Media controls, Live Activities, lyrics, calendar events, quick tools, Lock Screen integrations, and a Liquid Glass-inspired interface for macOS.
</p>

<p align="center">
  <a href="https://github.com/Clayton630/QuartzNotch/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Clayton630/QuartzNotch?style=for-the-badge&label=Release&color=111111"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-111111?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-macOS-111111?style=for-the-badge&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-GPLv3-111111?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="https://github.com/Clayton630/QuartzNotch/releases/latest"><strong>Download</strong></a>
  ·
  <a href="#what-it-does"><strong>Features</strong></a>
  ·
  <a href="#build-from-source"><strong>Build</strong></a>
  ·
  <a href="https://github.com/Clayton630/QuartzNotch/issues"><strong>Report a bug</strong></a>
</p>

---

## The Idea

QuartzNotch turns the unused space around the MacBook notch into a compact, glanceable command center. It stays quiet when you do not need it, then expands into media controls, calendar events, quick actions, timers, lyrics, and Lock Screen experiences when you do.

It is built for people who want the notch to feel intentional instead of wasted.

## What It Does

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>Media, Without Opening an App</h3>
      <p>Control playback, scrub through tracks, adjust volume, show synced lyrics, and keep the current song visible from the notch or the Lock Screen.</p>
    </td>
    <td width="50%" valign="top">
      <h3>Live Activities for macOS</h3>
      <p>Show music, timers, Bluetooth, battery, focus, shelf, and other contextual activities directly around the notch.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>Calendar at a Glance</h3>
      <p>Swipe through days, check upcoming events, and keep your schedule accessible without opening Calendar.</p>
    </td>
    <td width="50%" valign="top">
      <h3>Quick Tools</h3>
      <p>Use file shelf, quick sharing, clipboard tools, timers, camera preview, customizable toolbar actions, and reorderable pages.</p>
    </td>
  </tr>
</table>

## Highlights in 0.4.1

<table>
  <tr>
    <td valign="top"><strong>Liquid Glass redesign</strong></td>
    <td valign="top">A deeper, more dimensional visual style with refined transparency, fallback rendering, and better readability.</td>
  </tr>
  <tr>
    <td valign="top"><strong>Lyrics everywhere</strong></td>
    <td valign="top">Apple Music-style lyrics on the Lock Screen and inline lyrics in the notch player.</td>
  </tr>
  <tr>
    <td valign="top"><strong>Inline volume</strong></td>
    <td valign="top">A quick volume slider integrated into the notch and Lock Screen players.</td>
  </tr>
  <tr>
    <td valign="top"><strong>Better calendar</strong></td>
    <td valign="top">Smoother full-module day swiping, improved event layout, and better edge handling.</td>
  </tr>
  <tr>
    <td valign="top"><strong>Localization</strong></td>
    <td valign="top">Expanded translations and an in-app language selector.</td>
  </tr>
  <tr>
    <td valign="top"><strong>Polish pass</strong></td>
    <td valign="top">Cleaner symbols, refined animations, clipping fixes, large-display fixes, Sparkle update fixes, and DMG packaging improvements.</td>
  </tr>
</table>

## Feature Map

- Compact notch interface with customizable pages
- Music controls, Now Playing state, lyrics, visualizer, and source badge controls
- Lock Screen player with fullscreen album artwork
- Lock Screen Live Activities for music and timers
- Calendar and reminder events inside the notch
- File shelf, quick sharing, clipboard utilities, quick timers, and camera preview
- Bluetooth, battery, focus, timer, shelf, and media Live Activities
- Liquid Glass appearance with fallback mode for unsupported or disabled environments
- Light/Dark adaptive app icon support
- Customizable toolbar and page order
- Sparkle-based updates

## Requirements

| Requirement | Details |
| --- | --- |
| macOS | macOS 14 or later |
| Hardware | Apple Silicon or Intel Mac |
| Build tools | Xcode 16 or later |

## Download

Download the latest DMG from GitHub Releases:

<p>
  <a href="https://github.com/Clayton630/QuartzNotch/releases/latest"><img alt="Download QuartzNotch" src="https://img.shields.io/badge/Download_latest_DMG-111111?style=for-the-badge&logo=github&logoColor=white"></a>
</p>

> [!IMPORTANT]
> Current public builds are not notarized with an Apple Developer ID. On first launch, macOS may block the app as coming from an unidentified developer. If you trust the build, open `System Settings > Privacy & Security` and choose `Open Anyway`.

## Build From Source

```bash
git clone https://github.com/Clayton630/QuartzNotch.git
cd QuartzNotch
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

<details>
<summary><strong>Release packaging</strong></summary>

Release builds are generated with the release script:

```bash
bash Configuration/release/make_release.sh \
  --version 0.4.1 \
  --build 1035 \
  --oss \
  --sparkle-account quartznotch_clayton
```

The script creates the app, packages it into a DMG, and prints the Sparkle appcast enclosure metadata.

</details>

<details>
<summary><strong>Repository structure</strong></summary>

```text
QuartzNotch/              Main macOS app source
QuartzNotchXPCHelper/     Helper service used by the app
QuartzNotchScreenSaver/   Screen saver / backdrop component
Configuration/            Release, DMG, and Sparkle tooling
mediaremote-adapter/      MediaRemote bridge used for media integration
updater/                  Sparkle appcast
.github/                  GitHub issue templates
```

</details>

## Contributing

Bug reports and feature requests are welcome through GitHub Issues. Please read `CONTRIBUTING.md` before opening an issue.

## License

QuartzNotch is distributed under the GNU General Public License v3.0. See `LICENSE` for the full license text. Attribution and third-party notices are available in `NOTICE.md` and `THIRD_PARTY_LICENSES`.
