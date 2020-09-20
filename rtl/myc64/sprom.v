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

module sprom(clk, rst, ce, oe, addr, do);
	//
	// Default address and data buses width (1024*32)
	//
	parameter aw = 10; //number of address-bits
	parameter dw = 32; //number of data-bits
	parameter MEM_INIT_FILE = "";

	//
	// Generic synchronous single-port ROM interface
	//
	input           clk;  // Clock, rising edge
	input           rst;  // Reset, active high
	input           ce;   // Chip enable input, active high
	input           oe;   // Output enable input, active high
	input  [aw-1:0] addr; // address bus inputs
	output reg [dw-1:0] do;   // output data bus

	//
	// Module body
	//

	reg [dw-1:0] mem [(1<<aw) -1:0];
	reg [aw-1:0] ra;
	reg oe_r;

	always @(posedge clk)
		oe_r <= oe;

	always @*
//		if (oe_r)
			do = mem[ra];

	// read operation
	always @(posedge clk)
	  if (ce)
	    ra <= addr;     // read address needs to be registered to read clock

	initial begin
		/* verilator lint_off WIDTH */
		if (MEM_INIT_FILE != "") begin
		/* verilator lint_on WIDTH */
			$readmemh(MEM_INIT_FILE, mem);
		end
	end

endmodule

// Async ROM wrapper that serves two pases. phN_addr must be stable between phN_en pulses.
module sprom2phase(
  clk,
  rst,
  ph1_en,
  ph1_addr,
  ph1_do,
  ph2_en,
  ph2_addr,
  ph2_do
);

	parameter aw = 10; //number of address-bits
	parameter dw = 32; //number of data-bits
	parameter MEM_INIT_FILE = "";

  input clk;
  input rst;
  input ph1_en;
  input [aw-1:0] ph1_addr;
  output reg [dw-1:0] ph1_do;
  input ph2_en;
  input [aw-1:0] ph2_addr;
  output reg [dw-1:0] ph2_do;

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

  sprom #(
    .aw(aw),
    .dw(dw),
    .MEM_INIT_FILE(MEM_INIT_FILE)
  ) u_sprom(
    .clk(clk),
    .rst(rst),
    .ce(1'b1),
    .oe(1'b1),
    .addr(ph1_not_ph2 ? ph1_addr : ph2_addr),
    .do(do)
  );

endmodule
