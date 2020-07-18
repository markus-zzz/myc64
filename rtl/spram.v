/*
 * Copyright (C) 2018-2020 Markus Lavin (https://www.zzzconsulting.se/)
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

module spram(clk, rst, ce, we, oe, addr, di, do);
	//
	// Default address and data buses width (1024*32)
	//
	parameter aw = 10; //number of address-bits
	parameter dw = 32; //number of data-bits

	//
	// Generic synchronous single-port RAM interface
	//
	input           clk;  // Clock, rising edge
	input           rst;  // Reset, active high
	input           ce;   // Chip enable input, active high
	input           we;   // Write enable input, active high
	input           oe;   // Output enable input, active high
	input  [aw-1:0] addr; // address bus inputs
	input  [dw-1:0] di;   // input data bus
	output reg [dw-1:0] do;   // output data bus

	//
	// Module body
	//

	reg [dw-1:0] mem [(1<<aw) -1:0] /* verilator public */;
	reg [aw-1:0] ra;
	reg oe_r;

	always @(posedge clk)
		oe_r <= oe;

	always @*
		if (oe_r)
			do = mem[ra];

	// read operation
	always @(posedge clk)
	  if (ce)
	    ra <= addr;     // read address needs to be registered to read clock

	// write operation
	always @(posedge clk) begin
	  if (we && ce) begin
	    mem[addr] <= di;
            // $display("mem[%h] <= %h\n", addr, di);
          end
        end

endmodule

// Async RAM wrapper that serves two pases. phN_addr, phN_di and phN_we must be stable between phN_en pulses.
module spram2phase(
  clk,
  rst,
  ph1_en,
  ph1_addr,
  ph1_do,
  ph1_di,
  ph1_we,
  ph1_cs,
  ph2_en,
  ph2_addr,
  ph2_do,
  ph2_di,
  ph2_we,
  ph2_cs
);

	parameter aw = 10; //number of address-bits
	parameter dw = 32; //number of data-bits

  input clk;
  input rst;
  input ph1_en;
  input [aw-1:0] ph1_addr;
  output reg [dw-1:0] ph1_do;
  input [dw-1:0] ph1_di;
  input ph1_we;
  input ph1_cs;
  input ph2_en;
  input [aw-1:0] ph2_addr;
  output reg [dw-1:0] ph2_do;
  input [dw-1:0] ph2_di;
  input ph2_we;
  input ph2_cs;

  wire [dw-1:0] do;
  reg ph1_not_ph2;

  always @(posedge clk) begin
    if (ph1_en) ph1_not_ph2 <= 1'b1;
    else if (ph2_en) ph1_not_ph2 <= 1'b0;
  end

  always @(posedge clk) begin
    if (ph1_en) ph2_do <= do;
  end

  always @(posedge clk) begin
    if (ph2_en) ph1_do <= do;
  end

  spram #(
    .aw(aw),
    .dw(dw)
  ) u_spram(
    .clk(clk),
    .rst(rst),
    .ce(ph1_not_ph2 ? ph1_cs : ph2_cs),
    .oe(1'b1),
    .addr(ph1_not_ph2 ? ph1_addr : ph2_addr),
    .do(do),
    .di(ph1_not_ph2 ? ph1_di : ph2_di),
    .we(ph1_not_ph2 ? ph1_we : ph2_we)
  );

endmodule
