#!/bin/bash
# Build the morrownr 8821au out-of-tree driver (RTL8811AU / RTL8821AU) against a
# specific Unraid kernel, producing a loadable 8821au.ko.
#
# Why this works without rebuilding the whole kernel:
#   - Unraid kernels are built with CONFIG_MODVERSIONS off, RANDSTRUCT_NONE,
#     TRIM_UNUSED_KSYMS off and no forced module signing. So an external module
#     only needs a vermagic match (kernel release + SMP/preempt/mod_unload),
#     which we get from `make modules_prepare` against the vanilla source + the
#     exact Unraid .config.
#
# Inputs (env):
#   KVER   full Unraid kernel release, e.g. 6.18.33-Unraid   (required)
#   REPO   path to this repo checkout                         (default: cwd)
#   DRIVER_REF  git ref of the morrownr driver to build       (default: main)
#   OUT    directory to drop the built 8821au.ko into         (default: $REPO/out)
set -euo pipefail

REPO="${REPO:-$(pwd)}"
KVER="${KVER:?set KVER to the target Unraid kernel release, e.g. 6.18.33-Unraid}"
KBASE="${KVER%%-*}"                       # 6.18.33-Unraid -> 6.18.33
KMAJ="${KBASE%%.*}"                        # 6
DRIVER_REF="${DRIVER_REF:-main}"
OUT="${OUT:-$REPO/out}"
WORK="$(mktemp -d)"
JOBS="$(nproc)"

CFG="$REPO/kernel/$KVER/config"
[ -f "$CFG" ] || { echo "ERROR: missing pinned kernel config: $CFG"; exit 1; }

echo "::group::Fetch vanilla kernel source linux-$KBASE"
cd "$WORK"
curl -fL --retry 3 -o "linux-$KBASE.tar.xz" \
  "https://cdn.kernel.org/pub/linux/kernel/v${KMAJ}.x/linux-$KBASE.tar.xz"
tar xf "linux-$KBASE.tar.xz"
KDIR="$WORK/linux-$KBASE"
echo "::endgroup::"

echo "::group::Prepare kernel tree with Unraid config ($KVER)"
cp "$CFG" "$KDIR/.config"
# Pin the version string exactly to the Unraid release: no scm "+" suffix,
# LOCALVERSION="-Unraid", LOCALVERSION_AUTO off.
touch "$KDIR/.scmversion"
( cd "$KDIR"
  ./scripts/config --file .config --disable LOCALVERSION_AUTO --set-str LOCALVERSION "-Unraid"
  make -j"$JOBS" olddefconfig
  make -j"$JOBS" modules_prepare
  REL="$(cat include/config/kernel.release)"
  echo "prepared kernel.release = $REL"
  [ "$REL" = "$KVER" ] || { echo "ERROR: kernel.release '$REL' != target '$KVER'"; exit 1; }
)
echo "::endgroup::"

echo "::group::Clone + build morrownr 8821au ($DRIVER_REF)"
cd "$WORK"
git clone --depth 1 --branch "$DRIVER_REF" https://github.com/morrownr/8821au-20210708 driver \
  || git clone --depth 1 https://github.com/morrownr/8821au-20210708 driver
DRV_SHA="$(git -C driver rev-parse HEAD)"
make -j"$JOBS" -C driver KVER="$KVER" KSRC="$KDIR" modules
echo "::endgroup::"

echo "::group::Verify vermagic"
KO="$WORK/driver/8821au.ko"
[ -f "$KO" ] || { echo "ERROR: 8821au.ko not produced"; exit 1; }
VM="$(modinfo -F vermagic "$KO")"
echo "built vermagic: $VM"
case "$VM" in
  "$KVER SMP preempt mod_unload"*) echo "vermagic OK" ;;
  *) echo "ERROR: vermagic mismatch (expected '$KVER SMP preempt mod_unload')"; exit 1 ;;
esac
modinfo -F alias "$KO" | grep -qi "v2357p011E" && echo "device 2357:011e present in id table"
echo "::endgroup::"

mkdir -p "$OUT"
cp "$KO" "$OUT/8821au.ko"
md5sum "$OUT/8821au.ko" | awk '{print $1}' > "$OUT/8821au.ko.md5"
echo "$DRV_SHA" > "$OUT/driver.sha"
echo "Built $OUT/8821au.ko (driver $DRV_SHA) for $KVER"
rm -rf "$WORK"
