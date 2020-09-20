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

#include "Vmyc64_top.h"
#include "Vmyc64_top_myc64_top.h"
#include "Vmyc64_top_spram2phase__A10_D8.h"
#include "Vmyc64_top_spram2phase__D4.h"
#include "Vmyc64_top_spram__A10_D8.h"
#include "Vmyc64_top_spram__D4.h"
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
  uint16_t KeyCode;
} KeyInfo[] = {
#define DEF_KEY(a, b, c, d) {a, b, c, d},
#include "keys.def"
#undef DEF_KEY
};

static Vmyc64_top *dut = NULL;
static VerilatedVcdC *trace = NULL;
static unsigned TraceTick = 0;
static unsigned Cycle = 0;
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
    uint8_t *RAM = dut->myc64_top->u_ram_main->u_spram->mem;
    FILE *fp = fopen(m_PathToPRG, "rb");
    fseek(fp, 0, SEEK_END);
    uint16_t PrgSize = ftell(fp) - sizeof(uint16_t);
    rewind(fp);
    uint16_t PrgStartAddr;
    size_t res;
    res = fread(&PrgStartAddr, sizeof(PrgStartAddr), 1, fp);
    assert(res == 1);
    res = fread(&RAM[PrgStartAddr], PrgSize, 1, fp);
    assert(res == 1);
    fclose(fp);

    // Update various zero page pointers to adjust for loaded program.
    // - Pointer to beginning of variable area. (End of program plus 1.)
    // - Pointer to beginning of array variable area.
    // - Pointer to end of array variable area.
    // - Load address read from input file and pointer to current byte during
    // LOAD/VERIFY from serial bus.
    //   End address after LOAD/VERIFY from serial bus or datasette.
    // For details see https://sta.c64.org/cbm64mem.html and
    // VICE source: src/c64/c64mem.c:mem_set_basic_text()
    uint16_t PrgEndAddr = PrgStartAddr + PrgSize;
    RAM[0x2d] = RAM[0x2f] = RAM[0x31] = RAM[0xae] = PrgEndAddr & 0xff;
    RAM[0x2e] = RAM[0x30] = RAM[0x32] = RAM[0xaf] = PrgEndAddr >> 8;
  }
  const char *m_PathToPRG;
};

struct CommandDumpRAM : public CommandAtFrame {
  CommandDumpRAM(int FrameIdx, uint16_t Address, uint16_t Size)
      : CommandAtFrame(FrameIdx), m_Address(Address), m_Size(Size) {}
  void execute() override {
    uint8_t *p = dut->myc64_top->u_ram_main->u_spram->mem;
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
static std::vector<int16_t> SIDSamples;

static struct {
  int scale;
  int frame_rate;
  int save_frame_from;
  int save_frame_to;
  const char *save_frame_prefix;
  int exit_after_frame;
  bool trace;
} options;

static void saveWAV(std::vector<int16_t> &pcmSamples) {
  FILE *fp;
  fp = fopen("out.wav", "wb");

  char ChunkID[] = {'R', 'I', 'F', 'F'};
  uint32_t ChunkSize = 0;
  char Format[] = {'W', 'A', 'V', 'E'};

  char Subchunk1ID[] = {'f', 'm', 't', ' '};
  uint32_t Subchunk1Size = 16;
  uint16_t AudioFormat = 1;
  uint16_t NumChannels = 1;
  uint32_t SampleRate = 50000;
  uint16_t BitsPerSample = 16;
  uint32_t ByteRate = SampleRate * NumChannels * BitsPerSample / 8;
  uint16_t BlockAlign = NumChannels * BitsPerSample / 8;

  char Subchunk2ID[] = {'d', 'a', 't', 'a'};
  uint32_t Subchunk2Size = pcmSamples.size() * NumChannels * BitsPerSample / 8;
  ChunkSize = 36 + Subchunk2Size;

  // RIFF chunk descriptor.
  fwrite(&ChunkID[0], sizeof(ChunkID), 1, fp);
  fwrite(&ChunkSize, sizeof(ChunkSize), 1, fp);
  fwrite(&Format, sizeof(Format), 1, fp);

  // fmt sub-chunk.
  fwrite(&Subchunk1ID[0], sizeof(Subchunk1ID), 1, fp);
  fwrite(&Subchunk1Size, sizeof(Subchunk1Size), 1, fp);
  fwrite(&AudioFormat, sizeof(AudioFormat), 1, fp);
  fwrite(&NumChannels, sizeof(NumChannels), 1, fp);
  fwrite(&SampleRate, sizeof(SampleRate), 1, fp);
  fwrite(&ByteRate, sizeof(ByteRate), 1, fp);
  fwrite(&BlockAlign, sizeof(BlockAlign), 1, fp);
  fwrite(&BitsPerSample, sizeof(BitsPerSample), 1, fp);

  // data sub-chunk
  fwrite(&Subchunk2ID[0], sizeof(Subchunk2ID), 1, fp);
  fwrite(&Subchunk2Size, sizeof(Subchunk2Size), 1, fp);

  long NextDataPos = ftell(fp);
  for (unsigned i = 0; i < pcmSamples.size(); i++)
    fwrite(&pcmSamples[i], sizeof(int16_t), 1, fp);

  fclose(fp);
}

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
           dut->i_keyboard_mask);
  cairo_show_text(cr, buf);

