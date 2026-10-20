$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  ATHENA STUDIO: STANDALONE RV32I CPU IMPLEMENTATION AUTOMATION (PowerShell)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$vivadoCandidates = @(
    $env:VIVADO_BIN,
    "Z:\2026.1\Vivado\bin\vivado.bat",
    "C:\Xilinx\Vivado\2026.1\bin\vivado.bat",
    "C:\Xilinx\Vivado\2025.2\bin\vivado.bat",
    "C:\Xilinx\Vivado\2024.2\bin\vivado.bat"
)

$vivadoBin = $null
foreach ($cand in $vivadoCandidates) {
    if (Test-Path $cand) {
        $vivadoBin = $cand
        break
    }
}

if (-not $vivadoBin) {
    $cmd = Get-Command "vivado.bat" -ErrorAction SilentlyContinue
    if ($cmd) {
        $vivadoBin = $cmd.Source
    }
}

if (-not $vivadoBin) {
    Write-Error "AMD/Xilinx Vivado installation was not found."
    exit 1
}

Write-Host "[INFO] Found Vivado: $vivadoBin" -ForegroundColor Green
Write-Host "[INFO] Starting batch implementation for xc7a100tcsg324-1..." -ForegroundColor Yellow

New-Item -ItemType Directory -Path "$scriptDir\logs", "$scriptDir\reports", "$scriptDir\checkpoints" -Force | Out-Null

$proc = Start-Process -FilePath $vivadoBin -ArgumentList "-mode batch -notrace -source scripts/run_implementation.tcl -log logs/vivado_impl.log -journal logs/vivado_impl.jou" -NoNewWindow -PassThru -Wait

if ($proc.ExitCode -ne 0) {
    Write-Warning "Vivado implementation exited with code $($proc.ExitCode). Check logs/vivado_impl.log and reports/ for diagnostics."
    exit $proc.ExitCode
}

Write-Host "[SUCCESS] Standalone RV32I CPU Implementation completed cleanly!" -ForegroundColor Green
Write-Host "[INFO] Implementation reports available in $scriptDir\reports\" -ForegroundColor Cyan
exit 0
