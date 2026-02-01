#!/bin/bash
#
# mkbuildimg.sh - Create a bootable MS-DOS 6 build environment disk image
#
# Produces a bootable FAT16 hard disk image containing the full source tree
# at C:\ASTRO, ready to run BUILDALL.BAT. Intended for use with v86 or other
# emulators.
#
# Strategy:
#   1. mkfatimage16 creates the dosemu HD image
#   2. dosemu boots and runs SYS to write boot sector + system files
#   3. mtools copies the source tree and config files onto the image
#   4. 128-byte dosemu header is stripped for a raw image usable by v86/qemu

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SIZE_MB=250
OUTPUT="dos6-build.img"

usage() {
    cat <<EOF
Usage: $(basename "$0") [-o output.img] [--size SIZE_MB]

Creates a bootable hard disk image with the full MS-DOS 6 source tree
at C:\ASTRO, ready to build with BUILDALL.BAT.

Options:
  -o FILE        Output image file (default: $OUTPUT)
  --size SIZE    Disk size in MB (default: $SIZE_MB)
  -h, --help     Show this help

Requires: dosemu2, mtools, mkfatimage16
EOF
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -o)       OUTPUT="$2"; shift 2 ;;
        --size)   SIZE_MB="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

SIZE_KB=$(( SIZE_MB * 1024 ))

for cmd in dosemu mkfatimage16 mcopy mmd; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd not found." >&2
        exit 1
    fi
done

# Locate DOS system files (same logic as mak.sh)
IO_SYS="$SCRIPT_DIR/bios/io.sys"
MSDOS_SYS="$SCRIPT_DIR/dos/msdos.sys"
COMMAND_COM="$SCRIPT_DIR/cmd/command/command.com"

if [[ ! -f "$IO_SYS" ]] || [[ ! -f "$MSDOS_SYS" ]] || [[ ! -f "$COMMAND_COM" ]]; then
    if [[ -f "$SCRIPT_DIR/bootstrap/IO.SYS" ]]; then
        IO_SYS="$SCRIPT_DIR/bootstrap/IO.SYS"
        MSDOS_SYS="$SCRIPT_DIR/bootstrap/MSDOS.SYS"
        COMMAND_COM="$SCRIPT_DIR/bootstrap/COMMAND.COM"
        echo "Using bootstrap DOS files..."
    else
        echo "ERROR: No DOS system files found." >&2
        echo "Run the build first, or provide bootstrap files." >&2
        exit 1
    fi
fi

echo "Creating ${SIZE_MB}MB build environment image..."
echo "  Output: $OUTPUT"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- Phase 1: Create and make bootable ---

echo "Creating disk image..."
mkfatimage16 -l MSDOS6 -k "$SIZE_KB" -f "$TMPDIR/hd.img" -p

# Patch partition to active/bootable
printf '\x80' | dd of="$TMPDIR/hd.img" bs=1 seek=574 count=1 conv=notrunc 2>/dev/null

# Find partition offset (128-byte dosemu header + partition start)
dd if="$TMPDIR/hd.img" bs=128 skip=1 of="$TMPDIR/raw.img" 2>/dev/null
PART_START_SECTOR=$(fdisk -l "$TMPDIR/raw.img" 2>/dev/null \
    | grep "${TMPDIR}/raw.img1" | awk '{if ($2 == "*") print $3; else print $2}')
rm -f "$TMPDIR/raw.img"
MTOOLS_OFFSET=$(( 128 + PART_START_SECTOR * 512 ))
echo "  Partition at sector $PART_START_SECTOR (mtools offset: $MTOOLS_OFFSET)"

# Staging dir for dosemu boot — just needs system files + SYS.COM
STAGING="$TMPDIR/staging"
mkdir -p "$STAGING/DOS"
cp "$IO_SYS" "$STAGING/IO.SYS"
cp "$MSDOS_SYS" "$STAGING/MSDOS.SYS"
cp "$COMMAND_COM" "$STAGING/COMMAND.COM"

# Need SYS.COM to transfer system to target drive
if [ -f "$SCRIPT_DIR/binaries/sys.com" ]; then
    cp "$SCRIPT_DIR/binaries/sys.com" "$STAGING/DOS/SYS.COM"
elif [ -f "$SCRIPT_DIR/cmd/sys/sys.com" ]; then
    cp "$SCRIPT_DIR/cmd/sys/sys.com" "$STAGING/DOS/SYS.COM"
elif [ -f "$SCRIPT_DIR/bootstrap/SYS.COM" ]; then
    cp "$SCRIPT_DIR/bootstrap/SYS.COM" "$STAGING/DOS/SYS.COM"
