@echo off
setlocal enabledelayedexpansion

echo ================================================================================
echo   ATHENA STUDIO: STANDALONE RV32I CPU FPGA SYNTHESIS AUTOMATION
echo ================================================================================

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

set "VIVADO_BIN="
if exist "Z:\2026.1\Vivado\bin\vivado.bat" (
    set "VIVADO_BIN=Z:\2026.1\Vivado\bin\vivado.bat"
) else if exist "C:\Xilinx\Vivado\2026.1\bin\vivado.bat" (
    set "VIVADO_BIN=C:\Xilinx\Vivado\2026.1\bin\vivado.bat"
) else (
    where vivado.bat >nul 2>&1
    if !errorlevel! equ 0 (
        for /f "delims=" %%i in ('where vivado.bat') do set "VIVADO_BIN=%%i"
    )
)

if not defined VIVADO_BIN (
    echo [ERROR] AMD/Xilinx Vivado installation was not found.
    exit /b 1
)

echo [INFO] Found Vivado at: %VIVADO_BIN%
echo [INFO] Running batch synthesis on Artix-7 (xc7a100tcsg324-1)...

if not exist logs mkdir logs
if not exist reports mkdir reports

"%VIVADO_BIN%" -mode batch -notrace -source scripts\run_synthesis.tcl -log logs\vivado_synth.log -journal logs\vivado_synth.jou
set SYNTH_ERR=%errorlevel%

if %SYNTH_ERR% neq 0 (
    echo [ERROR] CPU synthesis failed with exit code %SYNTH_ERR%.
    exit /b %SYNTH_ERR%
)

echo [SUCCESS] Standalone RV32I CPU Synthesis completed cleanly!
echo [INFO] Reports generated in %SCRIPT_DIR%reports\
exit /b 0
