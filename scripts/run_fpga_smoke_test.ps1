# ==============================================================================
# Script: run_fpga_smoke_test.ps1
# Description: Compiles and runs the FPGA top-level wrapper smoke test
#              (tb_cpu_fpga_top) with iverilog and vvp.
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  ATHENA: FPGA TOP-LEVEL WRAPPER SMOKE TEST (tb_cpu_fpga_top)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$riscvDir  = Split-Path -Parent $scriptDir
Set-Location $riscvDir

# 1. Verify firmware is assembled
$asmSrc = Join-Path $riscvDir "software\asm\interactive_cpu.s"
$asmHex = Join-Path $riscvDir "software\asm\interactive_cpu.hex"
$asmPy  = Join-Path $riscvDir "software\assembler\riscv_assembler.py"

Write-Host "[1/3] Ensuring firmware is freshly assembled..." -ForegroundColor Yellow
python $asmPy $asmSrc $asmHex
if ($LASTEXITCODE -ne 0) {
    Write-Error "Assembly failed!"
    exit $LASTEXITCODE
}

# 2. Compile FPGA top testbench
Write-Host "[2/3] Compiling cpu_fpga_top and testbench with iverilog..." -ForegroundColor Yellow
$vvpBin = Join-Path $riscvDir "bin_cpu_fpga_top.vvp"

$rtlFiles = @(
    "rtl/core/riscv_pkg.sv",
    "rtl/core/alu.sv",
    "rtl/core/regfile.sv",
    "rtl/core/imm_gen.sv",
    "rtl/core/decoder.sv",
    "rtl/core/branch_unit.sv",
    "rtl/core/forwarding_unit.sv",
    "rtl/core/hazard_unit.sv",
    "rtl/core/pipe_reg_if_id.sv",
    "rtl/core/pipe_reg_id_ex.sv",
    "rtl/core/pipe_reg_ex_mem.sv",
    "rtl/core/pipe_reg_mem_wb.sv",
    "rtl/core/load_store_unit.sv",
    "rtl/core/rv32i_core.sv",
    "rtl/memory/ram_sync.sv",
    "rtl/memory/imem.sv",
    "rtl/memory/dmem.sv",
    "rtl/peripherals/host_interface.sv",
    "rtl/peripherals/timer.sv",
    "rtl/peripherals/uart_lite.sv",
    "rtl/interconnect/bus_interconnect.sv",
    "rtl/soc/cpu_standalone_top.sv",
    "rtl/soc/cpu_fpga_top.sv",
    "tb/cpu/tb_cpu_fpga_top.sv"
)

$iverilogCmd = @("-g2012", "-s", "tb_cpu_fpga_top", "-o", $vvpBin) + $rtlFiles
& iverilog $iverilogCmd
if ($LASTEXITCODE -ne 0) {
    Write-Error "iverilog compilation failed!"
    exit $LASTEXITCODE
}
Write-Host "  Compilation successful -> $vvpBin" -ForegroundColor Green

# 3. Execute Smoke Test
Write-Host "[3/3] Running FPGA Top Smoke Test simulation with vvp..." -ForegroundColor Yellow
& vvp $vvpBin
if ($LASTEXITCODE -ne 0) {
    Write-Error "FPGA Top Smoke Test simulation failed!"
    exit $LASTEXITCODE
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  FPGA TOP-LEVEL WRAPPER SMOKE TEST PASSED (100% SUCCESS)" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
exit 0
