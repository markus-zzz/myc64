/*
 * Copyright (C) 2019-2020 Markus Lavin (https://www.zzzconsulting.se/)
 *
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */

`default_nettype none

module myc64_soc_top(
  input clk_15mhz,
  input rst_15mhz,
  input clk_25mhz,
  input rst_25mhz,
  input clk_125mhz,
  input rst_125mhz,
  output [7:0] led,
  inout [27:0] gp,
  inout [27:0] gn,
  inout usb_fpga_bd_dp,
  inout usb_fpga_bd_dn,
  output usb_fpga_pu_dp,
  output usb_fpga_pu_dn,
  output [3:0] audio_l,
  output [3:0] gpdi_dp, gpdi_dn,
  output o_sdram_clk,
  output o_sdram_cke,
  output o_sdram_csn,
  output o_sdram_wen,
  output o_sdram_rasn,
  output o_sdram_casn,
  output [12:0] o_sdram_a,
  output [1:0] o_sdram_ba,
  output [1:0] o_sdram_dqm,
  output o_sdram_dq_oe,
  output [15:0] o_sdram_dq,
  input [15:0] i_sdram_dq,
  output o_vga_vsync,
  output o_vga_hsync,
  output o_vga_blank,
  output [23:0] o_vga_color_rgb,
  output [15:0] o_sid_wave,
  output [31:0] o_port_2,
  output [31:0] o_port_3
);
  assign usb_fpga_pu_dp = 1'b0;
  assign led[7:0] = keyb_matrix_0[7:0];

  reg [1:0] pipe;

  assign gp[21] = pipe[0];
  assign gn[21] = pipe[1];

  wire usb_oe, usb_out_j_not_k, usb_out_se0;

  // XXX: Need to deal with possible metastability of async inputs by double flopping.

  // XXX: This does not look like we are using the differential IO capabilities
  // of the ECP5. Give it another try and upgrade SymbiFlow tools if it still
  // does not work.

  assign usb_fpga_bd_dp = usb_oe ? (usb_out_se0 ? 1'b0 : ~usb_out_j_not_k) : 1'bz; // low-speed
  assign usb_fpga_bd_dn = usb_oe ? (usb_out_se0 ? 1'b0 :  usb_out_j_not_k) : 1'bz;

  always @(posedge clk_25mhz)
    pipe <= {usb_fpga_bd_dp, usb_fpga_bd_dn};

  wire [31:0] keyb_matrix_0, keyb_matrix_1;
  wire [15:0] ext_addr;
  wire [7:0] ext_data;
  wire ext_valid, ext_wstrb, ext_ready;
  soc_top u_soc(
    .i_rst(rst_15mhz),
    .i_clk(clk_15mhz),
    .i_usb_j_not_k(usb_fpga_bd_dn), // low-speed
    .i_usb_se0(usb_fpga_bd_dp ~| usb_fpga_bd_dn),
    .o_usb_oe(usb_oe),
    .o_usb_j_not_k(usb_out_j_not_k),
    .o_usb_se0(usb_out_se0),
    .o_usb_attach(usb_fpga_pu_dn),
    .o_port_0(keyb_matrix_0),
    .o_port_1(keyb_matrix_1),
    .o_port_2(o_port_2),
    .o_port_3(o_port_3),
    .o_ext_addr(ext_addr),
    .o_ext_data(ext_data),
    .o_ext_valid(ext_valid),
    .o_ext_wstrb(ext_wstrb),
    .i_ext_ready(ext_ready),
    .test_out(gp[22])
  );

  wire [3:0] color_idx;
  wire hsync /* verilator public */;
  wire vsync /* verilator public */;
  wire [23:0] c64_color_rgb /* verilator public */;

  myc64_top u_myc64(
    .rst(rst_15mhz),
    .clk(clk_15mhz),
    .o_color_rgb(c64_color_rgb),
    .o_color_idx(color_idx_c64),
    .o_hsync(hsync),
    .o_vsync(vsync),
    .o_wave(o_sid_wave),
    .i_keyboard_mask({keyb_matrix_1, keyb_matrix_0}), //XXX: Metastabiliy
    .i_ext_addr(ext_addr),
    .i_ext_data(ext_data),
    .i_ext_we(ext_valid & ext_wstrb),
    .o_ext_ready(ext_ready)
  );

///////////////
///////////////
///////////////

  wire vga_vsync, vga_hsync, vga_blank;
  wire [9:0] vga_hpos;
  wire [9:0] vga_vpos;

  wire [3:0] color_idx_c64;
  reg [3:0] color_idx_c64_r;
  reg [23:0] color_rgb;

`ifndef VERILATOR
  // VGA to digital video converter
  wire [1:0] tmds[3:0];
  vga2dvid u_vga2dvid(
    .clk_pixel(clk_25mhz),
    .clk_shift(clk_125mhz),
    .in_color(vga_c64_active ? color_rgb : 24'h0),
    .in_hsync(vga_hsync),
    .in_vsync(vga_vsync),
    .in_blank(vga_blank),
    .out_clock(tmds[3]),
    .out_red(tmds[2]),
    .out_green(tmds[1]),
    .out_blue(tmds[0]),
    .resetn(~rst_125mhz),
  );

  fake_differential u_fake_diff(
    .clk_shift(clk_125mhz),
    .in_clock(tmds[3]),
    .in_red(tmds[2]),
    .in_green(tmds[1]),
    .in_blue(tmds[0]),
    .out_p(gpdi_dp),
    .out_n(gpdi_dn)
  );
`endif

  vga_video u_vga_video(
    .clk(clk_25mhz),
    .resetn(~rst_25mhz),
    .vga_hsync(vga_hsync),
    .vga_vsync(vga_vsync),
    .vga_blank(vga_blank),
    .h_pos(vga_hpos),
    .v_pos(vga_vpos)
  );

  assign o_sdram_clk = clk_125mhz;
  assign o_sdram_csn = 1'b0;

  reg [1:0] wcntr;
  always @(posedge clk_15mhz) begin
    if (vsync)
      wcntr <= 0;
    else
      wcntr <= wcntr + 1;
  end

  reg [15:0] wcolors;
  always @(posedge clk_15mhz) begin
    color_idx_c64_r <= color_idx_c64;
    wcolors[wcntr[1:0]*4+:4] <= color_idx_c64_r;
  end


  reg [1:0] rcntr;
  always @(posedge clk_25mhz) begin
    if (rst_25mhz || ~vga_vsync)
      rcntr <= 0;
    else if (vga_c64_active)
      rcntr <= rcntr + 1;
  end

  wire [15:0] rcolors;
  wire [15:0] sdram_rdata, sdram_wdata;
  wire wfifo_empty, wfifo_full, rfifo_empty, rfifo_full;
  wire sdram_rdata_valid;

  reg [15:0] sdram_wdata_r;
  reg [1:0] wstate;
  always @(posedge clk_125mhz) begin
    if (rst_125mhz || vsync_pp) begin
      wstate <= 2'h0;
    end
    else begin
      case (wstate)
      2'h0: begin
        if (~wfifo_empty) begin
          sdram_wdata_r <= sdram_wdata;
          wstate <= 2'h1;
        end
      end
      2'h1: begin
        if (sdram_wgnt) begin
          wstate <= 2'h0;
        end
      end
      2'h2: begin
      end
      2'h3: begin
      end
      endcase
    end
  end

  afifo #(
    .ASIZE(2),
    .DSIZE(16)
  ) u_wfifo(
    .i_wclk(clk_15mhz),
    .i_wrst_n(~rst_15mhz),
    .i_wr(~wfifo_full && wcntr == 0),
    .i_wdata(wcolors),
    .o_wfull(wfifo_full),
		.i_rclk(clk_125mhz),
    .i_rrst_n(~rst_125mhz),
    .i_rd(~wfifo_empty & wstate == 2'h0),
    .o_rdata(sdram_wdata),
    .o_rempty(wfifo_empty)
  );

  reg [1:0] rstate;
  always @(posedge clk_125mhz) begin
    if (rst_125mhz || ~vga_vsync_pp) begin
      rstate <= 2'h0;
    end
    else begin
      case (rstate)
      2'h0: begin
        if (~rfifo_full) begin
          rstate <= 2'h1;
        end
      end
      2'h1: begin
        if (sdram_rgnt) begin
          rstate <= 2'h2;
        end
      end
      2'h2: begin
        if (sdram_rdata_valid) begin
          rstate <= 2'h0;
        end
      end
      2'h3: begin
      end
      endcase
    end
  end

  afifo #(
    .ASIZE(2),
    .DSIZE(16)
  ) u_rfifo(
    .i_wclk(clk_125mhz),
    .i_wrst_n(~(rst_125mhz | ~vga_vsync_pp)),
    .i_wr(sdram_rdata_valid),
    .i_wdata(sdram_rdata),
    .o_wfull(rfifo_full),
		.i_rclk(clk_25mhz),
    .i_rrst_n(~(rst_25mhz | ~vga_vsync)),
    .i_rd(~rfifo_empty && rcntr == 3 && vga_c64_active),
    .o_rdata(rcolors),
    .o_rempty(rfifo_empty)
  );

  // Full C64 screen is 504x312 pixels.
  localparam hborder_width = (640-504)/2,
             vborder_width = (480-312)/2;
  wire vga_c64_active;
  assign vga_c64_active = vga_hpos > hborder_width && vga_hpos <= 640 - hborder_width && vga_vpos > vborder_width && vga_vpos <= 480 - vborder_width;

  reg vga_vsync_p, vga_vsync_pp;
  always @(posedge clk_125mhz) begin
    vga_vsync_p <= vga_vsync;
    vga_vsync_pp <= vga_vsync_p;
  end
  reg vsync_p, vsync_pp;
  always @(posedge clk_125mhz) begin
    vsync_p <= vsync;
    vsync_pp <= vsync_p;
  end

  reg [15:0] sdram_raddr, sdram_waddr;
  wire sdram_rgnt, sdram_wgnt;
  always @(posedge clk_125mhz) begin
    if (rst_125mhz || ~vga_vsync_pp)
      sdram_raddr <= 0;
    else if (sdram_rgnt)
      sdram_raddr <= sdram_raddr + 1;
  end
  always @(posedge clk_125mhz) begin
    if (rst_125mhz || vsync_pp)
      sdram_waddr <= 0;
    else if (sdram_wgnt)
      sdram_waddr <= sdram_waddr + 1;
  end

  SDRAM_ctrl u_sdram(
    .clk(clk_125mhz),
    .rst(rst_125mhz),
    // read agent
    .RdReq(rstate == 2'h1),
    .RdGnt(sdram_rgnt),
    .RdAddr(sdram_raddr),
    .RdData(sdram_rdata),
    .RdDataValid(sdram_rdata_valid),

    // write agent
    .WrReq(wstate == 2'h1),
    .WrGnt(sdram_wgnt),
    .WrAddr(sdram_waddr),
    .WrData(sdram_wdata_r),

    // SDRAM
    .SDRAM_CKE(o_sdram_cke),
    .SDRAM_WEn(o_sdram_wen),
    .SDRAM_CASn(o_sdram_casn),
    .SDRAM_RASn(o_sdram_rasn),
    .SDRAM_A(o_sdram_a),
    .SDRAM_BA(o_sdram_ba),
    .SDRAM_DQM(o_sdram_dqm),
`ifdef VERILATOR
    .i_SDRAM_DQ(sdram_rdata_p),
`else
    .i_SDRAM_DQ(i_sdram_dq),
`endif
    .o_SDRAM_DQ(o_sdram_dq),
    .o_SDRAM_DQ_OE(o_sdram_dq_oe)
  );

  // Map color index to RGB.
  always @* begin
   case (rcolors[rcntr[1:0]*4+:4])
   4'h0: color_rgb = 24'h00_00_00;
   4'h1: color_rgb = 24'hff_ff_ff;
   4'h2: color_rgb = 24'h88_00_00;
   4'h3: color_rgb = 24'haa_ff_ee;
   4'h4: color_rgb = 24'hcc_44_cc;
   4'h5: color_rgb = 24'h00_cc_55;
   4'h6: color_rgb = 24'h00_00_aa;
   4'h7: color_rgb = 24'hee_ee_77;
   4'h8: color_rgb = 24'hdd_88_55;
   4'h9: color_rgb = 24'h66_44_00;
   4'ha: color_rgb = 24'hff_77_77;
   4'hb: color_rgb = 24'h33_33_33;
   4'hc: color_rgb = 24'h77_77_77;
   4'hd: color_rgb = 24'haa_ff_66;
   4'he: color_rgb = 24'h00_88_ff;
   4'hf: color_rgb = 24'hbb_bb_bb;
   endcase
  end

