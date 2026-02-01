#!/bin/bash

# Boot the built MS-DOS 6 in dosemu
# Usage: ./boot.sh

BOOT_DIR=~/.dosemu/dos6built

# Copy built files to boot directory if not already done
if [ ! -f "$BOOT_DIR/io.sys" ]; then
    echo "Setting up boot directory..."
    mkdir -p "$BOOT_DIR/dos"
    
    # Copy system files
    cp binaries/io.sys "$BOOT_DIR/"
    cp binaries/msdos.sys "$BOOT_DIR/"
    cp compress/command.com "$BOOT_DIR/"
    
    # Copy all utilities
    cp binaries/*.exe "$BOOT_DIR/dos/" 2>/dev/null
    cp binaries/*.com "$BOOT_DIR/dos/" 2>/dev/null
    cp binaries/*.sys "$BOOT_DIR/dos/" 2>/dev/null
    cp binaries/*.386 "$BOOT_DIR/dos/" 2>/dev/null
    cp binaries/*.hlp "$BOOT_DIR/dos/" 2>/dev/null
    
    # Create CONFIG.SYS (no HIMEM for now to avoid error)
    printf 'FILES=40\r\nBUFFERS=30\r\n' > "$BOOT_DIR/CONFIG.SYS"
    
    # Create AUTOEXEC.BAT
    printf '@echo off\r\npath c:\\;c:\\dos\r\nset TEMP=c:\\temp\r\nif not exist c:\\temp md c:\\temp\r\nver\r\necho.\r\necho Successfully booted MS-DOS 6.0 built from source!\r\necho Type "dir c:\\dos" to see utilities.\r\necho.\r\n' > "$BOOT_DIR/AUTOEXEC.BAT"
    
    echo "Boot directory created at $BOOT_DIR"
fi

# Boot using -n to skip .dosemurc
exec dosemu -n --Fdrive_c "$BOOT_DIR" "$@"
