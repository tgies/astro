#!/bin/bash

# Boot the built MS-DOS 6 in dosemu
# Self-contained - uses local .boot directory
# Usage: ./boot.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT_DIR="$SCRIPT_DIR/.boot"

# Copy built files to boot directory if not already done
if [ ! -f "$BOOT_DIR/IO.SYS" ]; then
    echo "Setting up boot directory..."
    mkdir -p "$BOOT_DIR/dos"
    
    # Copy system files from built output
    cp "$SCRIPT_DIR/bios/io.sys" "$BOOT_DIR/IO.SYS"
    cp "$SCRIPT_DIR/dos/msdos.sys" "$BOOT_DIR/MSDOS.SYS"
    cp "$SCRIPT_DIR/cmd/command/command.com" "$BOOT_DIR/COMMAND.COM"
    
    # Copy all utilities from binaries/
    cp "$SCRIPT_DIR/binaries/"*.exe "$BOOT_DIR/dos/" 2>/dev/null || true
    cp "$SCRIPT_DIR/binaries/"*.com "$BOOT_DIR/dos/" 2>/dev/null || true
    cp "$SCRIPT_DIR/binaries/"*.sys "$BOOT_DIR/dos/" 2>/dev/null || true
    cp "$SCRIPT_DIR/binaries/"*.hlp "$BOOT_DIR/dos/" 2>/dev/null || true
    
    # Create CONFIG.SYS
    printf 'FILES=40\r\nBUFFERS=30\r\n' > "$BOOT_DIR/CONFIG.SYS"
    
    # Create AUTOEXEC.BAT
    printf '@echo off\r\n' > "$BOOT_DIR/AUTOEXEC.BAT"
    printf 'path c:\\;c:\\dos\r\n' >> "$BOOT_DIR/AUTOEXEC.BAT"
    printf 'set TEMP=c:\\temp\r\n' >> "$BOOT_DIR/AUTOEXEC.BAT"
    printf 'if not exist c:\\temp md c:\\temp\r\n' >> "$BOOT_DIR/AUTOEXEC.BAT"
    printf 'ver\r\n' >> "$BOOT_DIR/AUTOEXEC.BAT"
    printf 'echo.\r\n' >> "$BOOT_DIR/AUTOEXEC.BAT"
    printf 'echo Successfully booted MS-DOS 6.0 built from source!\r\n' >> "$BOOT_DIR/AUTOEXEC.BAT"
    printf 'echo Type "dir c:\\dos" to see utilities.\r\n' >> "$BOOT_DIR/AUTOEXEC.BAT"
    printf 'echo.\r\n' >> "$BOOT_DIR/AUTOEXEC.BAT"
    
    echo "Boot directory created at $BOOT_DIR"
fi

# Create dosemu config file
cat > "$BOOT_DIR/dosemurc" << EOF
\$_hdimage = "$BOOT_DIR"
EOF

# Boot using our config file
exec dosemu -f "$BOOT_DIR/dosemurc" "$@"
