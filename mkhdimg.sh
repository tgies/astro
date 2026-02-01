#!/bin/bash
#
# mkhdimg.sh - Create bootable MS-DOS 6 disk images
#
# Produces bootable disk images from the compiled binaries/ directory.
#
# Image types:
#   (default)  FAT16 hard disk image (bootable in QEMU, dosemu, VirtualBox)
#   --floppy   Minimal 1.44MB FAT12 boot floppy (IO.SYS, MSDOS.SYS, COMMAND.COM)
#
# Two variants:
#   --retail  Retail (io.sys/command.com with DoubleSpace hooks)
#   --oem     OEM base (io.bse/command.bse without DoubleSpace)
#
# Strategy: Uses dosemu with mkfatimage16 to create a properly formatted
# disk image, then runs SYS inside dosemu to write the authentic MS-DOS 6
# boot sector and system files.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARIES_DIR="$SCRIPT_DIR/binaries"

# Defaults
VARIANT="retail"
OUTPUT=""
SIZE_KB=65536  # 64MB in KB
FLOPPY=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--retail|--oem] [--floppy] [-o output.img] [--size SIZE_MB]

Options:
  --retail       Retail variant with DoubleSpace hooks (default)
  --oem          OEM base variant without DoubleSpace
  --floppy       Create a minimal 1.44MB boot floppy instead of a hard disk
  -o FILE        Output image file (default: dos6retail.img or dos6oem.img)
  --size SIZE    Disk size in MB (default: 64, ignored for --floppy)
  -h, --help     Show this help

The binaries/ directory must be populated (run the build first).
Requires: dosemu2, mtools, mkfatimage16
EOF
    exit "${1:-0}"
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --retail) VARIANT="retail"; shift ;;
        --oem)    VARIANT="oem"; shift ;;
        --floppy) FLOPPY=true; shift ;;
        -o)       OUTPUT="$2"; shift 2 ;;
        --size)   SIZE_KB=$(( $2 * 1024 )); shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

if [ -z "$OUTPUT" ]; then
    if $FLOPPY; then
        OUTPUT="dos6${VARIANT}-boot.img"
    else
        OUTPUT="dos6${VARIANT}.img"
    fi
fi

# Sanity checks
if [ ! -d "$BINARIES_DIR" ]; then
    echo "Error: binaries/ directory not found. Run the build first." >&2
    exit 1
fi

if $FLOPPY; then
    REQUIRED_CMDS="dosemu mformat"
else
    REQUIRED_CMDS="dosemu mkfatimage16"
fi
for cmd in $REQUIRED_CMDS; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd not found. Install dosemu2 and mtools." >&2
        exit 1
    fi
done

# Files that go to the root directory (not C:\DOS)
# These are excluded from the DOS directory copy
ROOT_ONLY_FILES="io.sys io.bse msdos.sys command.com command.bse wina20.386"

# OEM .bse/.oem remapping: source -> target name
# For OEM variant, these .bse files replace their counterparts
BSE_REMAP_chkdsk_bse="CHKDSK.EXE"
BSE_REMAP_format_bse="FORMAT.COM"
BSE_REMAP_setver_bse="SETVER.EXE"
BSE_REMAP_sys_bse="SYS.COM"
BSE_REMAP_command_bse="COMMAND.COM"
BSE_REMAP_help_oem="HELP.HLP"

# The original files that .bse files replace (excluded from OEM DOS dir)
OEM_EXCLUDED_ORIGINALS="chkdsk.exe format.com setver.exe sys.com command.com help.hlp"

if $FLOPPY; then
    echo "Creating $VARIANT MS-DOS 6 boot floppy image..."
    echo "  Output: $OUTPUT"
else
    echo "Creating $VARIANT MS-DOS 6 hard disk image..."
    echo "  Output: $OUTPUT"
    echo "  Size:   $(( SIZE_KB / 1024 ))MB"
fi

# Create temporary working directory
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

STAGING="$TMPDIR/staging"
mkdir -p "$STAGING/DOS"

# --- Phase 1: Build staging directory ---

echo "Preparing staging directory..."

# Copy system files to root based on variant
if [ "$VARIANT" = "retail" ]; then
    cp "$BINARIES_DIR/io.sys"      "$STAGING/IO.SYS"
    cp "$BINARIES_DIR/msdos.sys"   "$STAGING/MSDOS.SYS"
    cp "$BINARIES_DIR/command.com" "$STAGING/COMMAND.COM"
else
    # OEM: use .bse variants for system files
    cp "$BINARIES_DIR/io.bse"      "$STAGING/IO.SYS"
    cp "$BINARIES_DIR/msdos.sys"   "$STAGING/MSDOS.SYS"
    cp "$BINARIES_DIR/command.bse" "$STAGING/COMMAND.COM"
fi

