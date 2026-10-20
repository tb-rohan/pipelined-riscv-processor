# ==============================================================================
# Script: run_cpu_regression.ps1
# Description: Automated Standalone RISC-V CPU Regression Suite (PowerShell)
#              Ensures fresh assembly, fresh RTL compilation, directed tests,
#              37-instruction ISA verification, and randomized testing.
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  ATHENA: STANDALONE RV32I CPU HARDWARE REGRESSION" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$riscvDir  = Split-Path -Parent $scriptDir
Set-Location $riscvDir

# 1. Verify / Assemble interactive_cpu.s
$asmSrc = Join-Path $riscvDir "software\asm\interactive_cpu.s"
$asmHex = Join-Path $riscvDir "software\asm\interactive_cpu.hex"
$asmPy  = Join-Path $riscvDir "software\assembler\riscv_assembler.py"

Write-Host "[1/4] Checking and assembling firmware..." -ForegroundColor Yellow
python $asmPy $asmSrc $asmHex
if ($LASTEXITCODE -ne 0) {
    Write-Error "Assembly failed!"
    exit $LASTEXITCODE
}

# 2. Fresh RTL Compilation with iverilog
Write-Host "[2/4] Compiling Standalone RV32I RTL with iverilog..." -ForegroundColor Yellow
$vvpBin = Join-Path $riscvDir "bin_cpu_interactive.vvp"

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
    "tb/cpu/tb_cpu_interactive.sv"
)

$iverilogCmd = @("-g2012", "-s", "tb_cpu_interactive", "-o", $vvpBin) + $rtlFiles
& iverilog $iverilogCmd
if ($LASTEXITCODE -ne 0) {
    Write-Error "iverilog compilation failed!"
    exit $LASTEXITCODE
}
Write-Host "  Compilation successful -> $vvpBin" -ForegroundColor Green

# 3. Directed Tests & ISA Verification
Write-Host "[3/4] Running Directed Tests & Full 37-Instruction ISA Suite..." -ForegroundColor Yellow

$testCases = @(
    @{ Cmd = 1;  A = 25;           B = 17;   Exp = 42;          Name = "Addition (25 + 17)" },
    @{ Cmd = 2;  A = -15;          B = 8;    Exp = -23;         Name = "Subtraction (-15 - 8)" },
    @{ Cmd = 3;  A = 15;           B = 20;   Exp = 300;         Name = "Multiplication (15 * 20)" },
    @{ Cmd = 3;  A = -7;           B = 9;    Exp = -63;         Name = "Multiplication (-7 * 9)" },
    @{ Cmd = 4;  A = 100;          B = 7;    Exp = 14; Hi = 2;  Name = "Division (100 / 7 -> Q:14, R:2)" },
    @{ Cmd = 4;  A = 42;           B = 0;    Exp = -1; Hi = 42; Name = "Division by Zero (42 / 0 -> Q:-1, R:42)" },
    @{ Cmd = 4;  A = -2147483648;  B = -1;   Exp = -2147483648; Hi = 0; Name = "Overflow Div (INT_MIN / -1)" },
    @{ Cmd = 5;  A = 0x0F0F;       B = 0xFF00; Exp = 0x0F00;    Name = "Bitwise AND" },
    @{ Cmd = 6;  A = 0x0F0F;       B = 0xF0F0; Exp = 0xFFFF;    Name = "Bitwise OR" },
    @{ Cmd = 7;  A = 12;           B = 10;   Exp = 6;           Name = "Bitwise XOR (12 ^ 10)" },
    @{ Cmd = 9;  A = 1;            B = 4;    Exp = 16;          Name = "Left Shift (1 << 4)" },
    @{ Cmd = 10; A = 64;           B = 3;    Exp = 8;           Name = "Logical Right Shift (64 >> 3)" },
    @{ Cmd = 11; A = -64;          B = 2;    Exp = -16;         Name = "Arithmetic Right Shift (-64 >>> 2)" },
    @{ Cmd = 12; A = -5;           B = 5;    Exp = 1;           Name = "Signed Comparison (-5 < 5)" },
    @{ Cmd = 13; A = 5;            B = 10;   Exp = 1;           Name = "Unsigned Comparison (5 < 10)" },
    @{ Cmd = 14; A = 0;            B = 0;    Exp = 37; Hi = 0x50415353; Name = "Full 37-Instruction RV32I ISA Suite" }
)

$passed = 0
$failed = 0

foreach ($tc in $testCases) {
    $out = & vvp $vvpBin "+CMD=$($tc.Cmd)" "+OP_A=$($tc.A)" "+OP_B=$($tc.B)"
    $resMatch = [regex]::Match($out, "CPU_RESULT_DEC=(-?\d+)")
    $hiMatch  = [regex]::Match($out, "CPU_RESULT_HI_DEC=(-?\d+)")
    $statusMatch = [regex]::Match($out, "CPU_STATUS=(PASS|FAIL)")

    $resVal = if ($resMatch.Success) { [int64]$resMatch.Groups[1].Value } else { $null }
    $hiVal  = if ($hiMatch.Success)  { [int64]$hiMatch.Groups[1].Value } else { $null }
    $status = if ($statusMatch.Success) { $statusMatch.Groups[1].Value } else { "FAIL" }

    $match = ($resVal -eq $tc.Exp) -and ($status -eq "PASS")
    if ($tc.ContainsKey("Hi")) {
        $match = $match -and ($hiVal -eq $tc.Hi)
    }

    if ($match) {
        $passed++
        Write-Host "  [PASS] $($tc.Name) -> Result = $resVal" -ForegroundColor Green
    } else {
        $failed++
        Write-Host "  [FAIL] $($tc.Name) -> Got $resVal, Expected $($tc.Exp)" -ForegroundColor Red
    }
}

# 4. Randomized Verification against Golden Python Reference
Write-Host "[4/4] Running 50 Randomized Operations via run_interactive_cpu.py..." -ForegroundColor Yellow
python scripts/run_interactive_cpu.py --random --count 50 --seed 42
if ($LASTEXITCODE -ne 0) {
    $failed++
} else {
    $passed += 50
}

Write-Host "================================================================================" -ForegroundColor Cyan
if ($failed -eq 0) {
    Write-Host "  REGRESSION COMPLETE: ALL $passed TESTS PASSED (100% SUCCESS)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  REGRESSION FAILED: $failed tests failed!" -ForegroundColor Red
    exit 1
}
