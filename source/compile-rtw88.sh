#!/bin/bash
# Build the in-kernel rtw88 driver modules for the RTL8811AU/8821AU (+ 8812AU,
# 8814AU) that Unraid ships disabled (CONFIG_RTW88_8821AU is not set), bundle the
# matching firmware, and package both into a tarball the plugin extracts to /.
#
# rtw88 is a mac80211 driver, so WPA3-SAE / PMF work through the standard stack
# (proven on RTL8811AU: SAE association + DHCP on a 5 GHz WPA3 AP). The morrownr
# fullmac driver cannot do this reliably.
#
# We build only the chip + USB-glue + shared (rtw88_88xxa) modules; rtw88_core /
# rtw88_usb / mac80211 / cfg80211 are already present on the box.
#
# Inputs (env): KVER (required), REPO (default cwd), OUT (default $REPO/out)
set -euo pipefail

REPO="${REPO:-$(pwd)}"
KVER="${KVER:?set KVER, e.g. 6.18.33-Unraid}"
KBASE="${KVER%%-*}"; KMAJ="${KBASE%%.*}"
OUT="${OUT:-$REPO/out}"
WORK="$(mktemp -d)"; JOBS="$(nproc)"
CFG="$REPO/kernel/$KVER/config"
FW_BASE="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtw88"
[ -f "$CFG" ] || { echo "ERROR: missing pinned config $CFG"; exit 1; }

echo "::group::Fetch + prepare kernel tree ($KVER) with rtw88 A-series enabled"
cd "$WORK"
curl -fL --retry 3 -o k.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v${KMAJ}.x/linux-$KBASE.tar.xz"
tar xf k.tar.xz
KDIR="$WORK/linux-$KBASE"
cp "$CFG" "$KDIR/.config"
touch "$KDIR/.scmversion"
cd "$KDIR"
./scripts/config --file .config --disable LOCALVERSION_AUTO --set-str LOCALVERSION "-Unraid" \
  --module RTW88_8821AU --module RTW88_8812AU --module RTW88_8814AU
make -j"$JOBS" olddefconfig
make -j"$JOBS" modules_prepare
echo "::endgroup::"

echo "::group::Build rtw88 modules (explicit .ko targets; MODPOST_WARN since no Module.symvers)"
RTW=drivers/net/wireless/realtek/rtw88
make -j"$JOBS" KBUILD_MODPOST_WARN=1 \
  "$RTW/rtw88_88xxa.ko" \
  "$RTW/rtw88_8821a.ko" "$RTW/rtw88_8821au.ko" \
  "$RTW/rtw88_8812a.ko" "$RTW/rtw88_8812au.ko" \
  "$RTW/rtw88_8814a.ko" "$RTW/rtw88_8814au.ko"
echo "::endgroup::"

echo "::group::Stage modules + firmware into a tarball"
STAGE="$WORK/stage"
MODDIR="$STAGE/lib/modules/$KVER/kernel/drivers/net/wireless/realtek/rtw88"
FWDIR="$STAGE/lib/firmware/rtw88"
mkdir -p "$MODDIR" "$FWDIR"
for m in rtw88_88xxa rtw88_8821a rtw88_8821au rtw88_8812a rtw88_8812au rtw88_8814a rtw88_8814au; do
  f="$RTW/$m.ko"
  [ -f "$f" ] || { echo "ERROR: missing $m.ko"; exit 1; }
  vm="$(modinfo -F vermagic "$f")"
  case "$vm" in "$KVER SMP preempt mod_unload"*) : ;; *) echo "VERMAGIC MISMATCH $m: $vm"; exit 1;; esac
  cp "$f" "$MODDIR/"
done
# Firmware (kernel-independent). rtw8821a covers 8811au/8821au; others for breadth.
for fw in rtw8821a_fw.bin rtw8812a_fw.bin rtw8814a_fw.bin; do
  if curl -fsSL --retry 3 -o "$FWDIR/$fw" "$FW_BASE/$fw"; then echo "fw $fw $(stat -c%s "$FWDIR/$fw")B"; else
    echo "WARN: firmware $fw not fetched"; rm -f "$FWDIR/$fw"; fi
done
[ -f "$FWDIR/rtw8821a_fw.bin" ] || { echo "ERROR: rtw8821a_fw.bin is required and was not fetched"; exit 1; }
echo "::endgroup::"

mkdir -p "$OUT"
tar -czf "$OUT/rtw88-$KVER.tar.gz" -C "$STAGE" lib
( cd "$OUT" && md5sum "rtw88-$KVER.tar.gz" | awk '{print $1}' > "rtw88-$KVER.tar.gz.md5" )
echo "rtw88_8821au device ids: $(modinfo -F alias "$RTW/rtw88_8821au.ko" | grep -ci p011E) match(es) for 2357:011e"
echo "packaged: $OUT/rtw88-$KVER.tar.gz"
tar -tzf "$OUT/rtw88-$KVER.tar.gz" | sed 's/^/  /'
rm -rf "$WORK"
