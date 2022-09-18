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

module myc64_top(
  input rst,
  input clk,
  output reg [23:0] o_color_rgb,
  output [3:0] o_color_idx,
  output o_hsync,
  output o_vsync,
  output [15:0] o_wave,
  input [63:0] i_keyboard_mask,
  input i_ext_we,
  input [15:0] i_ext_addr,
  input [7:0] i_ext_data,
  output o_ext_ready
);

  reg [2:0] clk_cntr;
  always @(posedge clk) begin
    if (rst)
       // XXX: The system is sensitive to which clk_1mhz_ph?_en comes first
       // after reset.
      clk_cntr <= 3'b101;
    else
      clk_cntr <= clk_cntr + 3'h1;
  end

  wire clk_1mhz_ph1_en;
  wire clk_1mhz_ph2_en;
  assign clk_1mhz_ph1_en = (clk_cntr == 3'b000);
  assign clk_1mhz_ph2_en = (clk_cntr == 3'b100);

  wire [15:0] cpu_addr;
  wire [7:0] cpu_do;
  wire cpu_we;
  reg [7:0] cpu_di;
  wire [5:0] cpu_po;
  wire [7:0] ram_main_do, rom_basic_do, rom_kernal_do, rom_char_do;
  wire [3:0] ram_color_do;

  wire [15:0] vic_addr;
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

  reg [15:0] ext_addr_r;
  reg [7:0] ext_data_r;
  reg ext_we_r;

  reg vic_cycle;
  always @(posedge clk) begin
    if (clk_1mhz_ph1_en)
      vic_cycle <= 0;
    else if (clk_1mhz_ph2_en)
      vic_cycle <= 1;
  end

  // For better or worse the memory signals need to be stable for an entire ph2
  // cycle.
  always @(posedge clk) begin
    if (clk_1mhz_ph2_en) begin
      ext_addr_r <= i_ext_addr;
      ext_data_r <= i_ext_data;
      ext_we_r <= i_ext_we;
    end
  end

  assign o_ext_ready = ext_we_r & clk_1mhz_ph1_en;

  cpu6510 u_cpu(
    .clk(clk),
    .reset(rst),
    .clk_1mhz_ph1_en(clk_1mhz_ph1_en),
    .clk_1mhz_ph2_en(clk_1mhz_ph2_en),
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

  vic_ii_2 u_vic(
    .clk(clk),
    .rst(rst),
    .clk_8mhz_en(1'b1),
    .clk_1mhz_ph1_en(clk_1mhz_ph1_en),
    .clk_1mhz_ph2_en(clk_1mhz_ph2_en),
    .o_addr(vic_addr),
    .i_data({ram_color_do, vic_di}),
    .i_reg_cs(vic_cs),
    .i_reg_we(cpu_we),
    .i_reg_addr(cpu_addr[5:0]),
    .i_reg_data(cpu_do),
    .o_reg_data(vic_reg_do),
    .BA(vic_ba),
    .BM(vic_bm),
    .o_color(o_color_idx),
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

  spram #(
    .aw(16),
    .dw(8)
  ) u_ram_main(
    .clk(clk),
    .rst(rst),
    .we(cpu_we & vic_bm & ~vic_cycle),
    .ce(1'b1),
    .oe(1'b1),
    .addr((~vic_bm | vic_cycle) ? vic_addr : cpu_addr),
    .di(cpu_do),
    .do(ram_main_do)
  );

  spram #(
    .aw(10),
    .dw(4)
  ) u_ram_color(
    .clk(clk),
    .rst(rst),
    .we(color_cs & cpu_we),
    .ce(color_cs | ~vic_bm),
    .oe(1'b1),
    .addr(vic_bm ? cpu_addr[9:0] : vic_addr[9:0]),
    .di(cpu_do[3:0]),
    .do(ram_color_do)
  );

  sprom #(
    .aw(12),
    .dw(8),
    .MEM_INIT_FILE(`MYC64_CHARACTERS_VH)
  ) u_rom_char(
    .clk(clk),
    .rst(rst),
    .oe(1'b1),
    .ce(1'b1),
    .addr(vic_cycle ? vic_addr : cpu_addr[11:0]),
    .do(rom_char_do)
  );

  sprom #(
    .aw(13),
    .dw(8),
    .MEM_INIT_FILE(`MYC64_BASIC_VH)
  ) u_rom_basic(
    .clk(clk),
    .rst(rst),
    .oe(1'b1),
    .ce(1'b1),
    .addr(cpu_addr[12:0]),
    .do(rom_basic_do)
  );

  sprom #(
    .aw(13),
    .dw(8),
    .MEM_INIT_FILE(`MYC64_KERNAL_VH)
  ) u_rom_kernal(
    .clk(clk),
    .rst(rst),
    .oe(1'b1),
    .ce(1'b1),
    .addr(cpu_addr[12:0]),
    .do(rom_kernal_do)
  );

  // Bank switching - following the table from
  // https://www.c64-wiki.com/wiki/Bank_Switching
  always @(*) begin
    cpu_di = 0;
    ram_enabled = 0;
    vic_cs = 0;
    sid_cs = 0;
    cia1_cs = 0;
    color_cs = 0;
    // RAM (which the system requires and must appear in each mode)
    if (cpu_addr <= 16'h0FFF) begin
      cpu_di = ram_main_do;
      ram_enabled = 1;
    end
    // RAM or is unmapped
    else if (16'h1000 <= cpu_addr && cpu_addr <= 16'h7FFF) begin
      cpu_di = ram_main_do;
      ram_enabled = 1;
    end
    // RAM or cartridge ROM
    else if (16'h8000 <= cpu_addr && cpu_addr <= 16'h9FFF) begin
      cpu_di = ram_main_do;
      ram_enabled = 1;
    end
    // RAM, BASIC interpretor ROM, cartridge ROM or is unmapped
    else if (16'hA000 <= cpu_addr && cpu_addr <= 16'hBFFF) begin
      if (cpu_po[2:0] == 3'b111 || cpu_po[2:0] == 3'b011) begin
        cpu_di = rom_basic_do;
      end
      else begin
        cpu_di = ram_main_do;
        ram_enabled = 1;
      end
    end
    // RAM or is unmapped
    else if (16'hC000 <= cpu_addr && cpu_addr <= 16'hCFFF) begin
      cpu_di = ram_main_do;
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
          cpu_di = {4'h0, ram_color_do}; // XXX: No CPU read from color RAM?
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
        cpu_di = rom_char_do;
      end
      else begin
        // RAM
        cpu_di = ram_main_do;
        ram_enabled = 1;
      end
    end
    // RAM, KERNAL ROM or cartridge ROM
    else if (16'hE000 <= cpu_addr) begin
      if (cpu_po[2:0] == 3'b111 || cpu_po[2:0] == 3'b110 ||
          cpu_po[2:0] == 3'b011 || cpu_po[2:0] == 3'b010) begin
        cpu_di = rom_kernal_do;
      end
      else begin
        cpu_di = ram_main_do;
        ram_enabled = 1;
      end
    end
  end

  always @(*) begin
    casex (vic_addr)
      16'bxx01_xxxx_xxxx_xxxx: vic_di = rom_char_do; // Char ROM at 0x1000-0x1fff
      default: vic_di = ram_main_do;
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

  // Map color index to RGB.
  always @* begin
   case (o_color_idx)
   4'h0: o_color_rgb = 24'h00_00_00;
   4'h1: o_color_rgb = 24'hff_ff_ff;
   4'h2: o_color_rgb = 24'h88_00_00;
   4'h3: o_color_rgb = 24'haa_ff_ee;
   4'h4: o_color_rgb = 24'hcc_44_cc;
   4'h5: o_color_rgb = 24'h00_cc_55;
   4'h6: o_color_rgb = 24'h00_00_aa;
   4'h7: o_color_rgb = 24'hee_ee_77;
   4'h8: o_color_rgb = 24'hdd_88_55;
   4'h9: o_color_rgb = 24'h66_44_00;
   4'ha: o_color_rgb = 24'hff_77_77;
   4'hb: o_color_rgb = 24'h33_33_33;
   4'hc: o_color_rgb = 24'h77_77_77;
   4'hd: o_color_rgb = 24'haa_ff_66;
   4'he: o_color_rgb = 24'h00_88_ff;
   4'hf: o_color_rgb = 24'hbb_bb_bb;
   endcase
  end

endmodule
