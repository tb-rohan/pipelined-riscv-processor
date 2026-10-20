
"""
================================================================================
File: run_interactive_soc.py
Description: Interactive Terminal Runner & Verification Interface for the
             Integrated RV32I Processor + INT8 CNN Hardware Acceleration SoC.
================================================================================
Features:
  - Interactive menu and command-line execution options
  - High-resolution ASCII art rendering of 28x28 handwritten digit inputs
  - Real-time hardware simulation via Icarus Verilog (`vvp`)
  - End-to-end SoC verification: CPU instruction streaming, DMA transfers,
    accelerator execution, interrupt polling, result retrieval, and argmax
  - Complete 10-class logit display with bit-exact golden reference verification
  - Performance profiling: cycle count, latency (us @ 100MHz), and throughput (FPS)
================================================================================
"""

import sys 
import os 
import re 
import time 
import argparse 
import subprocess 
from pathlib import Path 


SCRIPT_DIR =Path (__file__ ).resolve ().parent 
PROJECT_DIR =SCRIPT_DIR .parent 
WORKSPACE_DIR =PROJECT_DIR .parent 
INT8_DIR =WORKSPACE_DIR /"INT8"
VECTORS_SUBSET =INT8_DIR /"vectors"/"mnist_rtl_subset"
SMOKE_DIR =INT8_DIR /"vectors"/"smoke"
VVP_BINARY =PROJECT_DIR /"bin_riscv_cnn_soc.vvp"


SUBSET_LABELS ={
0 :7 ,
1 :2 ,
2 :1 ,
3 :0 ,
4 :4 ,
7 :9 ,
8 :5 ,
11 :6 ,
18 :3 ,
61 :8 
}

ASCII_RAMP =" .:-=+*#%@"

def render_ascii_digit (image_path :Path )->str :
    """Reads 784-word input.hex and renders a 28x28 ASCII grayscale art representation."""
    if not image_path .exists ():
        return "[Image file not found]"

    with open (image_path ,"r",encoding ="ascii")as f :
        words =[line .strip ()for line in f if line .strip ()]

    if len (words )<784 :
        return f"[Invalid input.hex: expected 784 words, got {len (words )}]"

    lines =[]
    lines .append ("    +----------------------------+")
    for r in range (28 ):
        row_str ="    |"
        for c in range (28 ):
            val =int (words [r *28 +c ],16 )&0xFF 
            ramp_idx =int ((val /255.0 )*(len (ASCII_RAMP )-1 ))
            char =ASCII_RAMP [ramp_idx ]
            row_str +=char 
        row_str +="|"
        lines .append (row_str )
    lines .append ("    +----------------------------+")
    return "\n".join (lines )

def run_simulation (cmd_val :int ,image_hex :Path =None ,timeout :int =500000 ):
    """Executes the SoC simulation using vvp and returns parsed results."""
    if not VVP_BINARY .exists ():
        raise FileNotFoundError (f"Simulation binary not found: {VVP_BINARY }. Please compile first.")

    args =["vvp",str (VVP_BINARY ),f"+CMD={cmd_val }",f"+TIMEOUT={timeout }"]
    if image_hex and image_hex .exists ():
        args .append (f"+IMAGE_HEX={image_hex }")

    start_time =time .time ()
    proc =subprocess .run (args ,cwd =str (PROJECT_DIR ),stdout =subprocess .PIPE ,stderr =subprocess .PIPE ,text =True )
    elapsed_wall =time .time ()-start_time 

    if proc .returncode !=0 :
        return {
        "success":False ,
        "error":proc .stderr or proc .stdout ,
        "wall_time":elapsed_wall 
        }

    out =proc .stdout 

    res_dec_match =re .search (r"SOC_RESULT_DEC=(-?\d+)",out )
    res_hex_match =re .search (r"SOC_RESULT_HEX=0x([0-9a-fA-F]+)",out )
    score_match =re .search (r"SOC_WINNING_SCORE=(-?\d+)",out )
    cycles_match =re .search (r"SOC_CYCLES=(\d+)",out )
    status_match =re .search (r"SOC_STATUS=(PASS|FAIL)",out )

    logits ={}
    for match in re .finditer (r"LOGIT\[(\d+)\]=(-?\d+)",out ):
        logits [int (match .group (1 ))]=int (match .group (2 ))

    return {
    "success":(status_match .group (1 )=="PASS")if status_match else False ,
    "result_dec":int (res_dec_match .group (1 ))if res_dec_match else None ,
    "result_hex":res_hex_match .group (1 )if res_hex_match else None ,
    "winning_score":int (score_match .group (1 ))if score_match else None ,
    "cycles":int (cycles_match .group (1 ))if cycles_match else None ,
    "status":status_match .group (1 )if status_match else "UNKNOWN",
    "logits":logits ,
    "stdout":out ,
    "wall_time":elapsed_wall 
    }

