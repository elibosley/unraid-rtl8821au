#!/bin/bash
# Build the in-kernel rtw88 driver modules for the RTL8811AU/8821AU (and 8812AU)
# that Unraid ships disabled (CONFIG_RTW88_8821AU is not set).
#
# rtw88 is a mac80211 driver, so WPA3-SAE / PMF works through the standard stack
# (unlike the morrownr fullmac driver). We only build the chip + USB-glue modules;
# rtw88_core / rtw88_usb / mac80211 / cfg80211 are already present on the box.
#
# Inputs (env): KVER (required), REPO (default cwd), OUT (default $REPO/out-rtw88)
set -euo pipefail

REPO="${REPO:-$(pwd)}"
KVER="${KVER:?set KVER, e.g. 6.18.33-Unraid}"
KBASE="${KVER%%-*}"; KMAJ="${KBASE%%.*}"
OUT="${OUT:-$REPO/out-rtw88}"
WORK="$(mktemp -d)"; JOBS="$(nproc)"
CFG="$REPO/kernel/$KVER/config"
[ -f "$CFG" ] || { echo "ERROR: missing pinned config $CFG"; exit 1; }

echo "::group::Fetch + prepare kernel tree ($KVER) with rtw88 A-series enabled"
cd "$WORK"
curl -fL --retry 3 -o k.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v${KMAJ}.x/linux-$KBASE.tar.xz"
tar xf k.tar.xz
KDIR="$WORK/linux-$KBASE"
cp "$CFG" "$KDIR/.config"
touch "$KDIR/.scmversion"
cd "$KDIR"
# Enable the A-series chip + USB modules Unraid left off.
./scripts/config --file .config --disable LOCALVERSION_AUTO --set-str LOCALVERSION "-Unraid" \
  --module RTW88_8821AU --module RTW88_8812AU --module RTW88_8814AU
make -j"$JOBS" olddefconfig
make -j"$JOBS" modules_prepare
echo "::endgroup::"

echo "::group::Build rtw88 chip + USB modules (+ shared rtw88_88xxa)"
# Module.symvers is absent after modules_prepare; with MODVERSIONS off the inter-
# module symbols (rtw88_core/usb, mac80211, and the shared rtw88_88xxa) resolve by
# name at load time, so let modpost warn instead of error. Explicit .ko targets
# (a bare dir target only compiles .o, it doesn't run modpost to produce .ko).
# rtw88_88xxa provides the rtw88xxa_* symbols that rtw88_8821a/8812a/8814a need.
RTW=drivers/net/wireless/realtek/rtw88
make -j"$JOBS" KBUILD_MODPOST_WARN=1 \
  "$RTW/rtw88_88xxa.ko" \
  "$RTW/rtw88_8821a.ko" "$RTW/rtw88_8821au.ko" \
  "$RTW/rtw88_8812a.ko" "$RTW/rtw88_8812au.ko" \
  "$RTW/rtw88_8814a.ko" "$RTW/rtw88_8814au.ko"
echo "::endgroup::"

mkdir -p "$OUT"
got=0
# Ship the A-series chip/USB modules plus the shared rtw88_88xxa they depend on.
# (rtw88_core / rtw88_usb / mac80211 / cfg80211 are already present on the box.)
for m in rtw88_88xxa rtw88_8821a rtw88_8821au rtw88_8812a rtw88_8812au rtw88_8814a rtw88_8814au; do
  f="$RTW/$m.ko"
  if [ -f "$f" ]; then
    vm="$(modinfo -F vermagic "$f")"
    case "$vm" in
      "$KVER SMP preempt mod_unload"*) cp "$f" "$OUT/"; echo "OK  $m  ($vm)"; got=$((got+1));;
      *) echo "VERMAGIC MISMATCH $m: $vm"; exit 1;;
    esac
  fi
done
[ "$got" -ge 2 ] || { echo "ERROR: expected at least rtw88_8821a + rtw88_8821au"; exit 1; }
modinfo -F alias "$OUT/rtw88_8821au.ko" | grep -qi "p011E" && echo "device 2357:011e present in rtw88_8821au"
ls -la "$OUT"
rm -rf "$WORK"
