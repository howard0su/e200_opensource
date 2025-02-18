/*
Copyright 2017 Silicon Integrated Microelectronics, Inc.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
Changelog:
  2018, Aug, Tomas Brabec
  - Modified the testbench to work with Verilator (i.e. used only synthesis
    like syntax. This also included using the same clock for `hfextclk` and
    `lfextclk`.
  - Commented out error injection.
*/

`include "e203_defines.v"

module tb_top(
        input wire  clk,
        input wire  rst_n,

        output  wire  [`E203_PC_SIZE - 1 : 0]                   peek_pc,
        output  wire  [`E203_INSTR_SIZE - 1 : 0]                peek_ir,

        output  wire                                            peek_mem_write_en,
        output  wire  [`E203_DTCM_RAM_DW - 1 : 0]               peek_mem_write_data,
        output  wire  [`E203_DTCM_RAM_AW - 1 : 0]               peek_mem_addr

  );

  `define CPU_TOP u_e203_soc_top.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top
  `define EXU `CPU_TOP.u_e203_cpu.u_e203_core.u_e203_exu
  `define ITCM `CPU_TOP.u_e203_srams.u_e203_itcm_ram.u_e203_itcm_gnrl_ram.u_sirv_sim_ram
  `define DTCM `CPU_TOP.u_e203_srams.u_e203_dtcm_ram.u_e203_dtcm_gnrl_ram.u_sirv_sim_ram


  `define DATA_WRITE_TOHOST       32'h200
    
  `define PC_EXT_IRQ_BEFOR_MRET `E203_PC_SIZE'h800000a6
  `define PC_SFT_IRQ_BEFOR_MRET `E203_PC_SIZE'h800000be
  `define PC_TMR_IRQ_BEFOR_MRET `E203_PC_SIZE'h800000d6
  `define PC_AFTER_SETMTVEC     `E203_PC_SIZE'h8000015C

  wire [`E203_XLEN-1:0] x3 = `EXU.u_e203_exu_regfile.rf_r[3];
  wire [`E203_XLEN-1:0] t0 = `EXU.u_e203_exu_regfile.rf_r[5];
  wire [`E203_XLEN-1:0] t1 = `EXU.u_e203_exu_regfile.rf_r[6];
  wire pc_vld = `EXU.u_e203_exu_commit.alu_cmt_i_valid;
  wire [`E203_PC_SIZE-1:0] pc = pc_vld?`EXU.u_e203_exu_commit.alu_cmt_i_pc:0;

  reg [31:0] pc_write_to_host_cnt;
  reg [31:0] pc_write_to_host_cycle;
  reg [31:0] valid_ir_cycle;
  reg [31:0] cycle_count;
  reg pc_write_to_host_flag;

  assign peek_pc = pc_vld?`EXU.u_e203_exu_commit.alu_cmt_i_pc:0;
  assign peek_ir = pc_vld?`EXU.u_e203_exu_commit.alu_cmt_i_instr:0;

  assign peek_mem_write_en = `CPU_TOP.u_e203_srams.u_e203_dtcm_ram.we & `CPU_TOP.u_e203_srams.u_e203_dtcm_ram.cs;
  assign peek_mem_write_data = `CPU_TOP.u_e203_srams.u_e203_dtcm_ram.din;
  assign peek_mem_addr = `CPU_TOP.u_e203_srams.u_e203_dtcm_ram.addr;


  wire itcm_write = `CPU_TOP.u_e203_srams.u_e203_itcm_ram.we & `CPU_TOP.u_e203_srams.u_e203_itcm_ram.cs;
  wire[`E203_DTCM_RAM_AW-1:0] itcm_addr = `CPU_TOP.u_e203_srams.u_e203_itcm_ram.addr;
  always @(posedge clk or negedge rst_n)
  begin 
    if(rst_n == 1'b0) begin
        pc_write_to_host_cnt <= 32'b0;
        pc_write_to_host_flag <= 1'b0;
        pc_write_to_host_cycle <= 32'b0;
    end
    else
    if (itcm_write) begin
        pc_write_to_host_cnt <= pc_write_to_host_cnt + 1'b1;
        pc_write_to_host_flag <= 1'b1;
        if (pc_write_to_host_flag == 1'b0) begin
            pc_write_to_host_cycle <= cycle_count;
        end
    end
  end

  always @(posedge clk or negedge rst_n)
  begin 
    if(rst_n == 1'b0) begin
        cycle_count <= 32'b0;
    end
    else begin
        cycle_count <= cycle_count + 1'b1;
    end
  end

  wire i_valid = `EXU.i_valid;
  wire i_ready = `EXU.i_ready;

  always @(posedge clk or negedge rst_n)
  begin 
    if(rst_n == 1'b0) begin
        valid_ir_cycle <= 32'b0;
    end
    else if(i_valid & i_ready & (pc_write_to_host_flag == 1'b0)) begin
        valid_ir_cycle <= valid_ir_cycle + 1'b1;
    end
  end

  // Randomly force the external interrupt
  `define EXT_IRQ u_e200_soc_top.u_e200_subsys_top.u_e200_subsys_main.plic_ext_irq
  `define SFT_IRQ u_e200_soc_top.u_e200_subsys_top.u_e200_subsys_main.clint_sft_irq
  `define TMR_IRQ u_e200_soc_top.u_e200_subsys_top.u_e200_subsys_main.clint_tmr_irq

  `define U_CPU u_e200_soc_top.u_e200_subsys_top.u_e200_subsys_main.u_e200_cpu_top.u_e200_cpu
  `define ITCM_BUS_ERR `U_CPU.u_e200_itcm_ctrl.sram_icb_rsp_err
  `define ITCM_BUS_READ `U_CPU.u_e200_itcm_ctrl.sram_icb_rsp_read
  `define STATUS_MIE   `U_CPU.u_e200_core.u_e200_exu.u_e200_exu_commit.u_e200_exu_excp.status_mie_r

  wire stop_assert_irq = (pc_write_to_host_cnt > 32);

  reg tb_itcm_bus_err;

  reg tb_ext_irq;
  reg tb_tmr_irq;
  reg tb_sft_irq;
  initial begin
    tb_ext_irq = 1'b0;
    tb_tmr_irq = 1'b0;
    tb_sft_irq = 1'b0;
  end

`ifdef ENABLE_TB_FORCE
  initial begin
    tb_itcm_bus_err = 1'b0;
    repeat (pc != `PC_AFTER_SETMTVEC ) begin
      // Wait the program goes out the reset_vector program
    end
    forever begin
      repeat ($urandom_range(1, 20)) @(posedge clk) tb_itcm_bus_err = 1'b0; // Wait random times
      repeat ($urandom_range(1, 200)) @(posedge clk) tb_itcm_bus_err = 1'b1; // Wait random times
      if(stop_assert_irq) begin
          break;
      end
    end
  end


  initial begin
    force `EXT_IRQ = tb_ext_irq;
    force `SFT_IRQ = tb_sft_irq;
    force `TMR_IRQ = tb_tmr_irq;
       // We force the bus-error only when:
       //   It is in common code, not in exception code, by checking MIE bit
       //   It is in read operation, not write, otherwise the test cannot recover
    force `ITCM_BUS_ERR = tb_itcm_bus_err
                        & `STATUS_MIE 
                        & `ITCM_BUS_READ
                        ;
  end


  initial begin
    #100
    repeat (pc != `PC_AFTER_SETMTVEC ) begin
      // Wait the program goes out the reset_vector program
    end
    forever begin
      repeat ($urandom_range(1, 1000)) @(posedge clk) tb_ext_irq = 1'b0; // Wait random times
      tb_ext_irq = 1'b1; // assert the irq
      @((pc == `PC_EXT_IRQ_BEFOR_MRET)) // Wait the program run into the IRQ handler by check PC values
      tb_ext_irq = 1'b0;
      if(stop_assert_irq) begin
          break;
      end
    end
  end

  initial begin
    #100
    repeat (pc != `PC_AFTER_SETMTVEC ) begin
      // Wait the program goes out the reset_vector program
    end
    forever begin
      repeat ($urandom_range(1, 1000)) @(posedge clk) tb_sft_irq = 1'b0; // Wait random times
      tb_sft_irq = 1'b1; // assert the irq
      @((pc == `PC_SFT_IRQ_BEFOR_MRET)) // Wait the program run into the IRQ handler by check PC values
      tb_sft_irq = 1'b0;
      if(stop_assert_irq) begin
          break;
      end
    end
  end

  initial begin
    #100
    repeat (pc != `PC_AFTER_SETMTVEC ) begin
      // Wait the program goes out the reset_vector program
    end
    forever begin
      repeat ($urandom_range(1, 1000)) @(posedge clk) tb_tmr_irq = 1'b0; // Wait random times
      tb_tmr_irq = 1'b1; // assert the irq
      @((pc == `PC_TMR_IRQ_BEFOR_MRET)) // Wait the program run into the IRQ handler by check PC values
      tb_tmr_irq = 1'b0;
      if(stop_assert_irq) begin
          break;
      end
    end
  end
`endif

  reg[8*200:1] testcase;
  reg[8*200:1] signature;
  integer dumpsig;
//  integer dumpwave;

  initial begin
    $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");  
    if($value$plusargs("TESTCASE=%s",testcase))begin
      $display("TESTCASE=%s",testcase);
    end
    else begin
	    $fatal(1,"No TESTCASE defined!");
	    $finish;
    end
  end

  initial begin
    if($value$plusargs("SIGNATURE=%s",signature))begin
      $display("SIGNATURE=%s",signature);
      dumpsig = 1;
    end
    else begin
	dumpsig = 0;
    end
  end

  always  @(pc_write_to_host_cnt) begin
	  if (pc_write_to_host_cnt == 32'd20) begin
`ifdef ENABLE_TB_FORCE
    @((~tb_tmr_irq) & (~tb_sft_irq) & (~tb_ext_irq)) #10 rst_n <=1;// Wait the interrupt to complete
`endif

        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~ Test Result Summary ~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~TESTCASE: %s ~~~~~~~~~~~~~", testcase);
        $display("~~~~~~~~~~~~~~Total cycle_count value: %d ~~~~~~~~~~~~~", cycle_count);
        $display("~~~~~~~~~~The valid Instruction Count: %d ~~~~~~~~~~~~~", valid_ir_cycle);
        $display("~~~~~The test ending reached at cycle: %d ~~~~~~~~~~~~~", pc_write_to_host_cycle);
        $display("~~~~~~~~~~~~~~~The final x3 Reg value: %d ~~~~~~~~~~~~~", x3);
        $display("~~~~~~~~~~~~~~~The final t0 Reg value: %x ~~~~~~~~~~~~~", t0);
        $display("~~~~~~~~~~~~~~~The final t1 Reg value: %x ~~~~~~~~~~~~~", t1);
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    if (x3 == 1) begin
        $display("~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    end
    else begin
        $display("~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    end
    if (dumpsig) begin
	    $writememh(signature, 
		    `DTCM.mem_r, 
		    (t0 & 20'hFFFFF)/4, 
		    (t1 & 20'hFFFFF)/4 - 1);
    end
    $finish;
    end
  end

  // watchdog
  always @(posedge clk) begin
    if (cycle_count[20] == 1'b1) begin
      $error("Time Out !!!");
      $finish;
    end
  end





//  initial begin
//    $value$plusargs("DUMPWAVE=%d",dumpwave);
//    if(dumpwave != 0)begin
//         // To add your waveform generation function
//    end
//  end





    integer i;

    reg [7:0] mem [0: (`E203_ITCM_RAM_DP*8) + (`E203_ITCM_RAM_DP*4)-1];

    initial begin
      $readmemh({testcase, ".verilog"}, mem);

      for (i=0;i<(`E203_ITCM_RAM_DP);i=i+1) begin
          `ITCM.mem_r[i][00+7:00] = mem[i*8+0];
          `ITCM.mem_r[i][08+7:08] = mem[i*8+1];
          `ITCM.mem_r[i][16+7:16] = mem[i*8+2];
          `ITCM.mem_r[i][24+7:24] = mem[i*8+3];
          `ITCM.mem_r[i][32+7:32] = mem[i*8+4];
          `ITCM.mem_r[i][40+7:40] = mem[i*8+5];
          `ITCM.mem_r[i][48+7:48] = mem[i*8+6];
          `ITCM.mem_r[i][56+7:56] = mem[i*8+7];
      end

        $display("ITCM 0x00: %h", `ITCM.mem_r[13'h00]);
        $display("ITCM 0x01: %h", `ITCM.mem_r[13'h01]);
        $display("ITCM 0x02: %h", `ITCM.mem_r[13'h02]);
        $display("ITCM 0x03: %h", `ITCM.mem_r[13'h03]);
        $display("ITCM 0x04: %h", `ITCM.mem_r[13'h04]);
        $display("ITCM 0x05: %h", `ITCM.mem_r[13'h05]);
        $display("ITCM 0x06: %h", `ITCM.mem_r[13'h06]);
        $display("ITCM 0x07: %h", `ITCM.mem_r[13'h07]);
        $display("ITCM 0x16: %h", `ITCM.mem_r[13'h16]);
        $display("ITCM 0x20: %h", `ITCM.mem_r[13'h20]);

      for (i=0;i<(`E203_DTCM_RAM_DP);i=i+1) begin
          `DTCM.mem_r[i][00+7:00] = mem[(`E203_ITCM_RAM_DP*8) + i*4+0];
          `DTCM.mem_r[i][08+7:08] = mem[(`E203_ITCM_RAM_DP*8) + i*4+1];
          `DTCM.mem_r[i][16+7:16] = mem[(`E203_ITCM_RAM_DP*8) + i*4+2];
          `DTCM.mem_r[i][24+7:24] = mem[(`E203_ITCM_RAM_DP*8) + i*4+3];
      end
        $display("DTCM 0x00: %h", `DTCM.mem_r[8'h00]);
        $display("DTCM 0x01: %h", `DTCM.mem_r[8'h01]);
        $display("DTCM 0x02: %h", `DTCM.mem_r[8'h02]);
        $display("DTCM 0x03: %h", `DTCM.mem_r[8'h03]);
        $display("DTCM 0x04: %h", `DTCM.mem_r[8'h04]);
        $display("DTCM 0x05: %h", `DTCM.mem_r[8'h05]);
        $display("DTCM 0x06: %h", `DTCM.mem_r[8'h06]);
        $display("DTCM 0x07: %h", `DTCM.mem_r[8'h07]);
        $display("DTCM 0x16: %h", `DTCM.mem_r[8'h16]);
        $display("DTCM 0x20: %h", `DTCM.mem_r[8'h20]);
    end 



  wire jtag_TDI = 1'b0;
  wire jtag_TDO;
  wire jtag_TCK = 1'b0;
  wire jtag_TMS = 1'b0;
  wire jtag_TRST = 1'b0;

  wire jtag_DRV_TDO = 1'b0;


e203_soc_top u_e203_soc_top(

   .hfextclk(clk),
   .hfxoscen(),

   .lfextclk(clk),
   .lfxoscen(),

   .io_pads_jtag_TCK_i_ival (jtag_TCK),
   .io_pads_jtag_TMS_i_ival (jtag_TMS),
   .io_pads_jtag_TDI_i_ival (jtag_TDI),
   .io_pads_jtag_TDO_o_oval (jtag_TDO),
   .io_pads_jtag_TDO_o_oe (),
   .io_pads_gpio_0_i_ival (1'b1),
   .io_pads_gpio_0_o_oval (),
   .io_pads_gpio_0_o_oe (),
   .io_pads_gpio_0_o_ie (),
   .io_pads_gpio_0_o_pue (),
   .io_pads_gpio_0_o_ds (),
   .io_pads_gpio_1_i_ival (1'b1),
   .io_pads_gpio_1_o_oval (),
   .io_pads_gpio_1_o_oe (),
   .io_pads_gpio_1_o_ie (),
   .io_pads_gpio_1_o_pue (),
   .io_pads_gpio_1_o_ds (),
   .io_pads_gpio_2_i_ival (1'b1),
   .io_pads_gpio_2_o_oval (),
   .io_pads_gpio_2_o_oe (),
   .io_pads_gpio_2_o_ie (),
   .io_pads_gpio_2_o_pue (),
   .io_pads_gpio_2_o_ds (),
   .io_pads_gpio_3_i_ival (1'b1),
   .io_pads_gpio_3_o_oval (),
   .io_pads_gpio_3_o_oe (),
   .io_pads_gpio_3_o_ie (),
   .io_pads_gpio_3_o_pue (),
   .io_pads_gpio_3_o_ds (),
   .io_pads_gpio_4_i_ival (1'b1),
   .io_pads_gpio_4_o_oval (),
   .io_pads_gpio_4_o_oe (),
   .io_pads_gpio_4_o_ie (),
   .io_pads_gpio_4_o_pue (),
   .io_pads_gpio_4_o_ds (),
   .io_pads_gpio_5_i_ival (1'b1),
   .io_pads_gpio_5_o_oval (),
   .io_pads_gpio_5_o_oe (),
   .io_pads_gpio_5_o_ie (),
   .io_pads_gpio_5_o_pue (),
   .io_pads_gpio_5_o_ds (),
   .io_pads_gpio_6_i_ival (1'b1),
   .io_pads_gpio_6_o_oval (),
   .io_pads_gpio_6_o_oe (),
   .io_pads_gpio_6_o_ie (),
   .io_pads_gpio_6_o_pue (),
   .io_pads_gpio_6_o_ds (),
   .io_pads_gpio_7_i_ival (1'b1),
   .io_pads_gpio_7_o_oval (),
   .io_pads_gpio_7_o_oe (),
   .io_pads_gpio_7_o_ie (),
   .io_pads_gpio_7_o_pue (),
   .io_pads_gpio_7_o_ds (),
   .io_pads_gpio_8_i_ival (1'b1),
   .io_pads_gpio_8_o_oval (),
   .io_pads_gpio_8_o_oe (),
   .io_pads_gpio_8_o_ie (),
   .io_pads_gpio_8_o_pue (),
   .io_pads_gpio_8_o_ds (),
   .io_pads_gpio_9_i_ival (1'b1),
   .io_pads_gpio_9_o_oval (),
   .io_pads_gpio_9_o_oe (),
   .io_pads_gpio_9_o_ie (),
   .io_pads_gpio_9_o_pue (),
   .io_pads_gpio_9_o_ds (),
   .io_pads_gpio_10_i_ival (1'b1),
   .io_pads_gpio_10_o_oval (),
   .io_pads_gpio_10_o_oe (),
   .io_pads_gpio_10_o_ie (),
   .io_pads_gpio_10_o_pue (),
   .io_pads_gpio_10_o_ds (),
   .io_pads_gpio_11_i_ival (1'b1),
   .io_pads_gpio_11_o_oval (),
   .io_pads_gpio_11_o_oe (),
   .io_pads_gpio_11_o_ie (),
   .io_pads_gpio_11_o_pue (),
   .io_pads_gpio_11_o_ds (),
   .io_pads_gpio_12_i_ival (1'b1),
   .io_pads_gpio_12_o_oval (),
   .io_pads_gpio_12_o_oe (),
   .io_pads_gpio_12_o_ie (),
   .io_pads_gpio_12_o_pue (),
   .io_pads_gpio_12_o_ds (),
   .io_pads_gpio_13_i_ival (1'b1),
   .io_pads_gpio_13_o_oval (),
   .io_pads_gpio_13_o_oe (),
   .io_pads_gpio_13_o_ie (),
   .io_pads_gpio_13_o_pue (),
   .io_pads_gpio_13_o_ds (),
   .io_pads_gpio_14_i_ival (1'b1),
   .io_pads_gpio_14_o_oval (),
   .io_pads_gpio_14_o_oe (),
   .io_pads_gpio_14_o_ie (),
   .io_pads_gpio_14_o_pue (),
   .io_pads_gpio_14_o_ds (),
   .io_pads_gpio_15_i_ival (1'b1),
   .io_pads_gpio_15_o_oval (),
   .io_pads_gpio_15_o_oe (),
   .io_pads_gpio_15_o_ie (),
   .io_pads_gpio_15_o_pue (),
   .io_pads_gpio_15_o_ds (),
   .io_pads_gpio_16_i_ival (1'b1),
   .io_pads_gpio_16_o_oval (),
   .io_pads_gpio_16_o_oe (),
   .io_pads_gpio_16_o_ie (),
   .io_pads_gpio_16_o_pue (),
   .io_pads_gpio_16_o_ds (),
   .io_pads_gpio_17_i_ival (1'b1),
   .io_pads_gpio_17_o_oval (),
   .io_pads_gpio_17_o_oe (),
   .io_pads_gpio_17_o_ie (),
   .io_pads_gpio_17_o_pue (),
   .io_pads_gpio_17_o_ds (),
   .io_pads_gpio_18_i_ival (1'b1),
   .io_pads_gpio_18_o_oval (),
   .io_pads_gpio_18_o_oe (),
   .io_pads_gpio_18_o_ie (),
   .io_pads_gpio_18_o_pue (),
   .io_pads_gpio_18_o_ds (),
   .io_pads_gpio_19_i_ival (1'b1),
   .io_pads_gpio_19_o_oval (),
   .io_pads_gpio_19_o_oe (),
   .io_pads_gpio_19_o_ie (),
   .io_pads_gpio_19_o_pue (),
   .io_pads_gpio_19_o_ds (),
   .io_pads_gpio_20_i_ival (1'b1),
   .io_pads_gpio_20_o_oval (),
   .io_pads_gpio_20_o_oe (),
   .io_pads_gpio_20_o_ie (),
   .io_pads_gpio_20_o_pue (),
   .io_pads_gpio_20_o_ds (),
   .io_pads_gpio_21_i_ival (1'b1),
   .io_pads_gpio_21_o_oval (),
   .io_pads_gpio_21_o_oe (),
   .io_pads_gpio_21_o_ie (),
   .io_pads_gpio_21_o_pue (),
   .io_pads_gpio_21_o_ds (),
   .io_pads_gpio_22_i_ival (1'b1),
   .io_pads_gpio_22_o_oval (),
   .io_pads_gpio_22_o_oe (),
   .io_pads_gpio_22_o_ie (),
   .io_pads_gpio_22_o_pue (),
   .io_pads_gpio_22_o_ds (),
   .io_pads_gpio_23_i_ival (1'b1),
   .io_pads_gpio_23_o_oval (),
   .io_pads_gpio_23_o_oe (),
   .io_pads_gpio_23_o_ie (),
   .io_pads_gpio_23_o_pue (),
   .io_pads_gpio_23_o_ds (),
   .io_pads_gpio_24_i_ival (1'b1),
   .io_pads_gpio_24_o_oval (),
   .io_pads_gpio_24_o_oe (),
   .io_pads_gpio_24_o_ie (),
   .io_pads_gpio_24_o_pue (),
   .io_pads_gpio_24_o_ds (),
   .io_pads_gpio_25_i_ival (1'b1),
   .io_pads_gpio_25_o_oval (),
   .io_pads_gpio_25_o_oe (),
   .io_pads_gpio_25_o_ie (),
   .io_pads_gpio_25_o_pue (),
   .io_pads_gpio_25_o_ds (),
   .io_pads_gpio_26_i_ival (1'b1),
   .io_pads_gpio_26_o_oval (),
   .io_pads_gpio_26_o_oe (),
   .io_pads_gpio_26_o_ie (),
   .io_pads_gpio_26_o_pue (),
   .io_pads_gpio_26_o_ds (),
   .io_pads_gpio_27_i_ival (1'b1),
   .io_pads_gpio_27_o_oval (),
   .io_pads_gpio_27_o_oe (),
   .io_pads_gpio_27_o_ie (),
   .io_pads_gpio_27_o_pue (),
   .io_pads_gpio_27_o_ds (),
   .io_pads_gpio_28_i_ival (1'b1),
   .io_pads_gpio_28_o_oval (),
   .io_pads_gpio_28_o_oe (),
   .io_pads_gpio_28_o_ie (),
   .io_pads_gpio_28_o_pue (),
   .io_pads_gpio_28_o_ds (),
   .io_pads_gpio_29_i_ival (1'b1),
   .io_pads_gpio_29_o_oval (),
   .io_pads_gpio_29_o_oe (),
   .io_pads_gpio_29_o_ie (),
   .io_pads_gpio_29_o_pue (),
   .io_pads_gpio_29_o_ds (),
   .io_pads_gpio_30_i_ival (1'b1),
   .io_pads_gpio_30_o_oval (),
   .io_pads_gpio_30_o_oe (),
   .io_pads_gpio_30_o_ie (),
   .io_pads_gpio_30_o_pue (),
   .io_pads_gpio_30_o_ds (),
   .io_pads_gpio_31_i_ival (1'b1),
   .io_pads_gpio_31_o_oval (),
   .io_pads_gpio_31_o_oe (),
   .io_pads_gpio_31_o_ie (),
   .io_pads_gpio_31_o_pue (),
   .io_pads_gpio_31_o_ds (),

   .io_pads_qspi_sck_o_oval (),
   .io_pads_qspi_dq_0_i_ival (1'b1),
   .io_pads_qspi_dq_0_o_oval (),
   .io_pads_qspi_dq_0_o_oe (),
   .io_pads_qspi_dq_0_o_ie (),
   .io_pads_qspi_dq_0_o_pue (),
   .io_pads_qspi_dq_0_o_ds (),
   .io_pads_qspi_dq_1_i_ival (1'b1),
   .io_pads_qspi_dq_1_o_oval (),
   .io_pads_qspi_dq_1_o_oe (),
   .io_pads_qspi_dq_1_o_ie (),
   .io_pads_qspi_dq_1_o_pue (),
   .io_pads_qspi_dq_1_o_ds (),
   .io_pads_qspi_dq_2_i_ival (1'b1),
   .io_pads_qspi_dq_2_o_oval (),
   .io_pads_qspi_dq_2_o_oe (),
   .io_pads_qspi_dq_2_o_ie (),
   .io_pads_qspi_dq_2_o_pue (),
   .io_pads_qspi_dq_2_o_ds (),
   .io_pads_qspi_dq_3_i_ival (1'b1),
   .io_pads_qspi_dq_3_o_oval (),
   .io_pads_qspi_dq_3_o_oe (),
   .io_pads_qspi_dq_3_o_ie (),
   .io_pads_qspi_dq_3_o_pue (),
   .io_pads_qspi_dq_3_o_ds (),
   .io_pads_qspi_cs_0_o_oval (),
   .io_pads_aon_erst_n_i_ival (rst_n),//This is the real reset, active low
   .io_pads_aon_pmu_dwakeup_n_i_ival (1'b1),

   .io_pads_aon_pmu_vddpaden_o_oval (),
    .io_pads_aon_pmu_padrst_o_oval    (),

    .io_pads_bootrom_n_i_ival       (1'b0),// In Simulation we boot from ROM
    .io_pads_dbgmode0_n_i_ival       (1'b1),
    .io_pads_dbgmode1_n_i_ival       (1'b1),
    .io_pads_dbgmode2_n_i_ival       (1'b1) 
);


endmodule
