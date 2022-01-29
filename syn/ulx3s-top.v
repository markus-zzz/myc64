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

module ulx3s_top(
  input clk_25mhz,
  input [6:0] btn,
  output [7:0] led,
  inout [27:0] gp,
  inout [27:0] gn,
  inout usb_fpga_bd_dp,
  inout usb_fpga_bd_dn,
  output usb_fpga_pu_dp,
  output usb_fpga_pu_dn,
  output [3:0] audio_l,
  output [3:0] gpdi_dp, gpdi_dn,
  output wifi_gpio0,
  output sdram_clk,
  output sdram_cke,
  output sdram_csn,
  output sdram_wen,
  output sdram_rasn,
  output sdram_casn,
  output [12:0] sdram_a,
  output [1:0] sdram_ba,
  output [1:0] sdram_dqm,
  inout [15:0] sdram_d
);

  assign wifi_gpio0 = 1'b1; // This has something to do with GPDI pins if IRC.

  wire clk_pll_0_15mhz;
  wire clk_pll_1_25mhz;
  wire clk_pll_1_125mhz;
  wire pll_0_locked;
  wire pll_1_locked;

  pll u_pll_0(
    .clkin(clk_25mhz),
    .clkout0(clk_pll_0_15mhz)
  );

  clk_25_250_125_25 u_pll_1(
    .clki(clk_25mhz),
    .clks1(clk_pll_1_125mhz),
    .clks2(clk_pll_1_25mhz),
    .locked(pll_1_locked)
  );

  assign pll_0_locked = pll_1_locked;

  // XXX: Wait until all PLLs are locked the sample reset signal in appropriate
  // clock domains.

  wire sdram_dq_oe;
  wire [15:0] sdram_dq_o;
  assign sdram_d = sdram_dq_oe ? sdram_dq_o : 16'hZZZZ;

  wire rst_async;
  assign rst_async = btn[6];
  reg [1:0] rst_async_p;
  reg rst_async_db;
  reg [31:0] rst_db_cntr;
  always @(posedge clk_25mhz) begin
    rst_async_p <= {rst_async_p[0], rst_async};
    if (rst_async_p[1]) begin
      rst_async_db <= 1;
      rst_db_cntr <= 32'd25_000_000;
    end
    else if (rst_db_cntr == 0) begin
      rst_async_db <= 0;
    end

    if (rst_db_cntr != 0) begin
      rst_db_cntr <= rst_db_cntr - 1;
    end
  end

  reg [1:0] rst_15mhz_p;
  always @(posedge clk_pll_0_15mhz) begin
    rst_15mhz_p <= {rst_15mhz_p[0], rst_async_db};
  end
  reg [1:0] rst_25mhz_p;
  always @(posedge clk_pll_1_25mhz) begin
    rst_25mhz_p <= {rst_25mhz_p[0], rst_async_db};
  end
  reg [1:0] rst_125mhz_p;
  always @(posedge clk_pll_1_125mhz) begin
    rst_125mhz_p <= {rst_125mhz_p[0], rst_async_db};
  end

  myc64_soc_top u_myc64_soc_top(
    .clk_15mhz(clk_pll_0_15mhz),
    .rst_15mhz(rst_15mhz_p[1]),
    .clk_25mhz(clk_pll_1_25mhz),
    .rst_25mhz(rst_25mhz_p[1]),
    .clk_125mhz(clk_pll_1_125mhz),
    .rst_125mhz(rst_125mhz_p[1]),
    .led(led),
    .gp(gp),
    .gn(gn),
    .usb_fpga_bd_dp(usb_fpga_bd_dp),
    .usb_fpga_bd_dn(usb_fpga_bd_dn),
    .usb_fpga_pu_dp(usb_fpga_pu_dp),
    .usb_fpga_pu_dn(usb_fpga_pu_dn),
    .audio_l(audio_l),
    .gpdi_dp(gpdi_dp),
    .gpdi_dn(gpdi_dn),
    .o_sdram_clk(sdram_clk),
    .o_sdram_cke(sdram_cke),
    .o_sdram_csn(sdram_csn),
    .o_sdram_wen(sdram_wen),
    .o_sdram_rasn(sdram_rasn),
    .o_sdram_casn(sdram_casn),
    .o_sdram_a(sdram_a),
    .o_sdram_ba(sdram_ba),
    .o_sdram_dqm(sdram_dqm),
    .o_sdram_dq_oe(sdram_dq_oe),
    .o_sdram_dq(sdram_dq_o),
    .i_sdram_dq(sdram_d),
    .o_sid_wave(sid_wave),
    .o_port_2(port_2),
    .o_port_3(port_3)
  );


  wire LRCLK;
  wire BCLK;
  wire SDIN;
  wire MCLK;

  wire [15:0] sid_wave;
  wire [31:0] port_2, port_3;

  assign gn[26] = LRCLK;
  assign gn[25] = BCLK;
  assign gn[24] = SDIN;
  assign gn[23] = MCLK;

  // SCL
  assign gp[27] = port_2[0] ? 1'bz : 1'b0;
  // SDA
  assign gn[27] = port_3[0] ? 1'bz : 1'b0;

  wire clk25mhz;
  wire i_rst;
  reg [10:0] clk_cntr;

  assign clk25mhz = clk_25mhz;
  assign i_rst = rst_async;

  always @(posedge clk25mhz) begin
    if (i_rst)
      clk_cntr <= 0;
    else
      clk_cntr <= clk_cntr + 1;
  end

  assign MCLK = clk_cntr[0]; // 12.5MHz
  assign LRCLK = clk_cntr[8]; // 48.8kHz
  assign BCLK = clk_cntr[3]; // 1.5625MHz

  reg prev_lrclk;
  always @(posedge clk25mhz) begin
    if (i_rst)
      prev_lrclk <= 0;
    else
      prev_lrclk <= LRCLK;
  end

  reg prev_bclk;
  always @(posedge clk25mhz) begin
    if (i_rst)
      prev_bclk <= 0;
    else
      prev_bclk <= BCLK;
  end

  reg [15:0] shift;
  always @(posedge clk25mhz) begin
    if (i_rst)
      shift <= 0;
    else if (~prev_lrclk & LRCLK)
      shift <= sid_wave;
    else if (prev_lrclk & ~LRCLK)
      shift <= sid_wave;
    else if (~prev_bclk & BCLK)
      shift <= {shift[14:0], 1'b0};
  end

  assign SDIN = shift[15];

endmodule
