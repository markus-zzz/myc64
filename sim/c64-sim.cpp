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

#include "Vtop.h"
#include "Vtop_spram2phase__A10_D8.h"
#include "Vtop_spram2phase__D4.h"
#include "Vtop_spram__A10_D8.h"
#include "Vtop_spram__D4.h"
#include "Vtop_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <assert.h>
#include <cairo.h>
#include <fstream>
#include <gdk/gdkkeysyms.h>
#include <gtk/gtk.h>
#include <list>
#include <map>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define XRES 403
#define YRES 284

static const struct {
  const char *C64Key;
  uint8_t PAIdx;
  uint8_t PBIdx;
} KeyInfo[] = {
#define DEF_KEY(a, b, c) {a, b, c},
#include "keys.def"
#undef DEF_KEY
};

static Vtop *tb = NULL;
static VerilatedVcdC *trace = NULL;
static unsigned tick = 0;
static const char *InjectKeyStringPtr = nullptr;

struct CommandAtFrame {
  CommandAtFrame(int FrameIdx) : m_FrameIdx(FrameIdx) {}
  virtual void execute() = 0;
  int m_FrameIdx;
};

struct CommandLoadPRG : public CommandAtFrame {
  CommandLoadPRG(int FrameIdx, const char *PathToPRG)
      : CommandAtFrame(FrameIdx), m_PathToPRG(PathToPRG) {}
  void execute() override {
    FILE *fp = fopen(m_PathToPRG, "rb");
    uint16_t loadAddress;
    size_t res;
    res = fread(&loadAddress, sizeof(loadAddress), 1, fp);
    while (!feof(fp)) {
      uint8_t byte;
      res = fread(&byte, sizeof(byte), 1, fp);
      tb->top->u_ram_main->u_spram->mem[loadAddress++] = byte;
    }
    fclose(fp);
  }
  const char *m_PathToPRG;
};

struct CommandDumpRAM : public CommandAtFrame {
  CommandDumpRAM(int FrameIdx, uint16_t Address, uint16_t Size)
      : CommandAtFrame(FrameIdx), m_Address(Address), m_Size(Size) {}
  void execute() override {
    uint8_t *p = tb->top->u_ram_main->u_spram->mem;
    for (uint16_t i = 0; i < m_Size; i++) {
      if (i % 16 == 0)
        printf("\n%04x: ", m_Address + i);
      uint8_t b = p[m_Address + i];
      printf(" %02x", b);
    }
    printf("\n");
  }
  uint16_t m_Address;
  uint16_t m_Size;
};

struct CommandInjectKeys : public CommandAtFrame {
  CommandInjectKeys(int FrameIdx, const char *Keys)
      : CommandAtFrame(FrameIdx), m_Keys(Keys) {}
  void execute() override { InjectKeyStringPtr = m_Keys; }
  const char *m_Keys;
};

std::list<CommandAtFrame *> Commands;

GdkPixbuf *FramePixBuf;
static int FrameIdx = -1;

static struct {
  int scale;
  int frame_rate;
  int save_frame_from;
  int save_frame_to;
  const char *save_frame_prefix;
  int exit_after_frame;
  int exit_after_cycle;
  bool trace;
} options;

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

static gboolean on_draw_event(GtkWidget *widget, cairo_t *cr,
                              gpointer user_data) {
  (void)widget;
  (void)user_data;
  cairo_scale(cr, options.scale, options.scale);
  gdk_cairo_set_source_pixbuf(cr, FramePixBuf, 0.0, 0.0);
  cairo_paint(cr);
  cairo_fill(cr);

  /* Draw some text */
  cairo_identity_matrix(cr);
  cairo_select_font_face(cr, "monospace", CAIRO_FONT_SLANT_NORMAL,
                         CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, 20);
  cairo_set_source_rgb(cr, 255, 255, 255);
  cairo_move_to(cr, 10, 15);
  char buf[64];
  snprintf(buf, sizeof(buf), "Frame #%03d, KeyboardMask=0x%016lx", FrameIdx,
           tb->i_keyboard_mask);
  cairo_show_text(cr, buf);

  return FALSE;
}

