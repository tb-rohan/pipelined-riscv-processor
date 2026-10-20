`timescale 1ns/1ps

module tb_cpu_fpga_top;

  logic       clk = 0;
  logic       rst_n = 0;
  logic       btn_trigger = 0;
  logic [1:0] sw_mode = 2'b00;

  wire [7:0]  led;
  wire        led_done;
  wire        led_pass;
  wire        led_fail;
  wire        led_heartbeat;

  always #5 clk = ~clk; // 100 MHz clock (10 ns period)

  cpu_fpga_top #(
    .IMEM_INIT_FILE("software/asm/interactive_cpu.hex"),
    .DMEM_INIT_FILE("")
  ) dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .btn_trigger  (btn_trigger),
    .sw_mode      (sw_mode),
    .led          (led),
    .led_done     (led_done),
    .led_pass     (led_pass),
    .led_fail     (led_fail),
    .led_heartbeat(led_heartbeat)
  );

  integer timeout_cnt;

  initial begin
    $display("================================================================================");
    $display("  STARTING FPGA TOP-LEVEL WRAPPER SMOKE TEST (tb_cpu_fpga_top)");
    $display("================================================================================");

    // Apply Reset
    rst_n = 0;
    btn_trigger = 0;
    sw_mode = 2'b00; // Mode 00: 37-instruction ISA suite

    repeat (10) @(posedge clk);
    rst_n = 1;
    $display("[TB] Released reset, waiting for autonomous ISA test execution...");

    // Wait for completion of Mode 00 (37-instruction ISA test)
    timeout_cnt = 0;
    while (!led_done && timeout_cnt < 50000) begin
      @(posedge clk);
      timeout_cnt = timeout_cnt + 1;
    end

    if (!led_done) begin
      $display("[TB ERROR] Timeout waiting for led_done in Mode 00! timeout_cnt=%0d", timeout_cnt);
      $finish(1);
    end

    $display("[TB] Mode 00 Finished in %0d cycles.", timeout_cnt);
    $display("[TB] led_done = %b, led_pass = %b, led_fail = %b, led = 0x%02x (%0d)",
             led_done, led_pass, led_fail, led, led);

    if (!led_pass || led_fail || (led != 8'd37)) begin
      $display("[TB ERROR] Mode 00 (37-inst ISA) FAILED! Expected PASS with count 37.");
      $finish(1);
    end
    $display("[TB PASS] Mode 00 (37-inst ISA verification) passed cleanly on FPGA top!");

    // Test Re-trigger with Mode 01 (Addition 25 + 17 = 42)
    repeat (10) @(posedge clk);
    sw_mode = 2'b01;
    btn_trigger = 1;
    repeat (2) @(posedge clk);
    btn_trigger = 0;
    $display("[TB] Triggered button for Mode 01 (Addition 25 + 17)...");

    // Wait for handshake to acknowledge and drop led_done
    timeout_cnt = 0;
    while (led_done && timeout_cnt < 100) begin
      @(posedge clk);
      timeout_cnt = timeout_cnt + 1;
    end

    // Wait for completion of Mode 01
    timeout_cnt = 0;
    while (!led_done && timeout_cnt < 10000) begin
      @(posedge clk);
      timeout_cnt = timeout_cnt + 1;
    end

    if (!led_done) begin
      $display("[TB ERROR] Timeout waiting for led_done in Mode 01! timeout_cnt=%0d", timeout_cnt);
      $finish(1);
    end

    $display("[TB] Mode 01 Finished in %0d cycles.", timeout_cnt);
    $display("[TB] led_done = %b, led_pass = %b, led_fail = %b, led = 0x%02x (%0d)",
             led_done, led_pass, led_fail, led, led);

    if (!led_pass || led_fail || (led != 8'd42)) begin
      $display("[TB ERROR] Mode 01 (Addition) FAILED! Expected result 42.");
      $finish(1);
    end
    $display("[TB PASS] Mode 01 (Addition: 25 + 17 = 42) passed cleanly on FPGA top!");

    $display("================================================================================");
    $display("  FPGA TOP-LEVEL WRAPPER SMOKE TEST: ALL TESTS PASSED (100%% SUCCESS)");
    $display("================================================================================");
    repeat (10) @(posedge clk);
    $finish(0);
  end

endmodule