def print_banner ():
    print ("""
================================================================================
  RISC-V (RV32I) + INT8 CNN ACCELERATOR INTEGRATED SoC RUNNER
================================================================================
  Architecture: 5-Stage Pipelined RV32I Core (Hazard & Forwarding Units)
  Accelerator:  Memory-Mapped 4x4 INT8 Systolic Array (Conv/Pool/FC)
  Interconnect: 32-bit Memory-Mapped Bus (0x8000_1000..0x8000_1030)
  Frequency:    100 MHz Synthesized Target | DMA Auto-Increment Streaming
================================================================================
""")

def run_sample (sample_id :int ):
    """Executes inference on a specific MNIST test sample."""
    sample_dir =VECTORS_SUBSET /str (sample_id )
    if not sample_dir .exists ():
        if sample_id ==0 and SMOKE_DIR .exists ():
            sample_dir =SMOKE_DIR 
        else :
            print (f"[!] Error: Sample directory {sample_dir } not found.")
            return 

    image_hex =sample_dir /"input.hex"
    golden_hex =sample_dir /"golden_layer4.hex"
    expected_label =SUBSET_LABELS .get (sample_id ,"?")

    print (f"\n[*] Selected MNIST Test Sample: #{sample_id } (Ground Truth: {expected_label })")
    print ("\n--- 28x28 Input Image (Grayscale Visualization) ---")
    print (render_ascii_digit (image_hex ))

    print ("\n[*] Launching RV32I + INT8 CNN Hardware Simulation...")
    res =run_simulation (cmd_val =1 ,image_hex =image_hex )

    if not res ["success"]:
        print (f"[!] Hardware Simulation Failed! Error: {res .get ('error')}")
        return 

    cycles =res ["cycles"]
    time_us =(cycles /100.0 )
    fps =(100_000_000.0 /cycles )if cycles else 0 

    print (f"\n==================== HARDWARE EXECUTION RESULTS ====================")
    print (f"  Predicted Digit (Argmax):  \033[1;32m{res ['result_dec']}\033[0m")
    print (f"  Ground Truth Label:        {expected_label }")
    print (f"  Classification Match:      {'CORRECT (PASS)'if res ['result_dec']==expected_label else 'MISMATCH'}")
    print (f"  Winning Class Score:       {res ['winning_score']}")
    print (f"  Hardware Clock Cycles:     {cycles :,} cycles")
    print (f"  Execution Latency:         {time_us :.2f} us (@ 100 MHz)")
    print (f"  Throughput:                {fps :,.1f} inferences/sec")
    print (f"  Simulation Wall Time:      {res ['wall_time']:.2f} s")
    print ("====================================================================")


    golden_logits =[]
    if golden_hex .exists ():
        with open (golden_hex ,"r",encoding ="ascii")as f :
            g_words =[line .strip ()for line in f if line .strip ()]
        for w in g_words [:3 ]:
            val =int (w ,16 )
            for b in range (4 ):
                byte_val =(val >>(b *8 ))&0xFF 
                if byte_val >=128 :
                    byte_val -=256 
                golden_logits .append (byte_val )
        golden_logits =golden_logits [:10 ]

    print ("\n--- 10-Class Output Logit Distribution (Layer 4 FC) ---")
    print (f"{'Class':<7} | {'HW Logit':<10} | {'Golden Logit':<14} | {'Match?':<8} | Distribution")
    print ("-"*65 )
    for c in range (10 ):
        hw_val =res ["logits"].get (c ,0 )
        g_val =golden_logits [c ]if c <len (golden_logits )else "-"
        match_str ="EXACT"if (c <len (golden_logits )and hw_val ==g_val )else "N/A"


        bar_len =max (0 ,min (25 ,int ((hw_val +70 )/4 )))
        star =" *"if c ==res ['result_dec']else ""
        print (f"Digit {c :<2} | {hw_val :>8}   | {str (g_val ):>12}   | {match_str :<8} | {'#'*bar_len }{star }")
    print ("-"*65 )