static gboolean on_key_press(GtkWidget *widget, GdkEventKey *event,
                             gpointer user_data) {
  (void)widget;
  (void)user_data;
#if 0
  auto key = KeyMap[event->hardware_keycode];
  int pa = std::get<0>(key);
  int pb = std::get<1>(key);
  uint64_t mask = 1ULL << (pa * 8 + pb);
  tb->i_keyboard_mask |= mask;
#endif
  return FALSE;
}

static gboolean on_key_release(GtkWidget *widget, GdkEventKey *event,
                               gpointer user_data) {
  (void)widget;
  (void)user_data;
#if 0
  auto key = KeyMap[event->hardware_keycode];
  int pa = std::get<0>(key);
  int pb = std::get<1>(key);
  uint64_t mask = 1ULL << (pa * 8 + pb);
  tb->i_keyboard_mask &= ~mask;
#endif
  return FALSE;
}

int clk_cb() {
  static int hcntr = 0;
  static int vcntr = 0;

  int frame_done = 0;

  if (tb->o_hsync) {
    hcntr = 0;
    vcntr++;
  }
  if (tb->o_vsync) {
    vcntr = 0;
    frame_done = 1;
  }

  int hcntr_shifted = hcntr - 70;
  int vcntr_shifted = vcntr - 10;
  if (0 <= hcntr_shifted && hcntr_shifted < XRES && 0 <= vcntr_shifted &&
      vcntr_shifted < YRES) {
    guchar red = tb->o_pixel >> 16;
    guchar green = tb->o_pixel >> 8;
    guchar blue = tb->o_pixel & 0xff;
    put_pixel(FramePixBuf, hcntr_shifted, vcntr_shifted, red, green, blue);
  }

  hcntr++;

  return frame_done;
}

static gboolean timeout_handler(GtkWidget *widget) {
  while (!Verilated::gotFinish()) {
    tb->clk = 1;
    tb->eval();
    if (trace)
      trace->dump(tick++);
    tb->clk = 0;
    tb->eval();
    if (trace)
      trace->dump(tick++);

    if (tick > options.exit_after_cycle)
      exit(0);

    if (clk_cb()) {
      FrameIdx++;
      gtk_widget_queue_draw(widget);

      if (!Commands.empty() && FrameIdx >= Commands.front()->m_FrameIdx) {
        Commands.front()->execute();
        Commands.pop_front();
      }
      static int KeyWaitFrameIdx = 0;
      if (FrameIdx >= KeyWaitFrameIdx && InjectKeyStringPtr &&
          *InjectKeyStringPtr != '\0') {
        if (tb->i_keyboard_mask) {
          tb->i_keyboard_mask = 0;
          KeyWaitFrameIdx = FrameIdx + 1;
        } else {
          // Inject key press.
          bool IsModifier;
          do {
            IsModifier = false;
            size_t Rem = strlen(InjectKeyStringPtr);
            for (int i = 0; i < sizeof(KeyInfo) / sizeof(KeyInfo[0]); i++) {
              size_t KeyLen = strlen(KeyInfo[i].C64Key);
              if (!strncmp(InjectKeyStringPtr, KeyInfo[i].C64Key,
                           std::min<size_t>(Rem, KeyLen))) {
                uint64_t mask = 1ULL
                                << (KeyInfo[i].PAIdx * 8 + KeyInfo[i].PBIdx);
                tb->i_keyboard_mask |= mask;
                InjectKeyStringPtr += KeyLen;
                KeyWaitFrameIdx = FrameIdx + 1;
                if (!strcmp("<LSHIFT>", KeyInfo[i].C64Key) ||
                    !strcmp("<RSHIFT>", KeyInfo[i].C64Key))
                  IsModifier = true;
                break;
              }
            }
          } while (IsModifier);
        }
      }

      if (options.save_frame_from <= FrameIdx &&
          FrameIdx <= options.save_frame_to) {
        char buf[128];
        snprintf(buf, sizeof(buf), "%s_%03d.png", options.save_frame_prefix,
                 FrameIdx);
        gdk_pixbuf_save(FramePixBuf, buf, "png", NULL, NULL);
      }

      if (FrameIdx >= options.exit_after_frame) {
        exit(0);
      }

      if (trace)
        trace->flush();

      return TRUE;
    }
  }

  return TRUE;
}

