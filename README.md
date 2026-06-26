# unraid-rtl8821au

In-kernel **`rtw88`** (mac80211) USB WiFi driver for the Realtek **RTL8811AU /
RTL8821AU / RTL8812AU / RTL8814AU** chipsets, packaged for **Unraid**.

Mainline Linux has an `rtw88` driver for these A-series chips (e.g. the **TP-Link
Archer T2U Nano `2357:011e`**), but **Unraid ships it disabled**
(`# CONFIG_RTW88_8821AU is not set`) and without the firmware. This repo compiles
those modules against each Unraid kernel, bundles the firmware, and installs both
via a plugin.

Because `rtw88` is a **mac80211** driver, **WPA3-SAE / PMF work** — verified on
RTL8811AU (SAE association + DHCP on a 5 GHz WPA3 AP). The older out-of-tree
*fullmac* drivers (e.g. morrownr `8821au`) reach `ASSOCIATING` and then fail on
SAE; that's why this project uses `rtw88` instead.

## How it works

Modeled on ich777's Unraid driver plugins:

1. **CI build** (`.github/workflows/build.yml`) enables `CONFIG_RTW88_8821AU/
   8812AU/8814AU`, compiles the chip + USB-glue + shared (`rtw88_88xxa`) modules
   against a specific Unraid kernel, fetches the matching firmware from
   linux-firmware, and publishes a tarball as a **GitHub release tagged with the
   exact kernel release** (e.g. `6.18.33-Unraid`).
2. **Plugin** (`unraid-rtl8821au.plg`) runs on the box, downloads the bundle for
   the running `uname -r`, caches it on the flash, extracts modules → `/lib/modules`
   and firmware → `/lib/firmware/rtw88`, `depmod`s, and loads the module — on
   install and every boot. `rtw88_core`/`rtw88_usb`/`mac80211`/`cfg80211` are
   already present on the box.

The build works without rebuilding the whole kernel because Unraid kernels set
`# CONFIG_MODVERSIONS is not set`, `CONFIG_RANDSTRUCT_NONE=y`,
`# CONFIG_TRIM_UNUSED_KSYMS is not set`, and don't force module signing. So
`make modules_prepare` against the vanilla kernel source + the exact Unraid
`.config` yields modules whose *vermagic* matches the running kernel
(`<kver> SMP preempt mod_unload`). The inter-module symbols resolve by name at
load time (`KBUILD_MODPOST_WARN=1`). The pinned per-kernel `.config` lives under
[`kernel/`](kernel/).

## Self-updating builds

The **build-driver** workflow runs **daily on a schedule** and keeps releases in
sync with Unraid automatically:

1. It reads the official release feed (`https://releases.unraid.net/json`) and
   resolves the latest stable Unraid version.
2. It recovers that build's exact kernel `.config` and kernel release string by
   downloading the release zip and extracting just `src/` from `bzmodules` (the
   squashfs mounted at `/usr` on a live system) — no access to a running box
   required. The recovered config is committed under `kernel/<kver>/`.
3. If a release for that kernel already exists, it no-ops. Otherwise it builds the
   bundle and publishes a release tagged with the kernel version.

So when Unraid ships an OS update with a new kernel, a matching driver release
appears automatically (within ~24h). The plugin pulls it on its next boot/reinstall.

### Manual / on-demand builds

Actions tab → **build-driver** → *Run workflow*:

- `unraid_version`: `latest` (default) or a specific version like `7.3.1`.
- `kernel_version`: build an exact `uname -r` from an already-committed config.
- `force`: rebuild/republish even if the release already exists.

> Timing note: if you update the box to a brand-new kernel *before* the daily
> build has published for it, the plugin reports no release yet — run the workflow
> manually (or wait for the next run), then reinstall the plugin.

## Connecting to a network

Driver-only: once `wlan0` exists, configure WiFi in **Settings → Network
Settings**. Unraid 7.x manages association/DHCP natively (`rc.wireless` +
`/boot/config/wireless.cfg`, its own `wpa_supplicant`). Don't run a second
`wpa_supplicant` against `wlan0`.

- **Set your Country/Region** in the GUI, or the regulatory domain stays
  `country 00` and 5 GHz channels are `no-IR` (scan-only) → association silently
  fails.
- **WPA3-SAE works** with this `rtw88` driver (5 GHz WPA3 verified).

## Caveats

- **Host-only.** Unraid's GUI manages association, but `wlan0` **cannot** be
  bridged into `br0` (an 802.11 station can't bridge multiple MACs), so Docker/VM
  bridged networking won't ride over it.
- **Breaks on kernel upgrade** until a release exists for the new version (the
  daily build handles this automatically within ~24h).

## Install

Plugins → Install Plugin →
`https://github.com/elibosley/unraid-rtl8821au/raw/main/unraid-rtl8821au.plg`

## License

Build scripts/plugin: MIT. The `rtw88` driver and firmware are from the Linux
kernel / linux-firmware (GPL-2.0 / respective firmware licenses).