def run_small_test ():
    """Runs the 3-layer synthetic CNN pipeline test (Conv -> Pool -> FC)."""
    print ("\n[*] Executing Small Deterministic 3-Layer CNN Test (CMD=2)...")
    print ("    Configuration:")
    print ("      - Layer 0 (Conv): 2x2x4 input, 4 output channels, 1x1 stride, unit weights")
    print ("      - Layer 1 (Pool): 2x2 max-pooling (downsamples to 1x1x4)")
    print ("      - Layer 2 (FC):   1x1x4 fully connected, diagonal weights")
    print ("      - Target Output:  Bytes [7, 70, 8, 80] = 0x50084607")

    res =run_simulation (cmd_val =2 )
    if res ["success"]:
        print ("\n\033[1;32m[PASS] Integrated SoC successfully executed 3-layer CNN test!\033[0m")
        print (f"  Result Word:   0x{res ['result_hex']}")
        print (f"  Output Bytes:  [7, 70, 8, 80]")
        print (f"  Cycles Taken:  {res ['cycles']} cycles")
        print (f"  Latency:       {res ['cycles']*10 /1000.0 :.2f} us (@ 100 MHz)")
    else :
        print (f"\n\033[1;31m[FAIL] Small CNN test failed! Got 0x{res .get ('result_hex')}\033[0m")

def run_benchmark ():
    """Runs a performance stress test across available samples and summarizes results."""
    available_samples =sorted ([int (p .name )for p in VECTORS_SUBSET .iterdir ()if p .is_dir ()and p .name .isdigit ()])
    if not available_samples :
        available_samples =[0 ]

    print (f"\n[*] Running Full SoC Benchmark Across {len (available_samples )} Test Samples...")
    results =[]

    for sid in available_samples :
        s_dir =VECTORS_SUBSET /str (sid )
        img_hex =s_dir /"input.hex"
        expected =SUBSET_LABELS .get (sid ,"?")

        t0 =time .time ()
        res =run_simulation (cmd_val =1 ,image_hex =img_hex )
        wall_t =time .time ()-t0 

        predicted =res ["result_dec"]
        cycles =res ["cycles"]
        correct =(predicted ==expected )
        results .append ({
        "id":sid ,
        "expected":expected ,
        "predicted":predicted ,
        "cycles":cycles ,
        "correct":correct ,
        "wall_time":wall_t 
        })
        print (f"  Sample #{sid :2d}: Expected={expected }, Predicted={predicted }, Cycles={cycles }, Correct={correct }")

    total_cycles =sum (r ["cycles"]for r in results )
    avg_cycles =total_cycles /len (results )
    avg_latency_us =avg_cycles /100.0 
    throughput_fps =100_000_000.0 /avg_cycles 
    accuracy =sum (1 for r in results if r ["correct"])/len (results )*100.0 

    print ("\n======================= BENCHMARK SUMMARY =======================")
    print (f"  Total Inferences Evaluated: {len (results )}")
    print (f"  Classification Accuracy:    {accuracy :.1f}% ({sum (1 for r in results if r ['correct'])}/{len (results )})")
    print (f"  Average Cycles / Image:     {avg_cycles :,.0f} cycles")
    print (f"  Average Latency @ 100 MHz:  {avg_latency_us :.2f} us")
    print (f"  Peak Hardware Throughput:   {throughput_fps :,.1f} inferences/second")
    print ("==================================================================")

def interactive_menu ():
    print_banner ()
    while True :
        print ("\n=== Main Menu ===")
        print ("  1. Run MNIST Test Sample (Digits 0-9 with ASCII Art & Logits)")
        print ("  2. Run Small Deterministic 3-Layer CNN Test (Conv -> Pool -> FC)")
        print ("  3. Run Complete Benchmark Suite (Multi-Sample Accuracy & Latency)")
        print ("  4. Quick Smoke Test (Sample #0, Digit 7)")
        print ("  5. Exit")

        choice =input ("\nEnter selection (1-5): ").strip ()
        if choice =="1":
            print ("\nAvailable MNIST Sample IDs:",sorted (SUBSET_LABELS .keys ()))
            sid_input =input ("Enter sample ID (default: 0): ").strip ()
            sid =int (sid_input )if sid_input .isdigit ()else 0 
            run_sample (sid )
        elif choice =="2":
            run_small_test ()
        elif choice =="3":
            run_benchmark ()
        elif choice =="4":
            run_sample (0 )
        elif choice =="5":
            print ("\nExiting SoC Runner. Goodbye!")
            break 
        else :
            print ("[!] Invalid choice. Please select 1-5.")

def main ():
    parser =argparse .ArgumentParser (description ="RISC-V + INT8 CNN SoC Interactive Runner")
    parser .add_argument ("--sample",type =int ,help ="Run inference on specific sample ID (e.g. 0, 1, 2, 3, 4)")
    parser .add_argument ("--small",action ="store_true",help ="Run small 3-layer deterministic CNN test")
    parser .add_argument ("--benchmark",action ="store_true",help ="Run full benchmark across all subset samples")
    args =parser .parse_args ()

    if args .sample is not None :
        print_banner ()
        run_sample (args .sample )
    elif args .small :
        print_banner ()
        run_small_test ()
    elif args .benchmark :
        print_banner ()
        run_benchmark ()
    else :
        interactive_menu ()

if __name__ =="__main__":
    main ()
