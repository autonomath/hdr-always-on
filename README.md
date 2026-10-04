# hdr-always-on

Keep HDR enabled on your external displays. Runs silently in the background on macOS.

## The problem

macOS often disables HDR on external displays after sleep, unlock, or display reconnection. There's no built-in way to keep it on -- the only option is manually toggling it in System Settings > Displays every time.

## How it works

Uses the macOS `CoreDisplay` private API to check and enable HDR on all connected external displays. No UI interaction, no dependencies beyond Python 3 (included with macOS).

Runs at login and every 15 minutes via launchd. When HDR is already on, the check takes milliseconds.

## Install

### Option 1: One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/autonomath/hdr-always-on/main/install.sh | bash
```

### Option 2: Download the .pkg installer

Download the latest `.pkg` from the [Releases](https://github.com/autonomath/hdr-always-on/releases) page and double-click to install. No Terminal required.

### Option 3: Git clone

```bash
git clone https://github.com/autonomath/hdr-always-on.git
cd hdr-always-on
bash install.sh
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/autonomath/hdr-always-on/main/uninstall.sh | bash
```

## Run manually

```bash
bash ~/.local/bin/enable-hdr.sh
```

## Technical details

The script calls two private CoreDisplay framework functions:

- `CoreDisplay_Display_IsHDRModeEnabled(displayID)` -- check if HDR is on
- `CoreDisplay_Display_SetHDRModeEnabled(displayID, true)` -- turn it on

It enumerates all online displays via `CGGetOnlineDisplayList`, skips built-in displays, and enables HDR on every external display that supports it. Displays that don't support HDR are silently skipped (the API returns a non-zero error code).

## Compatibility

- **macOS**: Tested on Sequoia 15.x (Apple Silicon). May work on earlier versions.
- **Displays**: Any external display with HDR support (LG, Samsung, Dell, Sony, etc.). The script is display-agnostic.
- **Apple Silicon & Intel**: Uses standard CoreGraphics/CoreDisplay frameworks available on both.

## Caveats

- Uses a **private API** that Apple could change or remove in future macOS updates.
- The launchd job runs every 15 minutes on the clock (:00, :15, :30, :45). You can edit the plist to change the interval.

## Logs

```bash
tail -f /tmp/enable-hdr.log
```

## License

MIT
