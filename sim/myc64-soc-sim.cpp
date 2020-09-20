/*
 * Copyright (C) 2019-2020 Markus Lavin (https://www.zzzconsulting.se/)
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

#include "Vmyc64_soc_top.h"
#include "Vmyc64_soc_top_myc64_soc_top.h"
#include "Vmyc64_soc_top_myc64_top.h"
#include "Vmyc64_soc_top_spram2phase__A10_D8.h"
#include "Vmyc64_soc_top_spram2phase__D4.h"
#include "Vmyc64_soc_top_spram__A10_D8.h"
#include "Vmyc64_soc_top_spram__D4.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <assert.h>
#include <fstream>
#include <functional>
#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vector>

static Vmyc64_soc_top *dut = NULL;
static VerilatedVcdC *trace = NULL;
static unsigned TraceTick = 0;

double sc_time_stamp() { return TraceTick; }

class ClockManager {
  using ClockCB = std::function<void(void)>;
  struct Clock {
    Clock(CData *clk_net, double freq, uint64_t offset_ps, ClockCB CallBack) {
      m_clk_net = clk_net;
      m_cycle_time_ps = 1e12 / freq;
      m_next_time_ps = offset_ps;
      m_CallBack = CallBack;
    }
    CData *m_clk_net;
    double m_freq;
    uint64_t m_cycle_time_ps;
    uint64_t m_next_time_ps;
    ClockCB m_CallBack;
  };

  std::vector<Clock> m_Clocks;
  uint64_t m_CurrTimePS = 0;

  Clock *getNext() {
    Clock *FirstClock = &m_Clocks[0];
    for (Clock &C : m_Clocks)
      if (C.m_next_time_ps < FirstClock->m_next_time_ps)
        FirstClock = &C;
    return FirstClock;
  }

public:
  void addClock(CData *clk_net, double freq, uint64_t offset_ps,
                ClockCB CallBack = std::function<void(void)>()) {
    m_Clocks.emplace_back(Clock(clk_net, freq, offset_ps, CallBack));
  }
  void doWork() {
    Clock *C = getNext();
    dut->eval();
    dut->eval();
    if (trace)
      trace->dump(m_CurrTimePS);
    m_CurrTimePS = C->m_next_time_ps;
    *C->m_clk_net = !(*C->m_clk_net);
    dut->eval();
    dut->eval();
    if (trace)
      trace->dump(m_CurrTimePS);
    C->m_next_time_ps += C->m_cycle_time_ps / 2;

    if (C->m_CallBack)
      C->m_CallBack();
  }
};

static void put_pixel(GdkPixbuf *pixbuf, int x, int y, guchar red, guchar green,
                      guchar blue) {
  int width, height, rowstride, n_channels;
  guchar *pixels, *p;

  n_channels = gdk_pixbuf_get_n_channels(pixbuf);

  g_assert(gdk_pixbuf_get_colorspace(pixbuf) == GDK_COLORSPACE_RGB);
  g_assert(gdk_pixbuf_get_bits_per_sample(pixbuf) == 8);
  g_assert(!gdk_pixbuf_get_has_alpha(pixbuf));
  g_assert(n_channels == 3);

  width = gdk_pixbuf_get_width(pixbuf);
  height = gdk_pixbuf_get_height(pixbuf);

  g_assert(x >= 0 && x < width);
  g_assert(y >= 0 && y < height);

  rowstride = gdk_pixbuf_get_rowstride(pixbuf);
  pixels = gdk_pixbuf_get_pixels(pixbuf);

  p = pixels + y * rowstride + x * n_channels;
  p[0] = red;
  p[1] = green;
  p[2] = blue;
}

struct VICIIFrameDumper {
  VICIIFrameDumper() {
    m_FramePixBuf =
        gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, c_Xres, c_Yres);
  }
  void operator()() {
    if (dut->clk_15mhz) {
      bool FrameDone = false;

      if (dut->myc64_soc_top->hsync) {
        m_HCntr = 0;
        m_VCntr++;
      }
      if (dut->myc64_soc_top->vsync) {
        m_VCntr = 0;
        FrameDone = true;
      }

      unsigned m_HCntrShifted = m_HCntr - 70;
      unsigned m_VCntrShifted = m_VCntr - 10;
      if (0 <= m_HCntrShifted && m_HCntrShifted < c_Xres &&
          0 <= m_VCntrShifted && m_VCntrShifted < c_Yres) {
        guchar Red = dut->myc64_soc_top->c64_color_rgb >> 16;
        guchar Green = dut->myc64_soc_top->c64_color_rgb >> 8;
        guchar Blue = dut->myc64_soc_top->c64_color_rgb & 0xff;
        put_pixel(m_FramePixBuf, m_HCntrShifted, m_VCntrShifted, Red, Green,
                  Blue);
      }

      m_HCntr++;

      if (FrameDone) {
        char buf[32];
        snprintf(buf, sizeof(buf), "vicii-%03d.png", m_FrameIdx++);
        gdk_pixbuf_save(m_FramePixBuf, buf, "png", NULL, NULL);
      }
    }
  }

private:
  const unsigned c_Xres = 504;
  const unsigned c_Yres = 312;
  GdkPixbuf *m_FramePixBuf;
  unsigned m_FrameIdx = 0;
  unsigned m_HCntr = 0;
  unsigned m_VCntr = 0;
};

struct VGAFrameDumper {
  VGAFrameDumper() {
    m_FramePixBuf =
        gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, c_Xres, c_Yres);
  }
  void operator()() {
    if (dut->clk_25mhz) {
      if (!prev_vga_vsync && dut->o_vga_vsync) {
        char buf[32];
        snprintf(buf, sizeof(buf), "vga-%03d.png", m_FrameIdx++);
        gdk_pixbuf_save(m_FramePixBuf, buf, "png", NULL, NULL);
        m_X = 0;
        m_Y = 0;
      } else if (!prev_vga_hsync && dut->o_vga_hsync) {
        m_X = 0;
        m_Y++;
      } else if (!dut->o_vga_blank) {
        guchar red = dut->o_vga_color_rgb >> 16;
        guchar green = dut->o_vga_color_rgb >> 8;
        guchar blue = dut->o_vga_color_rgb & 0xff;
        if (m_X < c_Xres && m_Y < c_Yres) {
          put_pixel(m_FramePixBuf, m_X, m_Y, red, green, blue);
        }
        m_X++;
      }
      prev_vga_hsync = dut->o_vga_hsync;
      prev_vga_vsync = dut->o_vga_vsync;
    }
  }

private:
  const unsigned c_Xres = 640;
  const unsigned c_Yres = 480;
  GdkPixbuf *m_FramePixBuf;
  unsigned m_FrameIdx = 0;
  unsigned m_X = 0;
  unsigned m_Y = 0;
  int prev_vga_hsync = 0;
  int prev_vga_vsync = 0;
};

int main(int argc, char *argv[]) {
  bool TraceOn = false;
  // Initialize Verilators variables
  Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(TraceOn);

  dut = new Vmyc64_soc_top;

  if (TraceOn) {
    trace = new VerilatedVcdC;
    trace->set_time_unit("1ps");
    trace->set_time_resolution("1ps");
    dut->trace(trace, 99);
    trace->open("dump.vcd");
  }

  VICIIFrameDumper myVICIIFrameDumper;
  VGAFrameDumper myVGAFrameDumper;

  ClockManager CM;
  CM.addClock(&dut->clk_15mhz, 15e6, 5000, myVICIIFrameDumper);
  CM.addClock(&dut->clk_25mhz, 25e6, 6000, myVGAFrameDumper);
  CM.addClock(&dut->clk_125mhz, 125e6, 7000);

  dut->rst_15mhz = 1;
  dut->rst_25mhz = 1;
  dut->rst_125mhz = 1;
  dut->eval();
  if (trace)
    trace->dump(0);

#if 1
  // Initialize Screen RAM (area) and Color RAM with pattern.
  {
    uint8_t *ColorRAM = dut->myc64_soc_top->u_myc64->u_ram_color->u_spram->mem;
    uint8_t *MainRAM = dut->myc64_soc_top->u_myc64->u_ram_main->u_spram->mem;
    char idx = 0;
    for (int r = 0; r < 25; r++) {
      for (int c = 0; c < 40; c++) {
        MainRAM[0x400 + r * 40 + c] = idx;
        ColorRAM[r * 40 + c] = idx++;
      }
    }
  }
#endif

  unsigned idx = 0;
  while (!Verilated::gotFinish()) {
    if (idx++ > 32) {
      dut->rst_15mhz = 0;
      dut->rst_25mhz = 0;
      dut->rst_125mhz = 0;
    }
    CM.doWork();
    if (trace)
      trace->flush();
  }

  return 0;
}
