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

## Building for a new kernel

After an Unraid OS upgrade the kernel changes, so a new release is needed:

1. Add the new kernel's `.config` under `kernel/<uname -r>/config`
   (copy it from the box: `/usr/src/linux-$(uname -r)/config`).
2. Run the **build-driver** workflow (Actions tab) with
   `kernel_version=<uname -r>`.
3. Reinstall / update the plugin on the box.

## Caveats

- **Host-only.** `wlan0` from this driver is a client interface. It **cannot**
  be bridged into Unraid's `br0` (an 802.11 station can't bridge multiple MACs),
  and Unraid's Network Settings GUI won't manage it. Configure it with
  `wpa_supplicant`. Docker/VM bridged networking will not ride over it.
- **Breaks on kernel upgrade** until a release exists for the new version.

## Install

Plugins → Install Plugin →
`https://github.com/elibosley/unraid-rtl8821au/raw/main/unraid-rtl8821au.plg`

## License

Build scripts/plugin: MIT. The driver itself is GPL-2.0 (see
[morrownr/8821au-20210708](https://github.com/morrownr/8821au-20210708)).
