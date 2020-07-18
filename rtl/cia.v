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

// http://archive.6502.org/datasheets/mos_6526_cia_recreated.pdf

// XXX: Lots of stuff missing here!

module cia(
  input clk,
  input rst,
  input clk_1mhz_ph1_en,
  input i_cs,
  input [3:0] i_addr,
  input i_we,
  input [7:0] i_data,
  output reg [7:0] o_data,
  output reg [7:0] o_pa,
  input [7:0] i_pb,
  output reg o_irq
);

  reg [15:0] timer_a_cntr;
  reg [7:0] timer_a_lo_latch;
  reg [7:0] timer_a_hi_latch;

  reg timer_a_start;
  reg timer_a_runmode;
  reg timer_a_load;

  always @(posedge clk) begin
    if (rst) begin
      o_pa <= 8'h0;
    end
    else if (clk_1mhz_ph1_en & i_cs & i_we) begin
      case (i_addr)
      4'h0: o_pa <= i_data;
      4'h4: timer_a_lo_latch <= i_data;
      4'h5: timer_a_hi_latch <= i_data;
      4'he: begin
        timer_a_start <= i_data[0];
        timer_a_runmode <= i_data[3];
      end
      default: /* do nothing */;
      endcase
    end
  end

  always @* begin
    case (i_addr)
    4'h0: o_data = 8'hff;
    4'h1: o_data = i_pb;
    default: o_data = 0;
    endcase
  end


  always @* begin
    timer_a_load = 0;
    if (clk_1mhz_ph1_en & i_cs & i_we) begin
      if (i_addr == 4'he) timer_a_load = i_data[4];
    end
    if (timer_a_runmode == 0 && timer_a_cntr == 0) timer_a_load = 1;
  end

  always @(posedge clk) begin
     if (rst) begin
       timer_a_cntr <= 0;
     end
     else if (clk_1mhz_ph1_en) begin
       if (timer_a_load) timer_a_cntr <= {timer_a_hi_latch, timer_a_lo_latch};
       else if (timer_a_start) timer_a_cntr <= timer_a_cntr - 1;
     end
  end

  // XXX: Temporary hack for timer interrupt.
  always @(posedge clk) begin
     if (rst) begin
        o_irq <= 0;
     end
     else if (clk_1mhz_ph1_en) begin
       if (timer_a_cntr == 0) o_irq <= 1;
       else if (i_cs && i_addr == 4'hd && ~i_we) o_irq <= 0;
     end
  end

endmodule
