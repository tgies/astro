#!/bin/bash

# DOS 6 (Astro) build wrapper using dosemu with MS-DOS 6.22
# Self-contained - uses built DOS files, no external dependencies
# Public Domain

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ENV="$SCRIPT_DIR/.build-env"

[[ -z "$DOSEMU" ]] && DOSEMU=dosemu

# Check for built DOS system files
# These are the files we built from source
IO_SYS="$SCRIPT_DIR/bios/io.sys"
MSDOS_SYS="$SCRIPT_DIR/dos/msdos.sys"
COMMAND_COM="$SCRIPT_DIR/cmd/command/command.com"

if [[ ! -f "$IO_SYS" ]] || [[ ! -f "$MSDOS_SYS" ]] || [[ ! -f "$COMMAND_COM" ]]; then
    # Use bootstrap files (committed to repo for first build)
    if [[ -f "$SCRIPT_DIR/bootstrap/IO.SYS" ]]; then
        IO_SYS="$SCRIPT_DIR/bootstrap/IO.SYS"
        MSDOS_SYS="$SCRIPT_DIR/bootstrap/MSDOS.SYS"
        COMMAND_COM="$SCRIPT_DIR/bootstrap/COMMAND.COM"
        echo "Using bootstrap DOS files for first build..."
    else
        echo "ERROR: No DOS system files found."
        echo "Need bios/io.sys, dos/msdos.sys, cmd/command/command.com"
        echo "or bootstrap/IO.SYS, bootstrap/MSDOS.SYS, bootstrap/COMMAND.COM"
        exit 1
    fi
fi


# Create temporary build environment
rm -rf "$BUILD_ENV"
mkdir -p "$BUILD_ENV"

# Copy DOS system files
cp "$IO_SYS" "$BUILD_ENV/IO.SYS"
cp "$MSDOS_SYS" "$BUILD_ENV/MSDOS.SYS"
cp "$COMMAND_COM" "$BUILD_ENV/COMMAND.COM"

# Create CONFIG.SYS with expanded environment space
printf 'FILES=40\r\nBUFFERS=30\r\nSHELL=C:\\COMMAND.COM /E:2048 /P\r\n' > "$BUILD_ENV/CONFIG.SYS"

# Create AUTOEXEC.BAT
printf '@echo off\r\n' > "$BUILD_ENV/AUTOEXEC.BAT"
printf 'set TEMP=c:\\tmp\r\n' >> "$BUILD_ENV/AUTOEXEC.BAT"
printf 'set TMP=c:\\tmp\r\n' >> "$BUILD_ENV/AUTOEXEC.BAT"
printf 'if not exist c:\\tmp md c:\\tmp\r\n' >> "$BUILD_ENV/AUTOEXEC.BAT"
printf 'd:\r\n' >> "$BUILD_ENV/AUTOEXEC.BAT"
printf 'cd \\\r\n' >> "$BUILD_ENV/AUTOEXEC.BAT"
printf 'set CURRENTDIR=D:\\\r\n' >> "$BUILD_ENV/AUTOEXEC.BAT"
printf 'call mak.bat\r\n' >> "$BUILD_ENV/AUTOEXEC.BAT"
printf 'exitemu\r\n' >> "$BUILD_ENV/AUTOEXEC.BAT"

# Create dosemu config file
# Maps C: to build environment, D: to astro source
cat > "$BUILD_ENV/dosemurc" << EOF
\$_hdimage = "$BUILD_ENV $SCRIPT_DIR"
EOF

# Run dosemu with our config file
"$DOSEMU" -f "$BUILD_ENV/dosemurc" -dumb -td -kt < /dev/null