static void print_usage(const char *prog) {
  // clang-format off
  fprintf(stderr, "Usage: %s [OPTIONS]\n\n", prog);
  fprintf(stderr, "  --scale=N             -- set pixel scaling\n");
  fprintf(stderr, "  --frame-rate=N        -- try to produce a new frame every N ms\n");
  fprintf(stderr, "  --save-frame-from=N   -- dump frames to .png starting from frame #N\n");
  fprintf(stderr, "  --save-frame-to=N=N   -- dump frames to .png ending with frame #N\n");
  fprintf(stderr, "  --save-frame-prefix=S -- prefix dump frame files with S\n");
  fprintf(stderr, "  --exit-after-frame=N  -- exit after frame #N\n");
  fprintf(stderr, "  --trace               -- create dump.vcd\n");
  fprintf(stderr, "  --cmd-load-prg=<FRAME>:<PRG>           -- wait until <FRAME> then load <PRG>\n");
  fprintf(stderr, "  --cmd-inject-keys=<FRAME>:<KEYS>       -- wait until <FRAME> then inject <KEYS>\n");
  fprintf(stderr, "  --cmd-dump-ram=<FRAME>:<ADDR>:<LENGTH> -- wait until <FRAME> then dump <LENGTH> bytes of RAM starting at <ADDR>\n");
  fprintf(stderr, "\n");
  // clang-format on
}

static void parse_cmd_args(int argc, char *argv[]) {
  int off;
#define MATCH(x) (!strncmp(argv[i], x, strlen(x)) && (off = strlen(x)))
  for (int i = 1; i < argc; i++) {
    if (MATCH("--scale=")) {
      options.scale = strtol(&argv[i][off], NULL, 0);
    } else if (MATCH("--frame-rate=")) {
      options.frame_rate = strtol(&argv[i][off], NULL, 0);
    } else if (MATCH("--save-frame-from=")) {
      options.save_frame_from = strtol(&argv[i][off], NULL, 0);
    } else if (MATCH("--save-frame-to=")) {
      options.save_frame_to = strtol(&argv[i][off], NULL, 0);
    } else if (MATCH("--save-frame-prefix=")) {
      options.save_frame_prefix = &argv[i][off];
    } else if (MATCH("--exit-after-frame=")) {
      options.exit_after_frame = strtol(&argv[i][off], NULL, 0);
    } else if (MATCH("--exit-after-cycle=")) {
      options.exit_after_cycle = strtol(&argv[i][off], NULL, 0);
    } else if (MATCH("--trace")) {
      options.trace = true;
    } else if (MATCH("--cmd-inject-keys=")) {
      char *EndPtr;
      int CmdFrameIdx = strtol(&argv[i][off], &EndPtr, 0);
      if (*EndPtr != ':') {
        print_usage(argv[0]);
        exit(1);
      }
      EndPtr++;
      Commands.push_back(new CommandInjectKeys(CmdFrameIdx, EndPtr));
    } else if (MATCH("--cmd-dump-ram=")) {
      char *EndPtr;
      int CmdFrameIdx = strtol(&argv[i][off], &EndPtr, 0);
      if (*EndPtr != ':') {
        print_usage(argv[0]);
        exit(1);
      }
      EndPtr++;
      uint16_t Address = strtol(EndPtr, &EndPtr, 0);
      if (*EndPtr != ':') {
        print_usage(argv[0]);
        exit(1);
      }
      EndPtr++;
      uint16_t Size = strtol(EndPtr, &EndPtr, 0);
      if (*EndPtr != '\0') {
        print_usage(argv[0]);
        exit(1);
      }
      Commands.push_back(new CommandDumpRAM(CmdFrameIdx, Address, Size));
    } else if (MATCH("--cmd-load-prg=")) {
      char *EndPtr;
      int CmdFrameIdx = strtol(&argv[i][off], &EndPtr, 0);
      if (*EndPtr != ':') {
        print_usage(argv[0]);
        exit(1);
      }
      EndPtr++;
      Commands.push_back(new CommandLoadPRG(CmdFrameIdx, EndPtr));
    } else {
      print_usage(argv[0]);
      exit(1);
    }
  }
}

