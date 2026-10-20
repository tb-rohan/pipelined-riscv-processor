# Vivado Batch Implementation Script for Standalone RV32I Processor
# Target Device: xc7a100tcsg324-1 (Artix-7 100T)
# Top Module: cpu_fpga_top

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set FPGA_DIR   [file normalize [file join $SCRIPT_DIR ".."]]
set REP_DIR    [file normalize [file join $FPGA_DIR "reports"]]
set LOG_DIR    [file normalize [file join $FPGA_DIR "logs"]]
set CKPT_DIR   [file normalize [file join $FPGA_DIR "checkpoints"]]

set SYNTH_DCP  [file join $CKPT_DIR "post_synth.dcp"]
if {![file exists $SYNTH_DCP]} {
    puts "ERROR: Synthesized checkpoint not found: $SYNTH_DCP"
    puts "Please run run_synthesis.ps1 first."
    exit 1
}

puts "================================================================================"
puts "  ATHENA / STANDALONE RV32I CPU VIVADO IMPLEMENTATION"
puts "  Synthesized Checkpoint: $SYNTH_DCP"
puts "================================================================================"

open_checkpoint $SYNTH_DCP

puts "INFO: Running opt_design..."
set t0 [clock seconds]
opt_design
set t1 [clock seconds]
puts "INFO: opt_design completed in [expr {$t1 - $t0}] seconds."
report_drc -file [file join $REP_DIR "opt_drc.rpt"]

puts "INFO: Running place_design..."
set t0 [clock seconds]
set place_status [catch {place_design} place_err]
set t1 [clock seconds]

if {$place_status != 0} {
    puts "================================================================================"
    puts "ERROR: place_design failed with the following error:"
    puts "$place_err"
    puts "================================================================================"
    set err_fp [open [file join $REP_DIR "place_error.rpt"] "w"]
    puts $err_fp "=== VIVADO PLACE_DESIGN ERROR REPORT ==="
    puts $err_fp $place_err
    close $err_fp
    exit 2
}

puts "INFO: place_design completed in [expr {$t1 - $t0}] seconds."
write_checkpoint -force [file join $CKPT_DIR "post_place.dcp"]
report_utilization -file [file join $REP_DIR "post_place_utilization.rpt"]
report_timing_summary -file [file join $REP_DIR "post_place_timing_summary.rpt"]

puts "INFO: Running phys_opt_design..."
catch {phys_opt_design}

puts "INFO: Running route_design..."
set t0 [clock seconds]
set route_status [catch {route_design} route_err]
set t1 [clock seconds]

if {$route_status != 0} {
    puts "================================================================================"
    puts "ERROR: route_design failed with the following error:"
    puts "$route_err"
    puts "================================================================================"
    set err_fp [open [file join $REP_DIR "route_error.rpt"] "w"]
    puts $err_fp "=== VIVADO ROUTE_DESIGN ERROR REPORT ==="
    puts $err_fp $route_err
    close $err_fp
    exit 3
}

puts "INFO: route_design completed in [expr {$t1 - $t0}] seconds."
write_checkpoint -force [file join $CKPT_DIR "post_route.dcp"]

puts "INFO: Generating post-route reports..."
report_route_status -file [file join $REP_DIR "post_route_status.rpt"]
report_utilization -file [file join $REP_DIR "post_route_utilization.rpt"] -pb [file join $REP_DIR "post_route_utilization.pb"]
report_timing_summary -file [file join $REP_DIR "post_route_timing_summary.rpt"]
report_timing -max_paths 10 -file [file join $REP_DIR "post_route_timing_max_paths.rpt"]
report_drc -file [file join $REP_DIR "post_route_drc.rpt"]

puts "================================================================================"
puts "  CPU IMPLEMENTATION COMPLETE"
puts "  Reports saved in: $REP_DIR"
puts "================================================================================"

exit 0
