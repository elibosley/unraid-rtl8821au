# unraid-rtl8821au

Out-of-tree **RTL8811AU / RTL8821AU** USB WiFi driver (morrownr
[`8821au`](https://github.com/morrownr/8821au-20210708)) packaged for **Unraid**.

These chipsets — e.g. the **TP-Link Archer T2U Nano (`2357:011e`)** — have **no
in-kernel driver** on Unraid. The in-kernel `rtw88` USB drivers only cover the
newer C/B-generation parts (`8821cu`, `8822bu`, `8822cu`), not the `8821a`
silicon. This repo builds the matching module and installs it via a plugin.

## How it works

Modeled on ich777's Unraid driver plugins:

1. **CI build** (`.github/workflows/build.yml`) compiles `8821au.ko`
   against a specific Unraid kernel and publishes it as a **GitHub release whose
   tag is the exact kernel release** (e.g. `6.18.33-Unraid`).
2. **Plugin** (`rtl8821au.plg`) runs on the Unraid box, downloads the `.ko` for
   the running `uname -r`, caches it on the flash, installs it into the module
   tree and `modprobe`s it — on install and on every boot.

The build works without rebuilding the whole kernel because Unraid kernels set
`# CONFIG_MODVERSIONS is not set`, `CONFIG_RANDSTRUCT_NONE=y`,
`# CONFIG_TRIM_UNUSED_KSYMS is not set`, and don't force module signing. So a
`make modules_prepare` against the vanilla kernel source + the exact Unraid
`.config` yields a module whose *vermagic* matches the running kernel
(`<kver> SMP preempt mod_unload`). The pinned per-kernel `.config` lives under
[`kernel/`](kernel/).

## Self-updating builds

The **build-driver** workflow runs **daily on a schedule** and keeps releases in
sync with Unraid automatically:

1. It reads the official release feed (`https://releases.unraid.net/json`) and
   resolves the latest stable Unraid version.
2. It recovers that build's exact kernel `.config` and kernel release string by
   downloading the release zip and extracting just `src/` from `bzmodules`
   (the squashfs mounted at `/usr` on a live system) — no access to a running
   box required. The recovered config is committed under `kernel/<kver>/` for
   provenance.
3. If a release for that kernel already exists, it no-ops. Otherwise it builds
   `8821au.ko` and publishes a release tagged with the kernel version.

So when Unraid ships an OS update with a new kernel, a matching driver release
appears automatically (within ~24h). On the box, the plugin then pulls the `.ko`
for the running `uname -r` on its next boot/reinstall.

### Manual / on-demand builds

From the Actions tab → **build-driver** → *Run workflow*:

- `unraid_version`: `latest` (default) or a specific version like `7.3.1`.
- `kernel_version`: build an exact `uname -r` from an already-committed config
  (overrides `unraid_version`).
- `force`: rebuild/republish even if the release already exists.

> Timing note: if you update the box to a brand-new kernel *before* the daily
> build has published for it, the plugin will report no release yet — trigger
> the workflow manually (or wait for the next run), then reinstall the plugin.

## Connecting to a network

This plugin is **driver-only**. Once `wlan0` exists, configure the connection in
**Settings → Network Settings** — Unraid 7.x manages wifi natively (`rc.wireless`
+ `/boot/config/wireless.cfg`, starting its own `wpa_supplicant` and `dhcpcd`).
Don't run a second `wpa_supplicant` against `wlan0` or it will fight Unraid's.

Two things to get right in the GUI:

- **Set your Country/Region.** With the regulatory domain unset (`country 00`),
  5 GHz channels are `no-IR` (scan-only) and association silently fails. Setting
  the region unlocks them.
- **WPA3-SAE is unreliable on this chipset.** The RTL8811AU/8821AU fullmac driver
  often fails to associate to WPA3-Personal (SAE / PMF-required) APs. Prefer a
  WPA2-PSK SSID, or set the AP to WPA2/WPA3 mixed mode.

## Caveats

- **Host-only.** `wlan0` is a client interface. Unraid's Network Settings GUI
  *does* manage its association (SSID/passphrase/DHCP), but it **cannot** be
  bridged into `br0` — an 802.11 station can't bridge multiple MACs — so
  Docker/VM bridged networking will not ride over it.
- **Breaks on kernel upgrade** until a release exists for the new version.

## Install

Plugins → Install Plugin →
`https://github.com/elibosley/unraid-rtl8821au/raw/main/unraid-rtl8821au.plg`

## License

Build scripts/plugin: MIT. The driver itself is GPL-2.0 (see
[morrownr/8821au-20210708](https://github.com/morrownr/8821au-20210708)).