int main(int argc, char *argv[]) {

  GtkWidget *window;
  GtkWidget *darea;

  gtk_init(&argc, &argv);

  // Set default options.
  options.scale = 3;
  options.frame_rate = 0;
  options.save_frame_from = INT_MAX;
  options.save_frame_to = INT_MAX;
  options.save_frame_prefix = "frame";
  options.exit_after_frame = INT_MAX;
  options.exit_after_cycle = INT_MAX;
  options.trace = false;

  parse_cmd_args(argc, argv);

  window = gtk_window_new(GTK_WINDOW_TOPLEVEL);

  darea = gtk_drawing_area_new();
  gtk_container_add(GTK_CONTAINER(window), darea);

  g_signal_connect(G_OBJECT(darea), "draw", G_CALLBACK(on_draw_event), NULL);
  g_signal_connect(G_OBJECT(window), "key_press_event",
                   G_CALLBACK(on_key_press), NULL);
  g_signal_connect(G_OBJECT(window), "key_release_event",
                   G_CALLBACK(on_key_release), NULL);
  g_signal_connect(G_OBJECT(window), "destroy", G_CALLBACK(gtk_main_quit),
                   NULL);
  if (options.frame_rate) {
    g_timeout_add(options.frame_rate, (GSourceFunc)timeout_handler, window);
  } else {
    g_idle_add((GSourceFunc)timeout_handler, window);
  }

  gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
  gtk_window_set_default_size(GTK_WINDOW(window), XRES * options.scale,
                              YRES * options.scale);
  gtk_window_set_title(GTK_WINDOW(window), argv[0]);

  gtk_widget_show_all(window);

  FramePixBuf = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8, XRES, YRES);

  // Initialize Verilators variables
  Verilated::commandArgs(argc, argv);

  Verilated::traceEverOn(options.trace);

  tb = new Vtop;

  if (options.trace) {
    trace = new VerilatedVcdC;
    tb->trace(trace, 99);
    trace->open("dump.vcd");
  }

  // Apply five cycles with reset active.
  tb->rst = 1;
  for (unsigned i = 0; i < 5; i++) {
    tb->clk = 1;
    tb->eval();
    if (trace)
      trace->dump(tick++);
    tb->clk = 0;
    tb->eval();
    if (trace)
      trace->dump(tick++);
  }
  tb->rst = 0;

#if 0
  {
    char idx = 0;
    for (int r = 0; r < 25; r++) {
      for (int c = 0; c < 40; c++) {
        tb->top->u_ram_main->u_spram->mem[0x400 + r * 40 + c] = 0x20;
        tb->top->u_ram_color->u_spram->mem[r * 40 + c] = idx++;
      }
    }
    tb->top->u_ram_main->u_spram->mem[0x400 + 0 * 40 + 0] = 1;
    tb->top->u_ram_main->u_spram->mem[0x400 + 0 * 40 + 1] = 2;
    tb->top->u_ram_main->u_spram->mem[0x400 + 0 * 40 + 2] = 3;
#if 1
    for (int r = 0; r < 25; r++) {
      tb->top->u_ram_main->u_spram->mem[0x400 + r * 40 + 0] = 1;
      tb->top->u_ram_main->u_spram->mem[0x400 + r * 40 + 39] = 2;
    }
    for (int c = 0; c < 40; c++) {
      tb->top->u_ram_main->u_spram->mem[0x400 + 0 * 40 + c] = 3;
      tb->top->u_ram_main->u_spram->mem[0x400 + 24 * 40 + c] = 4;
    }
#endif
  }
#endif

  gtk_main();

  return 0;
}