  return FALSE;
}

static gboolean on_key_press(GtkWidget *widget, GdkEventKey *event,
                             gpointer user_data) {
  (void)widget;
  (void)user_data;
  for (int i = 0; i < sizeof(KeyInfo) / sizeof(KeyInfo[0]); i++) {
    if (KeyInfo[i].KeyCode == event->hardware_keycode) {
      int pa = KeyInfo[i].PAIdx;
      int pb = KeyInfo[i].PBIdx;
      uint64_t mask = 1ULL << (pa * 8 + pb);
      dut->i_keyboard_mask |= mask;
      break;
    }
  }
  return FALSE;
}

static gboolean on_key_release(GtkWidget *widget, GdkEventKey *event,
                               gpointer user_data) {
  (void)widget;
  (void)user_data;
  for (int i = 0; i < sizeof(KeyInfo) / sizeof(KeyInfo[0]); i++) {
    if (KeyInfo[i].KeyCode == event->hardware_keycode) {
      int pa = KeyInfo[i].PAIdx;
      int pb = KeyInfo[i].PBIdx;
      uint64_t mask = 1ULL << (pa * 8 + pb);
      dut->i_keyboard_mask &= ~mask;
      break;
    }
  }
  return FALSE;
}

int clk_cb() {
  static int hcntr = 0;
  static int vcntr = 0;

  int frame_done = 0;

  if (dut->o_hsync) {
    hcntr = 0;
    vcntr++;
  }
  if (dut->o_vsync) {
    vcntr = 0;
    frame_done = 1;
  }

  int hcntr_shifted = hcntr - 70;
  int vcntr_shifted = vcntr - 10;
  if (0 <= hcntr_shifted && hcntr_shifted < XRES && 0 <= vcntr_shifted &&
      vcntr_shifted < YRES) {
    guchar red = dut->o_color_rgb >> 16;
    guchar green = dut->o_color_rgb >> 8;
    guchar blue = dut->o_color_rgb & 0xff;
    put_pixel(FramePixBuf, hcntr_shifted, vcntr_shifted, red, green, blue);
  }

  hcntr++;

  // Sample at 50kHz but clock is 8Mhz.
  if (Cycle % (20 * 8) == 0)
    SIDSamples.push_back(dut->o_wave);

  return frame_done;
}

static gboolean timeout_handler(GtkWidget *widget) {
  while (!Verilated::gotFinish()) {
    // XXX: Need additional call to eval() see
    // https://zipcpu.com/blog/2018/09/06/tbclock.html
    dut->clk = 1;
    dut->eval();
    if (trace)
      trace->dump(TraceTick++);
    dut->clk = 0;
    dut->eval();
    if (trace)
      trace->dump(TraceTick++);

    Cycle++;

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
        if (dut->i_keyboard_mask) {
          dut->i_keyboard_mask = 0;
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
                dut->i_keyboard_mask |= mask;
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
        saveWAV(SIDSamples);
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

  dut = new Vmyc64_top;

  if (options.trace) {
    trace = new VerilatedVcdC;
    dut->trace(trace, 99);
    trace->open("dump.vcd");
  }

  // Apply five cycles with reset active.
  dut->rst = 1;
  for (unsigned i = 0; i < 5; i++) {
    dut->clk = 1;
    dut->eval();
    if (trace)
      trace->dump(TraceTick++);
    dut->clk = 0;
    dut->eval();
    if (trace)
      trace->dump(TraceTick++);
    Cycle++;
  }
  dut->rst = 0;

  gtk_main();

  return 0;
}