if $FLOPPY; then
    # Floppy only needs SYS.COM in the DOS directory so the staging
    # boot can find it on PATH
    if [ "$VARIANT" = "retail" ]; then
        cp "$BINARIES_DIR/sys.com" "$STAGING/DOS/SYS.COM" 2>/dev/null || \
        cp "$BINARIES_DIR/SYS.COM" "$STAGING/DOS/SYS.COM"
    else
        cp "$BINARIES_DIR/sys.bse" "$STAGING/DOS/SYS.COM"
    fi
else
    # Hard disk image: full file layout

    # Copy WINA20.386
    cp "$BINARIES_DIR/wina20.386" "$STAGING/WINA20.386"

    # Generate CONFIG.SYS (from autoconf.c standard USA hard disk install)
    printf 'DEVICE=C:\\DOS\\SETVER.EXE\r\n' > "$STAGING/CONFIG.SYS"
    printf 'DEVICE=C:\\DOS\\HIMEM.SYS\r\n' >> "$STAGING/CONFIG.SYS"
    printf 'DOS=HIGH\r\n' >> "$STAGING/CONFIG.SYS"
    printf 'FILES=30\r\n' >> "$STAGING/CONFIG.SYS"

    # Generate the real AUTOEXEC.BAT (from autoconf.c) — saved separately
    # because the staging AUTOEXEC.BAT will be our install script
    printf 'C:\\DOS\\SMARTDRV.EXE\r\n' > "$STAGING/REAL_AE.BAT"
    printf '@ECHO OFF\r\n' >> "$STAGING/REAL_AE.BAT"
    printf 'PROMPT $p$g\r\n' >> "$STAGING/REAL_AE.BAT"
    printf 'PATH C:\\DOS\r\n' >> "$STAGING/REAL_AE.BAT"
    printf 'SET TEMP=C:\\DOS\r\n' >> "$STAGING/REAL_AE.BAT"

    # Copy files to DOS subdirectory
    echo "Copying DOS utilities..."

    for f in "$BINARIES_DIR"/*; do
        basename="$(basename "$f")"
        basename_lower="$(echo "$basename" | tr 'A-Z' 'a-z')"

        # Skip root-only files
        skip=false
        for r in $ROOT_ONLY_FILES; do
            if [ "$basename_lower" = "$r" ]; then
                skip=true
                break
            fi
        done
        $skip && continue

        if [ "$VARIANT" = "retail" ]; then
            # Retail: exclude all .bse and .oem files
            case "$basename_lower" in
                *.bse|*.oem) continue ;;
            esac
            # Copy with uppercase name
            target_name="$(echo "$basename" | tr 'a-z' 'A-Z')"
            cp "$f" "$STAGING/DOS/$target_name"

        else
            # OEM variant
            # Check if this is a .bse/.oem file that needs remapping
            key="$(echo "$basename_lower" | tr '.' '_')"
            remap_var="BSE_REMAP_${key}"
            remap_target="${!remap_var}"

            if [ -n "$remap_target" ]; then
                # This .bse/.oem file maps to a standard name
                cp "$f" "$STAGING/DOS/$remap_target"
                continue
            fi

            # Skip .bse/.oem files that aren't in the remap table
            case "$basename_lower" in
                *.bse|*.oem) continue ;;
            esac

            # Skip originals that are replaced by .bse files
            excluded=false
            for ex in $OEM_EXCLUDED_ORIGINALS; do
                if [ "$basename_lower" = "$ex" ]; then
                    excluded=true
                    break
                fi
            done
            $excluded && continue

            # Copy with uppercase name
            target_name="$(echo "$basename" | tr 'a-z' 'A-Z')"
            cp "$f" "$STAGING/DOS/$target_name"
        fi
    done

    echo "  Staged $(ls "$STAGING/DOS/" | wc -l) files in DOS directory"
fi

# --- Phase 2: Create target disk image ---

echo "Creating disk image..."

if $FLOPPY; then
    # Create a blank 1.44MB raw floppy image and format as FAT12
    dd if=/dev/zero of="$TMPDIR/floppy.img" bs=512 count=2880 2>/dev/null
    mformat -f 1440 -v MSDOS6 -i "$TMPDIR/floppy.img" ::
else
    # mkfatimage16 creates a dosemu-compatible hdimage with MBR + FAT16 partition
    mkfatimage16 -l MSDOS6 -k "$SIZE_KB" -f "$TMPDIR/target.img" -p

    # mkfatimage16 leaves the partition status as 0x00 (inactive).
    # Patch it to 0x80 (active/bootable) so DOS can boot from it.
    # The partition table entry starts at offset 574 (128-byte dosemu header + 446).
    printf '\x80' | dd of="$TMPDIR/target.img" bs=1 seek=574 count=1 conv=notrunc 2>/dev/null
fi

# --- Phase 3: Run dosemu to transfer system and files ---

echo "Running dosemu to install DOS onto image..."

# Minimal staging CONFIG.SYS for the dosemu boot environment.
# For HD images, the real CONFIG.SYS is saved as REAL_CF.SYS.
if ! $FLOPPY; then
    mv "$STAGING/CONFIG.SYS" "$STAGING/REAL_CF.SYS"
fi
printf 'FILES=40\r\n' > "$STAGING/CONFIG.SYS"
printf 'BUFFERS=30\r\n' >> "$STAGING/CONFIG.SYS"
printf 'SHELL=C:\\COMMAND.COM /E:2048 /P\r\n' >> "$STAGING/CONFIG.SYS"

# AUTOEXEC.BAT must have DOS line endings (\r\n) — use printf like mak.sh
printf '@ECHO OFF\r\n' > "$STAGING/AUTOEXEC.BAT"
printf 'PATH C:\\DOS\r\n' >> "$STAGING/AUTOEXEC.BAT"

if $FLOPPY; then
    # Floppy: just SYS to A:
    printf 'ECHO Transferring system to A: ...\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'SYS C: A:\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'ECHO Done! Floppy image is ready.\r\n' >> "$STAGING/AUTOEXEC.BAT"
else
    # Hard disk: SYS + copy all files to D:
    printf 'ECHO Transferring system to D: ...\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'SYS C: D:\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'MD D:\\DOS\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'ECHO Copying DOS utilities...\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'COPY C:\\DOS\\*.* D:\\DOS > NUL\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'ECHO Copying root files...\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'COPY C:\\REAL_CF.SYS D:\\CONFIG.SYS > NUL\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'COPY C:\\REAL_AE.BAT D:\\AUTOEXEC.BAT > NUL\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'COPY C:\\WINA20.386 D:\\ > NUL\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'ECHO Setting file attributes...\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'ATTRIB +R +H +S D:\\IO.SYS\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'ATTRIB +R +H +S D:\\MSDOS.SYS\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'ATTRIB +R D:\\COMMAND.COM\r\n' >> "$STAGING/AUTOEXEC.BAT"
    printf 'ECHO Done! Image is ready.\r\n' >> "$STAGING/AUTOEXEC.BAT"
fi
printf 'exitemu\r\n' >> "$STAGING/AUTOEXEC.BAT"

# Create dosemu config
if $FLOPPY; then
    # Staging dir is C: (boot drive), floppy image is A:
    cat > "$TMPDIR/dosemurc" << EOF
\$_hdimage = "$STAGING"
\$_floppy_a = "$TMPDIR/floppy.img:threeinch"
EOF
else
    # Staging dir is C: (boot drive), target image is D:
    cat > "$TMPDIR/dosemurc" << EOF
\$_hdimage = "$STAGING $TMPDIR/target.img"
EOF
fi

# Run dosemu in dumb terminal mode (same pattern as mak.sh)
dosemu -f "$TMPDIR/dosemurc" -dumb -td -kt < /dev/null

# --- Phase 4: Finalize ---

if $FLOPPY; then
    # Floppy image is already raw — just copy it out
    cp "$TMPDIR/floppy.img" "$OUTPUT"

    echo ""
    echo "Success!"
    echo ""
    echo "  Variant:  $VARIANT"
    echo "  Type:     1.44MB boot floppy"
    echo "  Files:    IO.SYS, MSDOS.SYS, COMMAND.COM"
    echo ""
    echo "  $OUTPUT   (raw 1.44MB floppy image)"
    echo ""
    echo "To boot with dosemu:"
    echo "  dosemu -f <(echo '\$_floppy_a = \"$OUTPUT:boot\"')"
    echo ""
    echo "To boot with QEMU:"
    echo "  qemu-system-i386 -fda $OUTPUT"
else
    # The dosemu hdimage format is a raw disk image with a 128-byte header.
    # Output both: the dosemu image as-is, and a raw image with the header stripped
    # for use in QEMU, VirtualBox, bochs, etc.
    cp "$TMPDIR/target.img" "$OUTPUT"

    RAW_OUTPUT="${OUTPUT%.img}.raw.img"
    dd if="$TMPDIR/target.img" of="$RAW_OUTPUT" bs=128 skip=1 2>/dev/null

    NUM_FILES="$(ls "$STAGING/DOS/" | wc -l)"

    echo ""
    echo "Success!"
    echo ""
    echo "  Variant:  $VARIANT"
    echo "  Size:     $(( SIZE_KB / 1024 ))MB"
    echo "  Files:    $NUM_FILES utilities in \\DOS"
    echo ""
    echo "  $OUTPUT         (dosemu hdimage format)"
    echo "  $RAW_OUTPUT     (raw disk image)"
    echo ""
    echo "To boot with dosemu:"
    echo "  dosemu -f <(echo '\$_hdimage = \"$OUTPUT\"')"
    echo ""
    echo "To boot with QEMU:"
    echo "  qemu-system-i386 -hda $RAW_OUTPUT"
fi
