#
# Copyright (C) 2020-2021 Markus Lavin (https://www.zzzconsulting.se/)
#
# All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# yapf --in-place --recursive --style="{indent_width: 2, column_limit: 120}"

from amaranth import *
from cpu6510 import Cpu6510
from cia import Cia
from vicii import VicII


class MyC64(Elaboratable):
  def __init__(self):
    self.o_vid_rgb = Signal(24)
    self.o_vid_hsync = Signal()
    self.o_vid_vsync = Signal()
    self.o_vid_en = Signal()
    self.o_wave = Signal(16)
    self.i_keyboard_mask = Signal(64)

    self.o_bus_addr = Signal(16)
    self.i_rom_char_data = Signal(8)
    self.i_rom_basic_data = Signal(8)
    self.i_rom_kernal_data = Signal(8)
    self.i_ram_main_data = Signal(8)
    self.o_ram_main_data = Signal(8)
    self.o_ram_main_we = Signal()

    self.o_clk_1mhz_ph1_en = Signal()
    self.o_clk_1mhz_ph2_en = Signal()

    self.ports = [
        self.o_vid_rgb, self.o_vid_hsync, self.o_vid_vsync, self.o_vid_en, self.o_wave, self.i_keyboard_mask,
        self.o_bus_addr, self.i_rom_char_data, self.i_rom_basic_data, self.i_rom_kernal_data,
        self.i_ram_main_data, self.o_ram_main_data, self.o_ram_main_we, self.o_clk_1mhz_ph1_en, self.o_clk_1mhz_ph2_en
    ]

  def elaborate(self, platform):
    m = Module()

    # XXX: The system is sensitive to which clk_1mhz_ph?_en comes first
    # after reset.
    clk_cntr = Signal(3, reset=0b101)
    m.d.sync += clk_cntr.eq(clk_cntr + 1)

    clk_1mhz_ph1_en = Signal()
    clk_1mhz_ph2_en = Signal()
    m.d.comb += [clk_1mhz_ph1_en.eq(clk_cntr == 0b000), clk_1mhz_ph2_en.eq(clk_cntr == 0b100)]

    vic_cycle = Signal()
    with m.If(clk_1mhz_ph1_en):
      m.d.sync += vic_cycle.eq(0)
    with m.Elif(clk_1mhz_ph2_en):
      m.d.sync += vic_cycle.eq(1)

    # 6510 CPU.
    m.submodules.u_cpu = u_cpu = Cpu6510()

    # Vic-II.
    m.submodules.u_vic = u_vic = VicII()

    # CIA-1.
    m.submodules.u_cia1 = u_cia1 = Cia()

    # CIA-2.
    m.submodules.u_cia2 = u_cia2 = Cia()

    # Color RAM.
    u_ram_color = Memory(width=4, depth=pow(2, 10))
    u_ram_color_rp = u_ram_color.read_port()
    u_ram_color_wp = u_ram_color.write_port()
    m.submodules += [u_ram_color_rp, u_ram_color_wp]

    cpu_di = Signal(8)
    ram_cs = Signal()
    sid_cs = Signal()
    cia1_cs = Signal()
    cia2_cs = Signal()
    color_cs = Signal()

    cpu_addr = Signal(16)
    cpu_we = Signal()
    cpu_di = Signal(8)
    cpu_do = Signal(8)
    cpu_po = Signal(6)

    sid_do = Signal(8)

    bus_addr = Signal(16)
    bus_we = Signal()
    bus_di = Signal(8)
    bus_do = Signal(8)

    m.d.comb += [self.o_bus_addr.eq(bus_addr), self.o_clk_1mhz_ph1_en.eq(clk_1mhz_ph1_en), self.o_clk_1mhz_ph2_en.eq(clk_1mhz_ph2_en)]
    m.d.comb += [
        u_ram_color_rp.addr.eq(bus_addr),
        u_ram_color_wp.addr.eq(bus_addr),
        u_ram_color_wp.data.eq(bus_do),
        self.o_ram_main_data.eq(bus_do),
        self.o_ram_main_we.eq(ram_cs & bus_we),
        u_ram_color_wp.en.eq(color_cs & bus_we)
    ]

    # Bank switching - following the table from
    # https://www.c64-wiki.com/wiki/Bank_Switching
    m.d.comb += [
        cpu_di.eq(0),
        ram_cs.eq(0),
        u_vic.i_reg_cs.eq(0),
        sid_cs.eq(0),
        cia1_cs.eq(0),
        cia2_cs.eq(0),
        color_cs.eq(0)
    ]

    # RAM (which the system requires and must appear in each mode)
    with m.If(cpu_addr <= 0x0FFF):
      m.d.comb += [cpu_di.eq(self.i_ram_main_data), ram_cs.eq(1)]
    #RAM or is unmapped
    with m.Elif((0x1000 <= cpu_addr) & (cpu_addr <= 0x7FFF)):
      m.d.comb += [cpu_di.eq(self.i_ram_main_data), ram_cs.eq(1)]
    # RAM or cartridge ROM
    with m.Elif((0x8000 <= cpu_addr) & (cpu_addr <= 0x9FFF)):
      m.d.comb += [cpu_di.eq(self.i_ram_main_data), ram_cs.eq(1)]
    # RAM, BASIC interpretor ROM, cartridge ROM or is unmapped
    with m.Elif((0xA000 <= cpu_addr) & (cpu_addr <= 0xBFFF)):
      with m.If((cpu_po[0:3] == 0b111) | (cpu_po[0:3] == 0b011)):
        m.d.comb += [cpu_di.eq(self.i_rom_basic_data)]
      with m.Else():
        m.d.comb += [cpu_di.eq(self.i_ram_main_data), ram_cs.eq(1)]
    # RAM or is unmapped
    with m.Elif((0xC000 <= cpu_addr) & (cpu_addr <= 0xCFFF)):
      m.d.comb += [cpu_di.eq(self.i_ram_main_data), ram_cs.eq(1)]
    # RAM, Character generator ROM, or I/O registers and Color RAM
    with m.Elif((0xD000 <= cpu_addr) & (cpu_addr <= 0xDFFF)):
      with m.If((cpu_po[0:3] == 0b111) | (cpu_po[0:3] == 0b110) | (cpu_po[0:3] == 0b101)):
        # IO
        with m.If((0xD000 <= cpu_addr) & (cpu_addr <= 0xD3FF)):  # VIC-II
          m.d.comb += [cpu_di.eq(u_vic.o_reg_data), u_vic.i_reg_cs.eq(1)]
        with m.Elif((0xD400 <= cpu_addr) & (cpu_addr <= 0xD7FF)):  # SID
          m.d.comb += [cpu_di.eq(sid_do), sid_cs.eq(1)]
        with m.Elif((0xD800 <= cpu_addr) & (cpu_addr <= 0xDBFF)):  # COLOR-RAM
          m.d.comb += [cpu_di.eq(u_ram_color_rp.data), color_cs.eq(1)]
        with m.Elif((0xDC00 <= cpu_addr) & (cpu_addr <= 0xDCFF)):  # CIA1
          m.d.comb += [cpu_di.eq(u_cia1.o_data), cia1_cs.eq(1)]
        with m.Elif((0xDD00 <= cpu_addr) & (cpu_addr <= 0xDDFF)):  # CIA2
          m.d.comb += [cpu_di.eq(u_cia2.o_data), cia2_cs.eq(1)]
      with m.Elif((cpu_po[0:3] == 0b011) | (cpu_po[0:3] == 0b010) | (cpu_po[0:3] == 0b001)):
        # CHAR ROM
        m.d.comb += [cpu_di.eq(self.i_rom_char_data)]
      with m.Else():
        # RAM
        m.d.comb += [cpu_di.eq(self.i_ram_main_data), ram_cs.eq(1)]
    # RAM, KERNAL ROM or cartridge ROM
    with m.Elif(0xE000 <= cpu_addr):
      with m.If((cpu_po[0:3] == 0b111) | (cpu_po[0:3] == 0b110) | (cpu_po[0:3] == 0b011) | (cpu_po[0:3] == 0b010)):
        m.d.comb += [cpu_di.eq(self.i_rom_kernal_data)]
      with m.Else():
        m.d.comb += [cpu_di.eq(self.i_ram_main_data), ram_cs.eq(1)]

    #
    #
    #

    m.d.comb += [
        u_cpu.i_rdy.eq(clk_1mhz_ph1_en & u_vic.BA),
        u_cpu.i_data.eq(cpu_di),
        u_cpu.i_irq.eq(u_cia1.o_irq | ~u_vic.IRQ),
        cpu_addr.eq(u_cpu.o_addr),
        cpu_we.eq(u_cpu.o_we),
        cpu_do.eq(u_cpu.o_data),
        cpu_po.eq(u_cpu.o_port),
        u_cpu.clk_1mhz_ph1_en.eq(clk_1mhz_ph1_en),
        u_cpu.clk_1mhz_ph2_en.eq(clk_1mhz_ph2_en),
        u_cpu.i_BA.eq(u_vic.BA),
        # VIC-II
        u_vic.clk_8mhz_en.eq(1),
        u_vic.clk_1mhz_ph1_en.eq(clk_1mhz_ph1_en),
        u_vic.clk_1mhz_ph2_en.eq(clk_1mhz_ph2_en),
        u_vic.i_reg_addr.eq(bus_addr),
        u_vic.i_reg_data.eq(bus_do),
        u_vic.i_reg_we.eq(bus_we),
        # CIA-1
        u_cia1.clk_1mhz_ph_en.eq(clk_1mhz_ph2_en),
        u_cia1.i_cs.eq(cia1_cs),
        u_cia1.i_addr.eq(bus_addr),
        u_cia1.i_we.eq(bus_we),
        u_cia1.i_data.eq(bus_do),
        # CIA-2
        u_cia2.clk_1mhz_ph_en.eq(clk_1mhz_ph2_en),
        u_cia2.i_cs.eq(cia2_cs),
        u_cia2.i_addr.eq(bus_addr),
        u_cia2.i_we.eq(bus_we),
        u_cia2.i_data.eq(bus_do),
        # Bus matrix
        bus_addr.eq(Mux(vic_cycle | ~u_vic.BM, Cat(u_vic.o_addr, ~u_cia2.o_pa[0:2]), cpu_addr)),
        bus_we.eq(cpu_we & u_vic.BM & ~vic_cycle),
        bus_do.eq(cpu_do)
    ]

    with m.If((bus_addr[12:16] == 0b0001) | (bus_addr[12:16] == 0b1001)):
      m.d.comb += u_vic.i_data.eq(Cat(self.i_rom_char_data, u_ram_color_rp.data))
    with m.Else():
      m.d.comb += u_vic.i_data.eq(Cat(self.i_ram_main_data, u_ram_color_rp.data))

    # Keyboard matrix.
    m.d.comb += u_cia1.i_pb.eq(~(
        Mux(~u_cia1.o_pa[7], self.i_keyboard_mask[56:64], 0) |  #
        Mux(~u_cia1.o_pa[6], self.i_keyboard_mask[48:56], 0) |  #
        Mux(~u_cia1.o_pa[5], self.i_keyboard_mask[40:48], 0) |  #
        Mux(~u_cia1.o_pa[4], self.i_keyboard_mask[32:40], 0) |  #
        Mux(~u_cia1.o_pa[3], self.i_keyboard_mask[24:32], 0) |  #
        Mux(~u_cia1.o_pa[2], self.i_keyboard_mask[16:24], 0) |  #
        Mux(~u_cia1.o_pa[1], self.i_keyboard_mask[8:16], 0) |  #
        Mux(~u_cia1.o_pa[0], self.i_keyboard_mask[0:8], 0)))

    m.d.comb += [self.o_vid_hsync.eq(u_vic.o_hsync), self.o_vid_vsync.eq(u_vic.o_vsync), self.o_vid_en.eq(u_vic.o_visib)]

    with m.Switch(u_vic.o_color):
      with m.Case(0x0):
        m.d.comb += self.o_vid_rgb.eq(0x000000)
      with m.Case(0x1):
        m.d.comb += self.o_vid_rgb.eq(0xffffff)
      with m.Case(0x2):
        m.d.comb += self.o_vid_rgb.eq(0x880000)
      with m.Case(0x3):
        m.d.comb += self.o_vid_rgb.eq(0xaaffee)
      with m.Case(0x4):
        m.d.comb += self.o_vid_rgb.eq(0xcc44cc)
      with m.Case(0x5):
        m.d.comb += self.o_vid_rgb.eq(0x00cc55)
      with m.Case(0x6):
        m.d.comb += self.o_vid_rgb.eq(0x0000aa)
      with m.Case(0x7):
        m.d.comb += self.o_vid_rgb.eq(0xeeee77)
      with m.Case(0x8):
        m.d.comb += self.o_vid_rgb.eq(0xdd8855)
      with m.Case(0x9):
        m.d.comb += self.o_vid_rgb.eq(0x664400)
      with m.Case(0xa):
        m.d.comb += self.o_vid_rgb.eq(0xff7777)
      with m.Case(0xb):
        m.d.comb += self.o_vid_rgb.eq(0x333333)
      with m.Case(0xc):
        m.d.comb += self.o_vid_rgb.eq(0x777777)
      with m.Case(0xd):
        m.d.comb += self.o_vid_rgb.eq(0xaaff66)
      with m.Case(0xe):
        m.d.comb += self.o_vid_rgb.eq(0x0088ff)
      with m.Case(0xf):
        m.d.comb += self.o_vid_rgb.eq(0xbbbbbb)

    return m

#
# Generate verilog
#

from amaranth.back import verilog
import sys
import os

if __name__ == "__main__":

  myc64 = MyC64()

  with open("myc64.v", "w") as f:
    f.write(verilog.convert(elaboratable=myc64, name='myc64_top', ports=myc64.ports))