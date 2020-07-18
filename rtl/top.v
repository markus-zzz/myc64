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

/* verilator lint_off CASEX */

module top(
  input rst,
  input clk,
  output [23:0] o_pixel,
  output o_hsync,
  output o_vsync,
  output [15:0] o_wave,
  input [63:0] i_keyboard_mask
);

  reg [2:0] clk_cntr = 0;
  always @(posedge clk)
    clk_cntr <= clk_cntr + 3'h1;

  wire clk_1mhz_ph1_en;
  wire clk_1mhz_ph2_en;
  assign clk_1mhz_ph1_en = (clk_cntr == 3'b000);
  assign clk_1mhz_ph2_en = (clk_cntr == 3'b100);

  wire [15:0] cpu_addr;
  wire [7:0] cpu_do;
  wire cpu_we;
  reg [7:0] cpu_di;
  wire [5:0] cpu_po;
  wire [7:0] ram_main_ph1_do, ram_main_ph2_do, rom_basic_ph1_do, rom_kernal_ph1_do, rom_char_ph1_do, rom_char_ph2_do;
  wire [3:0] ram_color_ph1_do;

  wire [15:0] vic_addr, vic_addr_ph1;
  reg [7:0] vic_di;
  wire [7:0] vic_reg_do;
  wire vic_ba, vic_bm;

  wire [7:0] sid_do;

  wire [7:0] cia1_do;
  wire [7:0] cia1_pa;
  wire [7:0] cia1_pb;
  wire cia1_irq;

  reg ram_enabled;

  reg vic_cs, sid_cs, color_cs, cia1_cs;

  cpu6510 u_cpu(
    .clk(clk),
    .reset(rst),
    .AB(cpu_addr),
    .DI(cpu_di),
    .DO(cpu_do),
    .WE(cpu_we),
    .IRQ(cia1_irq),
    .NMI(1'b0),
    .RDY(clk_1mhz_ph1_en & vic_ba),
    .PO(cpu_po),
    .PI()
  );

  vic_ii u_vic(
    .clk(clk),
    .rst(rst),
    .clk_8mhz_en(1'b1),
    .clk_1mhz_ph1_en(clk_1mhz_ph1_en),
    .clk_1mhz_ph2_en(clk_1mhz_ph2_en),
    .o_addr_ph1(vic_addr_ph1),
    .i_data_ph1({ram_color_ph1_do, ram_main_ph1_do}),
    .o_addr_ph2(vic_addr),
    .i_data_ph2({4'h0, vic_di}),
    .i_reg_cs(vic_cs),
    .i_reg_we(cpu_we),
    .i_reg_addr(cpu_addr[5:0]),
    .i_reg_data(cpu_do),
    .o_reg_data(vic_reg_do),
    .BA(vic_ba),
    .BM(vic_bm),
    .o_pixel(o_pixel),
    .o_hsync(o_hsync),
    .o_vsync(o_vsync)
  );

  sid u_sid(
    .clk(clk),
    .rst(rst),
    .clk_1mhz_ph1_en(clk_1mhz_ph1_en),
    .i_cs(sid_cs),
    .i_addr(cpu_addr[4:0]),
    .i_we(cpu_we),
    .i_data(cpu_do),
    .o_data(sid_do),
    .o_wave(o_wave)
  );

  cia u_cia1(
    .clk(clk),
    .rst(rst),
    .clk_1mhz_ph1_en(clk_1mhz_ph1_en),
    .i_addr(cpu_addr[3:0]),
    .i_cs(cia1_cs),
    .i_we(cpu_we),
    .i_data(cpu_do),
    .o_data(cia1_do),
    .o_pa(cia1_pa),
    .i_pb(cia1_pb),
    .o_irq(cia1_irq)
  );

  spram2phase #(
    .aw(16),
    .dw(8)
  ) u_ram_main(
    .clk(clk),
    .rst(rst),
    .ph1_en(clk_1mhz_ph1_en),
    .ph2_en(clk_1mhz_ph2_en),
    .ph1_we(cpu_we & vic_bm),
    .ph2_we(1'b0),
    .ph1_cs(ram_enabled | ~vic_bm),
    .ph2_cs(1'b1),
    .ph1_addr(vic_bm ? cpu_addr[15:0] : vic_addr_ph1),
    .ph2_addr(0),
    .ph1_di(cpu_do),
    .ph2_di(0),
    .ph1_do(ram_main_ph1_do),
    .ph2_do(ram_main_ph2_do)
  );

  spram2phase #(
    .aw(10),
    .dw(4)
  ) u_ram_color(
    .clk(clk),
    .rst(rst),
    .ph1_en(clk_1mhz_ph1_en),
    .ph2_en(clk_1mhz_ph2_en),
    .ph1_we(color_cs & cpu_we),
    .ph2_we(1'b0),
    .ph1_cs(color_cs | ~vic_bm),
    .ph2_cs(1'b1),
    .ph1_addr(vic_bm ? cpu_addr[9:0] : vic_addr_ph1[9:0]),
    .ph2_addr(0),
    .ph1_di(cpu_do[3:0]),
    .ph2_di(0),
    .ph1_do(ram_color_ph1_do),
    .ph2_do()
  );

  sprom2phase #(
    .aw(12),
    .dw(8),
    .MEM_INIT_FILE("characters.vh")
  ) u_rom_char(
    .clk(clk),
    .rst(rst),
    .ph1_en(clk_1mhz_ph1_en),
    .ph2_en(clk_1mhz_ph2_en),
    .ph1_addr(cpu_addr[11:0]),
    .ph2_addr(vic_addr[11:0]),
    .ph1_do(rom_char_ph1_do),
    .ph2_do(rom_char_ph2_do)
  );

  sprom2phase #(
    .aw(13),
    .dw(8),
    .MEM_INIT_FILE("basic.vh")
  ) u_rom_basic(
    .clk(clk),
    .rst(rst),
    .ph1_en(clk_1mhz_ph1_en),
    .ph2_en(clk_1mhz_ph2_en),
    .ph1_addr(cpu_addr[12:0]),
    .ph2_addr(0),
    .ph1_do(rom_basic_ph1_do),
    .ph2_do()
  );

  sprom2phase #(
    .aw(13),
    .dw(8),
    .MEM_INIT_FILE("kernal.vh")
  ) u_rom_kernal(
    .clk(clk),
    .rst(rst),
    .ph1_en(clk_1mhz_ph1_en),
    .ph2_en(clk_1mhz_ph2_en),
    .ph1_addr(cpu_addr[12:0]),
    .ph2_addr(0),
    .ph1_do(rom_kernal_ph1_do),
    .ph2_do()
  );

  // Bank switching - following the table from
  // https://www.c64-wiki.com/wiki/Bank_Switching
  always @(*) begin
    ram_enabled = 0;
    vic_cs = 0;
    sid_cs = 0;
    cia1_cs = 0;
    color_cs = 0;
    // RAM (which the system requires and must appear in each mode)
    if (cpu_addr <= 16'h0FFF) begin
      cpu_di = ram_main_ph1_do;
      ram_enabled = 1;
    end
    // RAM or is unmapped
    else if (16'h1000 <= cpu_addr && cpu_addr <= 16'h7FFF) begin
      cpu_di = ram_main_ph1_do;
      ram_enabled = 1;
    end
    // RAM or cartridge ROM
    else if (16'h8000 <= cpu_addr && cpu_addr <= 16'h9FFF) begin
      cpu_di = ram_main_ph1_do;
      ram_enabled = 1;
    end
    // RAM, BASIC interpretor ROM, cartridge ROM or is unmapped
    else if (16'hA000 <= cpu_addr && cpu_addr <= 16'hBFFF) begin
      if (cpu_po[2:0] == 3'b111 || cpu_po[2:0] == 3'b011) begin
        cpu_di = rom_basic_ph1_do;
      end
      else begin
        cpu_di = ram_main_ph1_do;
        ram_enabled = 1;
      end
    end
    // RAM or is unmapped
    else if (16'hC000 <= cpu_addr && cpu_addr <= 16'hCFFF) begin
      cpu_di = ram_main_ph1_do;
      ram_enabled = 1;
    end
    // RAM, Character generator ROM, or I/O registers and Color RAM
    else if (16'hD000 <= cpu_addr && cpu_addr <= 16'hDFFF) begin
      if (cpu_po[2:0] == 3'b111 || cpu_po[2:0] == 3'b110 ||
          cpu_po[2:0] == 3'b101) begin
        // IO
        if (16'hD000 <= cpu_addr && cpu_addr <= 16'hD3FF) begin // VIC-II
          cpu_di = vic_reg_do;
          vic_cs = 1;
        end
        else if (16'hD400 <= cpu_addr && cpu_addr <= 16'hD7FF) begin // SID
          cpu_di = sid_do;
          sid_cs = 1;
        end
        else if (16'hD800 <= cpu_addr && cpu_addr <= 16'hDBFF) begin // COLOR-RAM
          cpu_di = {4'h0, ram_color_ph1_do}; // XXX: No CPU read from color RAM?
          color_cs = 1;
        end
        else if (16'hDC00 <= cpu_addr && cpu_addr <= 16'hDCFF) begin // CIA1
          cpu_di = cia1_do;
          cia1_cs = 1;
        end
      end
      else if (cpu_po[2:0] == 3'b011 || cpu_po[2:0] == 3'b010 ||
          cpu_po[2:0] == 3'b001) begin
        // CHAR ROM
        cpu_di = rom_char_ph1_do;
      end
      else begin
        // RAM
        cpu_di = ram_main_ph1_do;
        ram_enabled = 1;
      end
    end
    // RAM, KERNAL ROM or cartridge ROM
    else if (16'hE000 <= cpu_addr) begin
      if (cpu_po[2:0] == 3'b111 || cpu_po[2:0] == 3'b110 ||
          cpu_po[2:0] == 3'b011 || cpu_po[2:0] == 3'b010) begin
        cpu_di = rom_kernal_ph1_do;
      end
      else begin
        cpu_di = ram_main_ph1_do;
        ram_enabled = 1;
      end
    end
  end

  always @(*) begin
    casex (vic_addr)
      16'bxx01_xxxx_xxxx_xxxx: vic_di = rom_char_ph2_do; // Char ROM at 0x1000-0x1fff
      default: vic_di = ram_main_ph2_do;
    endcase
  end

  // Keyboard matrix.
  assign cia1_pb =
    ~((~cia1_pa[7] ? i_keyboard_mask[63:56] : 8'h00) |
      (~cia1_pa[6] ? i_keyboard_mask[55:48] : 8'h00) |
      (~cia1_pa[5] ? i_keyboard_mask[47:40] : 8'h00) |
      (~cia1_pa[4] ? i_keyboard_mask[39:32] : 8'h00) |
      (~cia1_pa[3] ? i_keyboard_mask[31:24] : 8'h00) |
      (~cia1_pa[2] ? i_keyboard_mask[23:16] : 8'h00) |
      (~cia1_pa[1] ? i_keyboard_mask[15:8]  : 8'h00) |
      (~cia1_pa[0] ? i_keyboard_mask[7:0]   : 8'h00));


endmodule
