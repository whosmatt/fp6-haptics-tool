#!/bin/bash
# Install a hapkit project on a userdebug test device so the framework uses it until removed (survives reboots):
#   haptic_ram.bin  -> /vendor/firmware (adb remount overlay)
#   haptic.ko       -> /vendor/etc/hapkit, built from HAPKIT_KDIR with the project's effect table
#   boot hook       -> /system/etc/init/hapkit.rc + /system/etc/hapkit/swap.sh: swaps the module in post-fs-data,
#                      before the vibrator HAL starts
# usage: tools/devinstall.sh [project]          install and reboot
#        tools/devinstall.sh --remove           delete everything above and reboot (back to stock)
# Settings (environment, or KEY=VALUE lines in hapkit.local.env; see hapkit.local.env.example):
#   HAPKIT_SERIAL  ro.serialno of the test device (required)
#   HAPKIT_ADB     adb binary (default: adb or adb.exe on PATH)
#   HAPKIT_KDIR    kernel source with the haptic_hv primitives series; its driver is copied, the aw_ff_effects
#                  table replaced by the project's and built out of tree (HAPKIT_KDIR stays clean)
#   HAPKIT_KMAKE   command that runs make for the device's kernel (prepared build tree: modules_prepare done,
#                  Module.symvers present); called as "$HAPKIT_KMAKE M=<dir> modules"
#   HAPKIT_STRIP   llvm-strip binary (default: llvm-strip on PATH)
# The device needs root (adb root) and a working adb remount (verity disabled).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$HERE/hapkit.local.env" ]; then
    while IFS='=' read -r k v; do
        case "$k" in ''|\#*) continue ;; esac
        [ -n "${!k:-}" ] || export "$k=$v"
    done < "$HERE/hapkit.local.env"
fi
ADB=${HAPKIT_ADB:-$(command -v adb || command -v adb.exe || true)}
SERIAL=${HAPKIT_SERIAL:?set HAPKIT_SERIAL to the ro.serialno of the test device}
for f in ${HAPKIT_FORBID//,/ }; do [ "$SERIAL" != "$f" ] || { echo "refusing $SERIAL (HAPKIT_FORBID)"; exit 1; }; done
[ -n "$ADB" ] || { echo "adb not found (set HAPKIT_ADB)"; exit 1; }
A=("$ADB" -s "$SERIAL")
sh() { "${A[@]}" shell "$@" | tr -d '\r'; }
hostpath() { case "$ADB" in *.exe) wslpath -w "$1" ;; *) echo "$1" ;; esac; }
push() { "${A[@]}" push "$(hostpath "$1")" "$2" >/dev/null; }

[ "$(sh getprop ro.serialno)" = "$SERIAL" ] || { echo "device $SERIAL not attached"; exit 1; }
"${A[@]}" root >/dev/null; sleep 2
"${A[@]}" remount >/dev/null

if [ "${1:-}" = "--remove" ]; then
    sh 'rm -rf /system/etc/init/hapkit.rc /system/etc/hapkit /vendor/etc/hapkit /vendor/firmware/haptic_ram.bin'
    echo "removed; rebooting"; "${A[@]}" reboot; exit 0
fi

PROJECT=${1:-$HERE/projects/fp6.hapkit.json}
KDIR=${HAPKIT_KDIR:?set HAPKIT_KDIR to the kernel source with the haptic_hv series}
KMAKE=${HAPKIT_KMAKE:?set HAPKIT_KMAKE to a command that runs make for the device kernel}
STRIP=${HAPKIT_STRIP:-llvm-strip}
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
cp -r "$KDIR/drivers/misc/haptic_hv" "$OUT/haptic_hv"
rm -f "$OUT"/haptic_hv/*.o "$OUT"/haptic_hv/*.ko "$OUT"/haptic_hv/.*.cmd
PYTHONPATH="$HERE" python3 - "$PROJECT" "$OUT" <<'EOF'
import sys
from hapkit.core import exports, project as proj
p = proj.load(sys.argv[1])
blob, rep = exports.export_ram_bin(p, upstream=True)
open(f"{sys.argv[2]}/haptic_ram.bin", "wb").write(blob)
table = exports.export_kernel_table(p, upstream=True)
rows = table[table.index("static const struct aw_ff_effect aw_ff_effects[]"):]
cp = f"{sys.argv[2]}/haptic_hv/haptic_hv.c"
src = open(cp, newline="").read().replace("\r\n", "\n")
a = src.index("static const struct aw_ff_effect aw_ff_effects[]")
b = src.index("\n};\n", a) + 4
open(cp, "w", newline="\r\n").write(src[:a] + rows + src[b:])
print(f"{p['name']}: haptic_ram.bin {rep['sha256'][:12]} ({rep['file_bytes']} B)")
EOF

$KMAKE M="$OUT/haptic_hv" modules 2>&1 | grep -E "warning|error" && exit 1 || true
"$STRIP" --strip-debug -o "$OUT/haptic.ko" "$OUT/haptic_hv/haptic.ko"

cat > "$OUT/hapkit.rc" <<'EOF'
# hapkit test setup (adb remount overlay; userdebug only). Swaps haptic.ko for /vendor/etc/hapkit/haptic.ko
# before the vibrator HAL starts (class hal). Back to stock: hapkit tools/devinstall.sh --remove.
on post-fs-data
    exec u:r:su:s0 root root -- /system/bin/sh /system/etc/hapkit/swap.sh
EOF
cat > "$OUT/swap.sh" <<'EOF'
#!/system/bin/sh
# hapkit: replace the stock haptic.ko with /vendor/etc/hapkit/haptic.ko (see /system/etc/init/hapkit.rc)
ko=/vendor/etc/hapkit/haptic.ko
[ -f "$ko" ] || exit 0
if grep -q '^haptic ' /proc/modules; then
    rmmod haptic || { log -p e -t hapkit "rmmod haptic failed"; exit 1; }
fi
insmod "$ko" || { log -p e -t hapkit "insmod $ko failed"; exit 1; }
# the QTI vibrator HAL (user system) opens primitive_duration O_RDWR
n=/sys/class/qcom-haptics/primitive_duration
for i in 1 2 3 4 5 6 7 8 9 10; do [ -e $n ] && break; sleep 0.1; done
chown system:system $n && chmod 0664 $n
log -t hapkit "haptic.ko swapped ($(sha256sum "$ko" | cut -c1-12)), ram $(sha256sum /vendor/firmware/haptic_ram.bin | cut -c1-12)"
EOF

sh 'mkdir -p /vendor/etc/hapkit /system/etc/hapkit'
push "$OUT/haptic.ko" /vendor/etc/hapkit/haptic.ko
push "$OUT/haptic_ram.bin" /vendor/firmware/haptic_ram.bin
push "$OUT/hapkit.rc" /system/etc/init/hapkit.rc
push "$OUT/swap.sh" /system/etc/hapkit/swap.sh
sh 'chmod 644 /vendor/etc/hapkit/haptic.ko /vendor/firmware/haptic_ram.bin /system/etc/init/hapkit.rc;
    chmod 755 /system/etc/hapkit/swap.sh;
    restorecon -R /vendor/etc/hapkit /vendor/firmware/haptic_ram.bin /system/etc/hapkit /system/etc/init/hapkit.rc 2>/dev/null' >/dev/null
echo "installed; rebooting"
"${A[@]}" reboot
