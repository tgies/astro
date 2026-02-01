@echo off

:: DOS 6 (Astro) build wrapper for dosemu
:: CURRENTDIR is set by AUTOEXEC.BAT before this script runs

set oakpath=%CURRENTDIR%
set oakroot=%CURRENTDIR%

set PATH=%oakpath%c6ers\tools6\BIN;%oakpath%tools\BIN;%PATH%
set TEMP=%oakpath%c6ers\tools6\tmp
set TMP=%oakpath%c6ers\tools6\tmp
set INIT=%oakpath%c6ers\tools6\bin
set INCLUDE=%oakpath%c6ers\tools6\include
set LIB=%oakpath%c6ers\tools6\lib
set PROJ=500
set COUNTRY=USA
set BUILDER=YES
set LANG_SRC=%oakpath%LANG

echo DOS 6 Build Environment Set
echo CURRENTDIR=%CURRENTDIR%
echo PATH=%PATH%
echo.

nmake
