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

module cpu6510(
  input clk,              // CPU clock
  input reset,            // reset signal
  output reg [15:0] AB,   // address bus
  input [7:0] DI,         // data in, read bus
  output reg [7:0] DO,    // data out, write bus
  output reg WE,          // write enable
  input IRQ,              // interrupt request
  input NMI,              // non-maskable interrupt request
  input RDY,              // Ready signal. Pauses CPU when RDY=0
  output reg [5:0] PO,
  input [5:0] PI
);

  wire [15:0] AB_w;
  wire [7:0] DI_w, DO_w;
  wire WE_w;

  always @(posedge clk) begin
    if (RDY) begin
      AB <= AB_w;
      DO <= DO_w;
      WE <= WE_w;
    end
  end

  always @(posedge clk) begin
    if (reset) begin
      PO <= 6'b11_1111;
    end
    else if (RDY && WE_w && AB_w == 16'h0001) begin
      PO <= DO_w[5:0];
    end
  end

  assign DI_w = AB == 16'h0001 ? {2'b00, PO} : DI;

  cpu u_cpu(
    .clk(clk),
    .reset(reset),
    .AB(AB_w),
    .DI(DI_w),
    .DO(DO_w),
    .WE(WE_w),
    .IRQ(IRQ),
    .NMI(NMI),
    .RDY(RDY)
  );

endmodule
