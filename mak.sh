#!/bin/bash

# DOS 6 (Astro) build wrapper using dosemu with MS-DOS 6.22
# Public Domain

set -e

[[ -z "$DOSEMU" ]] && DOSEMU=dosemu

# Write build commands to AUTOEXEC.BAT
# Set CURRENTDIR directly instead of using setcurd.bat hack
cat > ~/.dosemu/drive_c/AUTOEXEC.BAT << 'ENDOFBAT'
@echo off
set TEMP=c:\tmp
set TMP=c:\tmp
if not exist c:\tmp md c:\tmp
d:
cd \
set CURRENTDIR=D:\
call mak.bat
exitemu
ENDOFBAT

# Convert to DOS line endings
sed -i 's/$/\r/' ~/.dosemu/drive_c/AUTOEXEC.BAT

# Run dosemu
"$DOSEMU" -dumb -td -kt < /dev/null