`ifdef VERILATOR
  assign o_vga_vsync = vga_vsync;
  assign o_vga_hsync = vga_hsync;
  assign o_vga_blank = vga_blank;
  assign o_vga_color_rgb = color_rgb;

  //
  // Dummy SDRAM
  //
  localparam [2:0] SDRAM_CMD_LOADMODE  = 3'b000;
  localparam [2:0] SDRAM_CMD_REFRESH   = 3'b001;
  localparam [2:0] SDRAM_CMD_PRECHARGE = 3'b010;
  localparam [2:0] SDRAM_CMD_ACTIVE    = 3'b011;
  localparam [2:0] SDRAM_CMD_WRITE     = 3'b100;
  localparam [2:0] SDRAM_CMD_READ      = 3'b101;
  localparam [2:0] SDRAM_CMD_NOP       = 3'b111;

  reg [7:0] sdram_row;
  reg [7:0] sdram_col;
  reg [15:0] mem[0:16'hffff] /* verilator public */;
  reg [15:0] sdram_rdata_p;

  always @(posedge clk_125mhz) begin
    sdram_rdata_p <= mem[{sdram_row, sdram_col}];
  end

  always @(posedge clk_125mhz) begin
    case ({o_sdram_rasn, o_sdram_casn, o_sdram_wen})
    SDRAM_CMD_ACTIVE: begin
      sdram_row <= o_sdram_a[7:0];
    end
    SDRAM_CMD_WRITE: begin
      sdram_col <= o_sdram_a[7:0];
      mem[{sdram_row, o_sdram_a[7:0]}] <= o_sdram_dq;
    end
    SDRAM_CMD_READ: begin
      sdram_col <= o_sdram_a[7:0];
    end
    endcase
  end
`endif

endmodule
