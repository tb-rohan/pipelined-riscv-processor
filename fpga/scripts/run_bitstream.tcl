# ==============================================================================
# Vivado Bitstream Generation Evaluation Script
# Evaluates bitstream generation on post_route.dcp for cpu_fpga_top
# ==============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set FPGA_DIR   [file normalize [file join $SCRIPT_DIR ".."]]
set LOG_DIR    [file normalize [file join $FPGA_DIR "logs"]]
set REPORT_DIR [file normalize [file join $FPGA_DIR "reports"]]
set CKPT_DIR   [file normalize [file join $FPGA_DIR "checkpoints"]]

set ROUTE_DCP  [file normalize [file join $CKPT_DIR "post_route.dcp"]]
set BIT_FILE   [file normalize [file join $CKPT_DIR "cpu_fpga_top.bit"]]
set BIT_LOG    [file normalize [file join $LOG_DIR "bitstream_evaluation.log"]]

puts "================================================================================"
puts "  Evaluating Bitstream Generation"
puts "  Checkpoint: $ROUTE_DCP"
puts "================================================================================"

if {![file exists $ROUTE_DCP]} {
    puts "ERROR: Route checkpoint not found: $ROUTE_DCP"
    exit 1
}

# Open routed checkpoint
open_checkpoint $ROUTE_DCP

# Step 1: Attempt standard write_bitstream without DRC overrides to capture default behavior
puts "\n--- Attempting write_bitstream with default DRC rules ---"
set drc_catch [catch {write_bitstream -force -no_bitstream $BIT_FILE} err_msg]
if {$drc_catch != 0} {
    puts "Expected DRC rejection occurred without pin LOCs:"
    puts "$err_msg"
} else {
    puts "DRC check passed without errors."
}

# Step 2: Test with documented DRC downgrade for software-based unconstrained evaluation
puts "\n--- Applying documented DRC downgrades for unconstrained chip model ---"
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

# Step 3: Attempt bitstream write
puts "\n--- Generating bitstream with downgraded pin DRCs ---"
set bit_catch [catch {write_bitstream -force $BIT_FILE} bit_err]
if {$bit_catch != 0} {
    puts "Bitstream generation failed with error:"
    puts "$bit_err"
} else {
    puts "SUCCESS: Bitstream generated successfully at: $BIT_FILE"
    if {[file exists $BIT_FILE]} {
        set bit_size [file size $BIT_FILE]
        puts "Bitstream file size: $bit_size bytes"
    }
}

puts "================================================================================"
puts "  Bitstream evaluation complete."
puts "================================================================================"
exit 0
