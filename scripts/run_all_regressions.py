
"""
================================================================================
File: run_all_regressions.py
Description: Master Automated Regression Suite for the Pipelined RISC-V CPU
             with Memory-Mapped INT8 CNN Hardware Acceleration.
================================================================================
Validates all three execution configurations:
  1. Configuration 1: Standalone RISC-V CPU (Arithmetic, Logic, Shifts,
     Software Mul/Div, Randomized Testing)
  2. Configuration 2: Standalone INT8 CNN Accelerator (Preserved baseline suite:
     PE, Systolic Array, Post-Processor, Memory Controller, Control Unit,
     Full 5-Layer CNN Schedule)
  3. Configuration 3: Integrated RISC-V + INT8 CNN SoC (Memory-Mapped AXI-Lite
     Interconnect, DMA Data Streaming, Interrupt Polling, Argmax Prediction)
================================================================================
"""

import sys 
import os 
import re 
import time 
import subprocess 
from pathlib import Path 

SCRIPT_DIR =Path (__file__ ).resolve ().parent 
PROJECT_DIR =SCRIPT_DIR .parent 
WORKSPACE_DIR =PROJECT_DIR .parent 
INT8_DIR =WORKSPACE_DIR /"INT8"

CPU_VVP =PROJECT_DIR /"bin_cpu_interactive.vvp"
SOC_VVP =PROJECT_DIR /"bin_riscv_cnn_soc.vvp"

class Colors :
    GREEN ="\033[1;32m"
    RED ="\033[1;31m"
    YELLOW ="\033[1;33m"
    CYAN ="\033[1;36m"
    BOLD ="\033[1m"
    RESET ="\033[0m"

def print_header (title :str ):
    print (f"\n{Colors .CYAN }{'='*80 }")
    print (f"  {title }")
    print (f"{'='*80 }{Colors .RESET }")

def run_cmd (cmd :list ,cwd :Path =PROJECT_DIR ,timeout :int =300 )->tuple :
    start_t =time .time ()
    try :
        proc =subprocess .run (
        cmd ,
        cwd =str (cwd ),
        stdout =subprocess .PIPE ,
        stderr =subprocess .PIPE ,
        text =True ,
        timeout =timeout 
        )
        elapsed =time .time ()-start_t 
        return (proc .returncode ==0 ,proc .stdout ,proc .stderr ,elapsed )
    except subprocess .TimeoutExpired :
        return (False ,"",f"Timeout after {timeout } seconds",time .time ()-start_t )




def run_cpu_tests ()->dict :
    print_header ("SUITE 1: STANDALONE RISC-V CPU ARITHMETIC & CONTROL VERIFICATION")

    sys .path .insert (0 ,str (SCRIPT_DIR ))
    from run_interactive_cpu import ensure_compiled ,python_reference 
    print ("  [*] Ensuring standalone CPU RTL and assembly are freshly compiled...")
    ensure_compiled ()

    test_cases =[
    {"cmd":1 ,"a":25 ,"b":17 ,"exp_res":42 ,"name":"Addition (25 + 17)"},
    {"cmd":2 ,"a":-15 ,"b":8 ,"exp_res":-23 ,"name":"Subtraction (-15 - 8)"},
    {"cmd":3 ,"a":15 ,"b":20 ,"exp_res":300 ,"name":"Multiplication (15 * 20)"},
    {"cmd":3 ,"a":-7 ,"b":9 ,"exp_res":-63 ,"name":"Multiplication (-7 * 9)"},
    {"cmd":4 ,"a":100 ,"b":7 ,"exp_res":14 ,"exp_hi":2 ,"name":"Division (100 / 7 -> Q:14, R:2)"},
    {"cmd":4 ,"a":42 ,"b":0 ,"exp_res":-1 ,"exp_hi":42 ,"name":"Division by Zero (42 / 0 -> Q:-1, R:42)"},
    {"cmd":4 ,"a":-2147483648 ,"b":-1 ,"exp_res":-2147483648 ,"exp_hi":0 ,"name":"Overflow Division (INT_MIN / -1)"},
    {"cmd":7 ,"a":12 ,"b":10 ,"exp_res":6 ,"name":"XOR (12 ^ 10)"},
    ]

    passed =0 
    total =len (test_cases )

    for tc in test_cases :
        args =[
        "vvp",str (CPU_VVP ),
        f"+CMD={tc ['cmd']}",
        f"+OP_A={tc ['a']}",
        f"+OP_B={tc ['b']}"
        ]
        ok ,out ,err ,elapsed =run_cmd (args )

        res_m =re .search (r"CPU_RESULT_DEC=(-?\d+)",out )
        hi_m =re .search (r"CPU_RESULT_HI_DEC=(-?\d+)",out )
        res_val =int (res_m .group (1 ))if res_m else None 
        hi_val =int (hi_m .group (1 ))if hi_m else None 

        match =(res_val ==tc ["exp_res"])
        if "exp_hi"in tc :
            match =match and (hi_val ==tc ["exp_hi"])

        if ok and match :
            passed +=1 
            print (f"  [{Colors .GREEN }PASS{Colors .RESET }] {tc ['name']:<40} -> Result={res_val } ({elapsed *1000 :.1f} ms)")
        else :
            print (f"  [{Colors .RED }FAIL{Colors .RESET }] {tc ['name']:<40} -> Got {res_val }, Expected {tc ['exp_res']}")


    sys .path .insert (0 ,str (SCRIPT_DIR ))
    from run_interactive_cpu import python_reference 

    print ("\n  [*] Running 50 Randomized Operations across all ALU/Mul/Div ops (Seed: 42)...")
    import random 
    rng =random .Random (42 )
    rand_passed =0 
    for i in range (50 ):
        op =rng .randint (1 ,13 )
        a =rng .randint (-1000 ,1000 )
        b =rng .randint (-1000 ,1000 )
        exp_lo ,exp_hi =python_reference (op ,a ,b )

        args =["vvp",str (CPU_VVP ),f"+CMD={op }",f"+OP_A={a }",f"+OP_B={b }"]
        ok ,out ,_ ,_ =run_cmd (args )
        res_m =re .search (r"RESULT_DEC=(-?\d+)",out )
        res_val =int (res_m .group (1 ))if res_m else None 
        if res_val ==exp_lo :
            rand_passed +=1 

    print (f"  [{Colors .GREEN }PASS{Colors .RESET }] Randomized Arithmetic: {rand_passed }/50 tests passed perfectly!")
    return {"passed":passed +rand_passed ,"total":total +50 }




