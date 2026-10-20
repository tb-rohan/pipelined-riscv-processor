# Vivado Batch Synthesis Script for Standalone RV32I Processor
# Target Device: xc7a100tcsg324-1 (Artix-7 100T)
# Top Module: cpu_standalone_top

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set FPGA_DIR   [file normalize [file join $SCRIPT_DIR ".."]]
set RISCV_DIR  [file normalize [file join $FPGA_DIR ".."]]
set RTL_DIR    [file normalize [file join $RISCV_DIR "rtl"]]
set CONST_DIR  [file normalize [file join $FPGA_DIR "constraints"]]
set REP_DIR    [file normalize [file join $FPGA_DIR "reports"]]
set LOG_DIR    [file normalize [file join $FPGA_DIR "logs"]]
set CKPT_DIR   [file normalize [file join $FPGA_DIR "checkpoints"]]

file mkdir $REP_DIR
file mkdir $LOG_DIR
file mkdir $CKPT_DIR

set PART_NAME "xc7a100tcsg324-1"
set TOP_MODULE "cpu_fpga_top"

puts "================================================================================"
puts "  ATHENA / STANDALONE RV32I CPU VIVADO SYNTHESIS"
puts "  Target Part:   $PART_NAME"
puts "  Top Module:    $TOP_MODULE"
puts "  RTL Directory: $RTL_DIR"
puts "================================================================================"

read_verilog -sv [list \
    [file join $RTL_DIR "core" "riscv_pkg.sv"] \
    [file join $RTL_DIR "core" "alu.sv"] \
    [file join $RTL_DIR "core" "regfile.sv"] \
    [file join $RTL_DIR "core" "imm_gen.sv"] \
    [file join $RTL_DIR "core" "decoder.sv"] \
    [file join $RTL_DIR "core" "branch_unit.sv"] \
    [file join $RTL_DIR "core" "forwarding_unit.sv"] \
    [file join $RTL_DIR "core" "hazard_unit.sv"] \
    [file join $RTL_DIR "core" "pipe_reg_if_id.sv"] \
    [file join $RTL_DIR "core" "pipe_reg_id_ex.sv"] \
    [file join $RTL_DIR "core" "pipe_reg_ex_mem.sv"] \
    [file join $RTL_DIR "core" "pipe_reg_mem_wb.sv"] \
    [file join $RTL_DIR "core" "load_store_unit.sv"] \
    [file join $RTL_DIR "core" "rv32i_core.sv"] \
    [file join $RTL_DIR "memory" "ram_sync.sv"] \
    [file join $RTL_DIR "memory" "imem.sv"] \
    [file join $RTL_DIR "memory" "dmem.sv"] \
    [file join $RTL_DIR "peripherals" "host_interface.sv"] \
    [file join $RTL_DIR "peripherals" "timer.sv"] \
    [file join $RTL_DIR "peripherals" "uart_lite.sv"] \
    [file join $RTL_DIR "interconnect" "bus_interconnect.sv"] \
    [file join $RTL_DIR "soc" "cpu_standalone_top.sv"] \
    [file join $RTL_DIR "soc" "cpu_fpga_top.sv"] \
]

read_xdc [file join $CONST_DIR "clock.xdc"]

set HEX_PATH [file normalize [file join $RISCV_DIR "software" "asm" "interactive_cpu.hex"]]
puts "INFO: Instruction memory initialization file: $HEX_PATH"
if {![file exists $HEX_PATH]} {
    puts "WARNING: $HEX_PATH does not exist. Assembling default firmware..."
}

puts "INFO: Starting synthesis of $TOP_MODULE on $PART_NAME..."
set start_time [clock seconds]

synth_design -top $TOP_MODULE -part $PART_NAME -flatten_hierarchy rebuilt -generic IMEM_INIT_FILE=$HEX_PATH

set end_time [clock seconds]
set elapsed [expr {$end_time - $start_time}]
puts "INFO: CPU Synthesis completed in $elapsed seconds."

write_checkpoint -force [file join $CKPT_DIR "post_synth.dcp"]

puts "INFO: Generating synthesis reports in $REP_DIR..."
report_utilization -file [file join $REP_DIR "synth_utilization.rpt"] -pb [file join $REP_DIR "synth_utilization.pb"]
report_utilization -hierarchical -file [file join $REP_DIR "synth_utilization_hierarchical.rpt"]
report_timing_summary -file [file join $REP_DIR "synth_timing_summary.rpt"]
report_timing -max_paths 10 -file [file join $REP_DIR "synth_timing_max_paths.rpt"]
report_drc -file [file join $REP_DIR "synth_drc.rpt"]

set latches [all_latches]
set latch_count [llength $latches]
set latch_file [open [file join $REP_DIR "synth_latches.rpt"] "w"]
puts $latch_file "=== INFERRED LATCH REPORT (CPU) ==="
puts $latch_file "Total Inferred Latches: $latch_count"
if {$latch_count > 0} {
    puts $latch_file "WARNING: Latches detected in design:"
    foreach l $latches {
        puts $latch_file "  $l"
    }
} else {
    puts $latch_file "Clean design: Zero inferred latches."
}
close $latch_file

puts "================================================================================"
puts "  CPU SYNTHESIS REPORT SUMMARY"
puts "  Inferred Latches: $latch_count"
puts "  Reports saved in: $REP_DIR"
puts "================================================================================"

exit 0
