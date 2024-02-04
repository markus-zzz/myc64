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

class Cia(Elaboratable):
  def __init__(self):
    self.clk_1mhz_ph_en = Signal()
    self.i_cs = Signal()
    self.i_addr = Signal(4)
    self.i_we = Signal()
    self.i_data = Signal(8)
    self.o_data = Signal(8)
    self.o_pa = Signal(8)
    self.i_pb = Signal(8)
    self.o_irq = Signal()

    self.ports = [
        self.clk_1mhz_ph_en, self.i_cs, self.i_addr, self.i_we, self.i_data, self.o_data, self.o_pa, self.i_pb,
        self.o_irq
    ]

  def elaborate(self, platform):
    m = Module()

    timer_a_cntr = Signal(16)
    timer_a_lo_latch = Signal(8)
    timer_a_hi_latch = Signal(8)

    timer_a_start = Signal()
    timer_a_runmode = Signal()
    timer_a_load = Signal()

    with m.If(self.clk_1mhz_ph_en & self.i_cs & self.i_we):
      with m.Switch(self.i_addr):
        with m.Case(0x0):
          m.d.sync += self.o_pa.eq(self.i_data)
        with m.Case(0x4):
          m.d.sync += timer_a_lo_latch.eq(self.i_data)
        with m.Case(0x5):
          m.d.sync += timer_a_hi_latch.eq(self.i_data)
        with m.Case(0xe):
          m.d.sync += timer_a_start.eq(self.i_data[0])
          m.d.sync += timer_a_runmode.eq(self.i_data[3])

    m.d.comb += self.o_data.eq(0)
    with m.Switch(self.i_addr):
      with m.Case(0x0):
        m.d.comb += self.o_data.eq(0xff)
      with m.Case(0x1):
        m.d.comb += self.o_data.eq(self.i_pb)

    m.d.comb += timer_a_load.eq(0)
    with m.If(self.clk_1mhz_ph_en & self.i_cs & self.i_we):
      with m.If(self.i_addr == 0xe):
        m.d.comb += timer_a_load.eq(self.i_data[4])
    with m.If(~timer_a_runmode & (timer_a_cntr == 0)):
      m.d.comb += timer_a_load.eq(1)

    with m.If(self.clk_1mhz_ph_en):
      with m.If(timer_a_load):
        m.d.sync += timer_a_cntr.eq(Cat(timer_a_lo_latch, timer_a_hi_latch))
      with m.Elif(timer_a_start):
        m.d.sync += timer_a_cntr.eq(timer_a_cntr - 1)

    # XXX: Temporary hack for timer interrupt.
    with m.If(self.clk_1mhz_ph_en):
      with m.If(timer_a_cntr == 0):
        m.d.sync += self.o_irq.eq(1)
      with m.Elif(self.i_cs & (self.i_addr == 0xd) & ~self.i_we):
        m.d.sync += self.o_irq.eq(0)

    return m


if __name__ == "__main__":
  cia = Cia()
  main(cia, name="cia", ports=cia.ports)