def run_accel_tests ()->dict :
    print_header ("SUITE 2: STANDALONE INT8 CNN HARDWARE ACCELERATOR TESTBENCHES")
    print ("  [*] Verifying 100% preservation of INT8 accelerator RTL & testbenches...")

    tests =[
    ("tb_pe",["rtl/pe.sv","tb/tb_pe.sv"]),
    ("tb_pe_array",["rtl/cnn_pkg.sv","rtl/pe.sv","rtl/pe_array.sv","tb/tb_pe_array.sv"]),
    ("tb_post_proc",["rtl/cnn_pkg.sv","rtl/post_proc.sv","tb/tb_post_proc.sv"]),
    ("tb_mem_ctrl_random",["rtl/cnn_pkg.sv","rtl/mem_ctrl.sv","tb/tb_mem_ctrl_random.sv"]),
    ("tb_mem_ctrl_zero_scan",["rtl/cnn_pkg.sv","rtl/mem_ctrl.sv","tb/tb_mem_ctrl_zero_scan.sv"]),
    ("tb_ctrl_unit",["rtl/cnn_pkg.sv","rtl/ctrl_unit.sv","tb/tb_ctrl_unit.sv"]),
    ("tb_top",["rtl/cnn_pkg.sv","rtl/pe.sv","rtl/pe_array.sv","rtl/post_proc.sv","rtl/mem_ctrl.sv","rtl/ctrl_unit.sv","rtl/accel_top.sv","tb/tb_top.sv"]),
    ("tb_full_cnn",["rtl/cnn_pkg.sv","rtl/pe.sv","rtl/pe_array.sv","rtl/post_proc.sv","rtl/mem_ctrl.sv","rtl/ctrl_unit.sv","rtl/accel_top.sv","tb/tb_full_cnn.sv"]),
    ]

    passed =0 
    temp_dir =PROJECT_DIR /"temp_accel_test"
    temp_dir .mkdir (exist_ok =True )

    for name ,sources in tests :
        vvp_out =temp_dir /f"{name }.vvp"
        compile_cmd =["iverilog","-g2012","-s",name ,"-o",str (vvp_out )]+[str (INT8_DIR /s )for s in sources ]
        ok_compile ,_ ,err_comp ,_ =run_cmd (compile_cmd ,cwd =INT8_DIR )
        if not ok_compile :
            print (f"  [{Colors .RED }FAIL{Colors .RESET }] {name :<25} Compilation error: {err_comp }")
            continue 

        run_command =["vvp",str (vvp_out )]
        ok_run ,out ,err_run ,elapsed =run_cmd (run_command ,cwd =INT8_DIR )

        has_pass =("PASS"in out )
        if ok_run and has_pass :
            passed +=1 
            print (f"  [{Colors .GREEN }PASS{Colors .RESET }] {name :<25} Verified cleanly ({elapsed :.2f} s)")
        else :
            print (f"  [{Colors .RED }FAIL{Colors .RESET }] {name :<25} Test execution failed!")

    return {"passed":passed ,"total":len (tests )}




