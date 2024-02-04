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

class Cpu6510(Elaboratable):
  def __init__(self):
    self.clk_1mhz_ph1_en = Signal()
    self.clk_1mhz_ph2_en = Signal()
    self.o_addr = Signal(16)  # address bus
    self.i_data = Signal(8)  # data in, read bus
    self.o_data = Signal(8)  #data out, write bus
    self.o_we = Signal()  # write enable
    self.i_irq = Signal()  # interrupt request
    self.i_nmi = Signal()  # non-maskable interrupt request
    self.i_rdy = Signal()  # Ready signal. Pauses CPU when RDY=0
    self.o_port = Signal(6, reset=0b11_1111)
    self.i_port = Signal(6)
    self.i_BA = Signal()

    self.ports = [
        self.clk_1mhz_ph1_en, self.clk_1mhz_ph2_en, self.o_addr, self.i_data, self.o_data, self.o_we, self.i_irq,
        self.i_nmi, self.i_rdy, self.o_port, self.i_port
    ]

  def elaborate(self, platform):
    m = Module()

    clk = ClockSignal('sync')
    rst = ResetSignal('sync')

    addr = Signal(16)
    data_i = Signal(8)
    data_o = Signal(8)
    we = Signal()
    rdy = Signal()
    rdy_mask = Signal()

    with m.If(~self.i_BA):
      m.d.sync += rdy_mask.eq(0)
    with m.Elif(self.clk_1mhz_ph2_en):
      m.d.sync += rdy_mask.eq(1)

    m.d.comb += rdy.eq(self.i_rdy & rdy_mask)

    m.submodules.u_6502 = Instance('cpu',
                                   i_clk=clk,
                                   i_reset=rst,
                                   o_AB=addr,
                                   i_DI=data_i,
                                   o_DO=data_o,
                                   o_WE=we,
                                   i_IRQ=self.i_irq,
                                   i_NMI=self.i_nmi,
                                   i_RDY=rdy)

    with m.If(rdy):
      m.d.sync += [self.o_addr.eq(addr), self.o_data.eq(data_o), self.o_we.eq(we)]

    with m.If(rdy & we & (addr == 0x0001)):
      m.d.sync += self.o_port.eq(data_o[0:6])

    data_ir = Signal(8)
    with m.If(self.clk_1mhz_ph2_en & self.i_BA):
      m.d.sync += data_ir.eq(self.i_data)

    m.d.comb += data_i.eq(Mux(self.o_addr == 0x0001, self.o_port, data_ir))

    return m
