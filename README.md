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

## Supported hardware

Three chipset families (the driver binds by USB ID — 74 IDs total):

| Chipset | Class | Example adapters |
|---|---|---|
| **RTL8811AU / RTL8821AU** | AC600 | TP-Link Archer T2U Nano / T2U Plus / T2U v3, D-Link DWA-171, Edimax EW-7811UAC/UTC, Netgear A6100, ASUS USB-AC51 |
| **RTL8812AU** | AC1200 | TP-Link Archer T4U / T4UH, ASUS USB-AC56, Alfa AWUS036AC / AWUS036ACH, D-Link DWA-182, Netgear A6210, Edimax EW-7822UAC, Tenda U12 |
| **RTL8814AU** | AC1900 | TP-Link Archer T9UH, ASUS USB-AC68, Alfa AWUS1900, D-Link DWA-192, Netgear A7000 |

Full USB `vendor:product` IDs (what each module claims):

- **RTL8811AU/8821AU** (`rtw88_8821au`): `0411:0242 0411:029b 04bb:0953 056e:4007 056e:400e 056e:400f 0846:9052 0bda:0811 0bda:0820 0bda:0821 0bda:0823 0bda:8822 0bda:a811 0e66:0023 2001:3314 2001:3318 2019:ab32 20f4:804b 2357:011e 2357:011f 2357:0120 3823:6249 7392:a811 7392:a812 7392:a813 7392:b611`
- **RTL8812AU** (`rtw88_8812au`): `0409:0408 0411:025d 04bb:0952 050d:1106 050d:1109 0586:3426 0789:016e 07b8:8812 0846:9051 0b05:17d2 0bda:8812 0bda:881a 0bda:881b 0bda:881c 0df6:0074 0e66:0022 1058:0632 13b1:003f 148f:9097 1740:0100 2001:330e 2001:3313 2001:3315 2001:3316 2019:ab30 20f4:805b 2357:0101 2357:0103 2357:010d 2357:010e 2357:010f 2357:0122 2604:0012 7392:a822`
- **RTL8814AU** (`rtw88_8814au`): `056e:400b 056e:400d 0846:9054 0b05:1817 0b05:1852 0b05:1853 0bda:8813 0e66:0026 2001:331a 20f4:809a 20f4:809b 2357:0106 7392:a833 7392:a834`

> Not sure which chipset your adapter has? Run `lsusb` and match the
> `vendor:product` ID against the lists above.

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
