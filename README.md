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
  <a href="https://github.com/Clayton630/QuartzNotch/releases/download/v0.4.1/QuartzNotch-0.4.1.1035.dmg">
    <img alt="Download QuartzNotch for macOS" src="https://img.shields.io/badge/Download_QuartzNotch_for_macOS-000000?style=for-the-badge&logo=apple&logoColor=white&labelColor=FF3B30&color=111111">
  </a>
</p>

---

## Make the notch useful

QuartzNotch transforms the MacBook notch into a compact command center for the things you check and control all day. It brings your media, calendar, timers, quick tools, Live Activities, and Lock Screen controls into one interface that feels native to the Mac instead of sitting in another window.

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>Media that stays within reach</h3>
      <p>Control playback, scrub through tracks, adjust volume, follow lyrics, hide the source badge when you want a cleaner look, and keep Now Playing visible without opening your music app.</p>
    </td>
    <td width="50%" valign="top">
      <h3>Lock Screen experiences</h3>
      <p>Show a refined Lock Screen player, fullscreen album artwork, Apple Music-style lyrics, and Live Activities for music and timers directly where they make sense.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>Live Activities for macOS</h3>
      <p>Bring music, timers, Bluetooth, battery, focus, shelf, and media states into the notch with custom animations and a layout designed for quick glances.</p>
    </td>
    <td width="50%" valign="top">
      <h3>Calendar without opening Calendar</h3>
      <p>Swipe through days, check events and reminders, and keep your schedule visible inside the notch with a redesigned calendar module.</p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>Tools for small actions</h3>
      <p>Use quick timers, file shelf, quick sharing, clipboard utilities, camera preview, customizable toolbar actions, and reorderable pages from one compact surface.</p>
    </td>
    <td width="50%" valign="top">
      <h3>Built to feel visual</h3>
      <p>QuartzNotch includes a Liquid Glass-inspired appearance, fallback rendering, adaptive app icons, custom symbols, localization, and refined animations across the app.</p>
    </td>
  </tr>
</table>

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

## Contributing

Bug reports and feature requests are welcome through GitHub Issues. Please read `CONTRIBUTING.md` before opening an issue.

## License

QuartzNotch is distributed under the GNU General Public License v3.0. See `LICENSE` for the full license text. Attribution and third-party notices are available in `NOTICE.md` and `THIRD_PARTY_LICENSES`.
