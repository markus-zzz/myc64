/*
 * Copyright (C) 2020 Markus Lavin (https://www.zzzconsulting.se/)
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

// http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt
// Type: 6569 (PAL-B)

module vic_ii(
  input clk,
  input rst,
  input clk_8mhz_en,
  input clk_1mhz_ph1_en,
  input clk_1mhz_ph2_en,
  output [15:0] o_addr_ph1,
  input [11:0] i_data_ph1,
  output [15:0] o_addr_ph2, // XXX: Should be 14 bits, remaining two come from CIA
  input [11:0] i_data_ph2,
  input [5:0] i_reg_addr,
  input i_reg_cs,
  input i_reg_we,
  input [7:0] i_reg_data,
  output reg [7:0] o_reg_data,
  output BA,
  output BM,
  output reg [23:0] o_pixel,
  output o_hsync,
  output o_vsync
);

  parameter p_x_raster_last = 9'h190,
            p_cycle_first_disp = 6'd15;
  reg [8:0] X; // 0-0x1f7
  reg [8:0] Y; // 0-311

  reg [9:0] VC, VCBASE;
  reg [2:0] RC;

  reg [11:0] VML[39:0];
  reg [5:0] VMLI;

  reg [5:0] CYCLE;

  wire [8:0] RASTER;
  assign RASTER = Y;

  wire [2:0] YSCROLL;
  assign YSCROLL = 0;

  wire BAD_LINE_COND;
  assign BAD_LINE_COND = RASTER >= 9'h30 && RASTER <= 9'hf7 && RASTER[2:0] == YSCROLL;

  // X and Y counters with wrap logic.
  always @(posedge clk) begin
    if (rst) begin
      X <= 0;
    end
    else if (clk_8mhz_en) begin
      if (X == 9'h1f7) X <= 9'h0;
      else X <= X + 9'h1;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      Y <= 0;
    end
    else if (clk_8mhz_en) begin
      if (X == p_x_raster_last) begin
        if (Y == 9'd311) Y <= 9'd0;
        else Y <= Y + 9'd1;
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      CYCLE <= 0;
    end
    else if (clk_8mhz_en) begin
      if (X == p_x_raster_last)
        CYCLE <= 1;
      else if (clk_1mhz_ph2_en)
        CYCLE <= CYCLE + 1;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      RC <= 0;
    end
    else if (clk_1mhz_ph2_en) begin
      if (CYCLE == 14) begin
        if (BAD_LINE_COND) RC <= 0;
      end
      else if (CYCLE == 58) RC <= RC + 1;
    end
  end

  assign o_addr_ph2 = {2'b00, r_d018[3:1], BAD_LINE_COND ? i_data_ph1[7:0] : VML[VMLI][7:0], RC[2:0]};
  reg [3:0] fgcolor, fgcolor_1;

  always @(posedge clk) begin
    if (clk_1mhz_ph2_en) begin
      fgcolor_1 <= VML[VMLI][11:8];
      fgcolor <= BAD_LINE_COND ? i_data_ph1[11:8] : fgcolor_1;
    end
  end

  reg [7:0] pixshift;
  always @(posedge clk) begin
    if (clk_1mhz_ph2_en) pixshift <= i_data_ph2[7:0];
    else if (clk_8mhz_en) pixshift <= {pixshift[6:0], 1'b0};
  end

  assign o_hsync = X == p_x_raster_last;
  assign o_vsync = RASTER == 0 && o_hsync;

  always @(posedge clk) begin
    if (clk_1mhz_ph1_en) begin
      if (CYCLE == 1)
        VMLI <= 0;
      else if (CYCLE >= p_cycle_first_disp - 1)
        VMLI <= VMLI + 1;
    end
  end

  always @(posedge clk) begin
    if (clk_1mhz_ph1_en && BAD_LINE_COND)
      VML[VMLI] <= i_data_ph1;
  end

  always @(posedge clk) begin
    if (clk_1mhz_ph1_en) begin
      if (RASTER == 9'h0)
        VCBASE <= 0;
      else if (CYCLE == 58 && RC == 0)
        VCBASE <= VC;
    end
  end

  always @(posedge clk) begin
    if (clk_1mhz_ph1_en) begin
      if (RASTER == 0)
        VC <= 0;
      else if (CYCLE >= p_cycle_first_disp - 1 && CYCLE < p_cycle_first_disp + 40 - 1 && RASTER >= 9'h30 && RASTER <= 9'hf7 && RC == 0)
        VC <= VC + 1;
    end
  end

  assign o_addr_ph1 = {6'b0000_01, VC}; // Video Matrix at 0x400

  reg [3:0] color;
  always @* begin
    color = r_d020; // Border color.
    if (CYCLE >= p_cycle_first_disp && CYCLE < p_cycle_first_disp + 40 && RASTER >= 9'h30 && RASTER <= 9'hf7)
      color = pixshift[7] ? fgcolor : r_d021;
  end

  always @* begin
   case (color)
   4'h0: o_pixel = 24'h_00_00_00;
   4'h1: o_pixel = 24'h_ff_ff_ff;
   4'h2: o_pixel = 24'h_88_00_00;
   4'h3: o_pixel = 24'h_aa_ff_ee;
   4'h4: o_pixel = 24'h_cc_44_cc;
   4'h5: o_pixel = 24'h_00_cc_55;
   4'h6: o_pixel = 24'h_00_00_aa;
   4'h7: o_pixel = 24'h_ee_ee_77;
   4'h8: o_pixel = 24'h_dd_88_55;
   4'h9: o_pixel = 24'h_66_44_00;
   4'ha: o_pixel = 24'h_ff_77_77;
   4'hb: o_pixel = 24'h_33_33_33;
   4'hc: o_pixel = 24'h_77_77_77;
   4'hd: o_pixel = 24'h_aa_ff_66;
   4'he: o_pixel = 24'h_00_88_ff;
   4'hf: o_pixel = 24'h_bb_bb_bb;
   endcase
  end

  assign BA = !(BAD_LINE_COND && CYCLE >= p_cycle_first_disp - 3 && CYCLE < p_cycle_first_disp + 40 + 3);
  assign BM = !(BAD_LINE_COND && CYCLE >= p_cycle_first_disp - 2 && CYCLE < p_cycle_first_disp + 40 + 2);

  reg [7:0] r_d018; // Memory setup.
  reg [3:0] r_d020; // Border color.
  reg [3:0] r_d021; // Background color.

  always @(posedge clk) begin
    if (rst) begin
      r_d020 <= 0;
      r_d021 <= 0;
    end
    else if (clk_1mhz_ph1_en & i_reg_cs & i_reg_we) begin
      //$display("VICII[%h]=%h(%b)", i_reg_addr, i_reg_data, i_reg_data);
      case (i_reg_addr)
        6'h18: r_d018 <= i_reg_data[7:0];
        6'h20: r_d020 <= i_reg_data[3:0];
        6'h21: r_d021 <= i_reg_data[3:0];
        default: /* do nothing */;
      endcase
    end
  end

  always @* begin
    case (i_reg_addr)
      6'h12: o_reg_data = RASTER[7:0];
      6'h18: o_reg_data = r_d018;
      6'h20: o_reg_data = {4'h0, r_d020};
      6'h21: o_reg_data = {4'h0, r_d021};
      default: o_reg_data = 8'h0;
    endcase
  end

endmodule