else
    echo "ERROR: SYS.COM not found. Run the build first," >&2
    echo "or place SYS.COM in the bootstrap/ directory." >&2
    exit 1
fi

printf 'FILES=40\r\nBUFFERS=30\r\nSHELL=C:\\COMMAND.COM /E:2048 /P\r\n' > "$STAGING/CONFIG.SYS"

printf '@ECHO OFF\r\n' > "$STAGING/AUTOEXEC.BAT"
printf 'PATH C:\\DOS\r\n' >> "$STAGING/AUTOEXEC.BAT"
printf 'ECHO Transferring system to D: ...\r\n' >> "$STAGING/AUTOEXEC.BAT"
printf 'SYS C: D:\r\n' >> "$STAGING/AUTOEXEC.BAT"
printf 'ECHO Done.\r\n' >> "$STAGING/AUTOEXEC.BAT"
printf 'exitemu\r\n' >> "$STAGING/AUTOEXEC.BAT"

cat > "$TMPDIR/dosemurc" << EOF
\$_hdimage = "$STAGING $TMPDIR/hd.img"
EOF

echo "Running dosemu to write boot sector..."
dosemu -f "$TMPDIR/dosemurc" -dumb -td -kt < /dev/null

# --- Phase 2: Copy source tree via mtools ---

echo "Copying source tree to image..."

IMG="$TMPDIR/hd.img"
MCOPY="mcopy -i ${IMG}@@${MTOOLS_OFFSET} -o"
MMD="mmd -i ${IMG}@@${MTOOLS_OFFSET}"

# Create CONFIG.SYS for the build environment
printf 'FILES=40\r\n' > "$TMPDIR/config.sys"
printf 'BUFFERS=30\r\n' >> "$TMPDIR/config.sys"
printf 'SHELL=C:\\COMMAND.COM /E:2048 /P\r\n' >> "$TMPDIR/config.sys"

# AUTOEXEC.BAT that drops you at C:\ASTRO
printf '@ECHO OFF\r\n' > "$TMPDIR/autoexec.bat"
printf 'PROMPT $p$g\r\n' >> "$TMPDIR/autoexec.bat"
printf 'PATH C:\\ASTRO\\C6ERS\\TOOLS6\\BIN;C:\\ASTRO\\TOOLS\\BIN\r\n' >> "$TMPDIR/autoexec.bat"
printf 'SET INCLUDE=C:\\ASTRO\\C6ERS\\TOOLS6\\INCLUDE\r\n' >> "$TMPDIR/autoexec.bat"
printf 'SET LIB=C:\\ASTRO\\C6ERS\\TOOLS6\\LIB\r\n' >> "$TMPDIR/autoexec.bat"
printf 'SET TEMP=C:\\TMP\r\n' >> "$TMPDIR/autoexec.bat"
printf 'SET TMP=C:\\TMP\r\n' >> "$TMPDIR/autoexec.bat"
printf 'IF NOT EXIST C:\\TMP MD C:\\TMP\r\n' >> "$TMPDIR/autoexec.bat"
printf 'CD \\ASTRO\r\n' >> "$TMPDIR/autoexec.bat"
printf 'ECHO.\r\n' >> "$TMPDIR/autoexec.bat"
printf 'ECHO MS-DOS 6 source tree is at C:\\ASTRO\r\n' >> "$TMPDIR/autoexec.bat"
printf 'ECHO Type BUILDALL to build from source.\r\n' >> "$TMPDIR/autoexec.bat"

$MCOPY "$TMPDIR/config.sys" ::/CONFIG.SYS
$MCOPY "$TMPDIR/autoexec.bat" ::/AUTOEXEC.BAT

$MMD ::/ASTRO

echo "  Copying source tree..."
mcopy -s -o -i "${IMG}@@${MTOOLS_OFFSET}" "$SCRIPT_DIR"/* ::/ASTRO/

# --- Phase 3: Output raw image ---

echo "Stripping dosemu header..."
RAW_OUTPUT="$OUTPUT"
dd if="$TMPDIR/hd.img" of="$RAW_OUTPUT" bs=128 skip=1 2>/dev/null

RAW_SIZE=$(stat -c%s "$RAW_OUTPUT")

echo ""
echo "Success!"
echo ""
echo "  Image:  $RAW_OUTPUT"
echo "  Size:   $(( RAW_SIZE / 1024 / 1024 ))MB"
echo "  Source: C:\\ASTRO"
echo ""
echo "To boot with QEMU:"
echo "  qemu-system-i386 -hda $RAW_OUTPUT"
echo ""
echo "For v86 (async disk loading):"
echo "  hda: { url: \"$RAW_OUTPUT\", async: true, size: $RAW_SIZE }"
