# ==============================================================================
# PowerShell Runner for Bitstream Evaluation
# ==============================================================================
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tclScript = Join-Path $scriptDir "scripts\run_bitstream.tcl"
$logFile   = Join-Path $scriptDir "logs\vivado_bitstream.log"
$jouFile   = Join-Path $scriptDir "logs\vivado_bitstream.jou"

# Locate Vivado portably
$vivadoBin = $null
$vivadoCandidates = @(
    $env:VIVADO_BIN,
    "Z:\2026.1\Vivado\bin\vivado.bat",
    "C:\Xilinx\Vivado\2026.1\bin\vivado.bat",
    "C:\Xilinx\Vivado\2025.2\bin\vivado.bat",
    "C:\Xilinx\Vivado\2024.2\bin\vivado.bat"
)

foreach ($cand in $vivadoCandidates) {
    if ($cand -and (Test-Path $cand)) {
        $vivadoBin = $cand
        break
    }
}

if (-not $vivadoBin) {
    $cmd = Get-Command "vivado.bat" -ErrorAction SilentlyContinue
    if ($cmd) {
        $vivadoBin = $cmd.Source
    } else {
        $cmd2 = Get-Command "vivado" -ErrorAction SilentlyContinue
        if ($cmd2) {
            $vivadoBin = $cmd2.Source
        }
    }
}

if (-not $vivadoBin) {
    Write-Error "Vivado executable not found in candidate paths or in PATH."
    exit 1
}

$vivadoPath = $vivadoBin

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  Starting Bitstream Generation Evaluation" -ForegroundColor Cyan
Write-Host "  Vivado Path : $vivadoPath"
Write-Host "  Tcl Script  : $tclScript"
Write-Host "  Log File    : $logFile"
Write-Host "================================================================================" -ForegroundColor Cyan

$process = Start-Process -FilePath $vivadoPath `
    -ArgumentList "-mode", "batch", "-source", "`"$tclScript`"", "-log", "`"$logFile`"", "-journal", "`"$jouFile`"" `
    -NoNewWindow -Wait -PassThru

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  Bitstream evaluation completed with exit code $($process.ExitCode)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

exit $process.ExitCode