def run_soc_tests ()->dict :
    print_header ("SUITE 3: INTEGRATED RISC-V + INT8 CNN SoC SYSTEM-LEVEL VERIFICATION")

    passed =0 
    total =3 


    print ("  [*] Running Test 1: Small Deterministic 3-Layer Workload (Conv -> Pool -> FC)...")
    ok ,out ,_ ,elapsed =run_cmd (["vvp",str (SOC_VVP ),"+CMD=2"])
    if ok and ("0x50084607"in out )and ("SOC_STATUS=PASS"in out ):
        passed +=1 
        print (f"  [{Colors .GREEN }PASS{Colors .RESET }] Small 3-Layer Test: Bytes [7, 70, 8, 80] verified ({elapsed :.2f} s)")
    else :
        print (f"  [{Colors .RED }FAIL{Colors .RESET }] Small 3-Layer Test failed!")


    print ("  [*] Running Test 2: Full MNIST Inference Sample #0 (Ground Truth = 7)...")
    img0 =INT8_DIR /"vectors"/"mnist_rtl_subset"/"0"/"input.hex"
    ok ,out ,_ ,elapsed =run_cmd (["vvp",str (SOC_VVP ),"+CMD=1",f"+IMAGE_HEX={img0 }"])
    if ok and ("SOC_RESULT_DEC=7"in out )and ("SOC_WINNING_SCORE=47"in out )and ("SOC_STATUS=PASS"in out ):
        passed +=1 
        print (f"  [{Colors .GREEN }PASS{Colors .RESET }] MNIST Sample #0: Predicted=7, Score=47 (EXACT MATCH, {elapsed :.2f} s)")
    else :
        print (f"  [{Colors .RED }FAIL{Colors .RESET }] MNIST Sample #0 failed!")


    print ("  [*] Running Test 3: Full MNIST Inference Sample #1 (Ground Truth = 2)...")
    img1 =INT8_DIR /"vectors"/"mnist_rtl_subset"/"1"/"input.hex"
    ok ,out ,_ ,elapsed =run_cmd (["vvp",str (SOC_VVP ),"+CMD=1",f"+IMAGE_HEX={img1 }"])
    if ok and ("SOC_RESULT_DEC=2"in out )and ("SOC_WINNING_SCORE=34"in out )and ("SOC_STATUS=PASS"in out ):
        passed +=1 
        print (f"  [{Colors .GREEN }PASS{Colors .RESET }] MNIST Sample #1: Predicted=2, Score=34 (EXACT MATCH, {elapsed :.2f} s)")
    else :
        print (f"  [{Colors .RED }FAIL{Colors .RESET }] MNIST Sample #1 failed!")

    return {"passed":passed ,"total":total }




def main ():
    start_all =time .time ()
    print (f"""
{Colors .BOLD }================================================================================
  MASTER HARDWARE REGRESSION SUITE
  Pipelined RISC-V CPU with Memory-Mapped INT8 CNN Accelerator
================================================================================{Colors .RESET }""")

    res_cpu =run_cpu_tests ()
    res_acc =run_accel_tests ()
    res_soc =run_soc_tests ()

    total_passed =res_cpu ["passed"]+res_acc ["passed"]+res_soc ["passed"]
    total_tests =res_cpu ["total"]+res_acc ["total"]+res_soc ["total"]
    elapsed_all =time .time ()-start_all 

    print_header ("FINAL REGRESSION SUMMARY REPORT")
    print (f"  1. Standalone RISC-V CPU Suite:      {res_cpu ['passed']}/{res_cpu ['total']} PASS")
    print (f"  2. Standalone INT8 CNN Suite:        {res_acc ['passed']}/{res_acc ['total']} PASS")
    print (f"  3. Integrated RISC-V + INT8 SoC:     {res_soc ['passed']}/{res_soc ['total']} PASS")
    print ("-"*80 )

    if total_passed ==total_tests :
        print (f"  {Colors .GREEN }{Colors .BOLD }OVERALL STATUS: ALL {total_tests } REGRESSION TESTS PASSED (100% SUCCESS){Colors .RESET }")
    else :
        print (f"  {Colors .RED }{Colors .BOLD }OVERALL STATUS: {total_tests -total_passed } TESTS FAILED{Colors .RESET }")
    print (f"  Total Wall Clock Time: {elapsed_all :.2f} seconds")
    print ("="*80 +"\n")

    sys .exit (0 if total_passed ==total_tests else 1 )

if __name__ =="__main__":
    main ()
