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

#include <assert.h>
#include <cairo.h>
#include <fstream>
#include <gdk/gdkkeysyms.h>
#include <gtk/gtk.h>
#include <libusb.h>
#include <list>
#include <map>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

std::map<int, guint> FdToSourceId;

gboolean handleLibUsbEvents(GIOChannel *source, GIOCondition condition,
                            gpointer data) {
  struct timeval tv_zero;
  memset(&tv_zero, 0, sizeof(tv_zero));
  int res = libusb_handle_events_timeout(NULL, &tv_zero);
  assert(res == 0);

  return TRUE;
}
void addLibUsbFd(int fd, short events, void *user_data) {
  int Mask = 0;
  if (events & POLLIN)
    Mask |= G_IO_IN;
  if (events & POLLOUT)
    Mask |= G_IO_OUT;
  GIOCondition Cond = static_cast<GIOCondition>(Mask);
  GIOChannel *Ch = g_io_channel_unix_new(fd);
  guint SourceId = g_io_add_watch(Ch, Cond, handleLibUsbEvents, NULL);
  FdToSourceId[fd] = SourceId;
}

void delLibUsbFd(int fd, void *user_data) {
  assert(FdToSourceId.find(fd) != FdToSourceId.end());
  guint SourceId = FdToSourceId[fd];
  g_source_remove(SourceId);
}

static struct libusb_transfer *MyC64KeybIntTransf;
static uint8_t MyC64KeybData[8];
static bool MyC64KeybBusy = false;
static uint64_t MyC64KeybMaskCurr = 0;
static uint64_t MyC64KeybMaskNext = 0;

static libusb_device_handle *MyC64DevHandle = NULL;

void MyC64KeybSubmit() {
  if (MyC64KeybMaskNext != MyC64KeybMaskCurr && !MyC64KeybBusy) {
    memcpy(MyC64KeybData, &MyC64KeybMaskNext, sizeof(MyC64KeybMaskNext));
    int res = libusb_submit_transfer(MyC64KeybIntTransf);
    assert(res == 0);
    MyC64KeybBusy = true;
    MyC64KeybMaskCurr = MyC64KeybMaskNext;
  }
}
void MyC64KeybDataCB(struct libusb_transfer *transfer) {
  assert(transfer->status == LIBUSB_TRANSFER_COMPLETED);
  MyC64KeybBusy = false;
  MyC64KeybSubmit();
  return;
}

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

static gboolean on_draw_event(GtkWidget *widget, cairo_t *cr,
                              gpointer user_data) {
  (void)widget;
  (void)user_data;

  /* Draw some text */
  cairo_identity_matrix(cr);
  cairo_select_font_face(cr, "monospace", CAIRO_FONT_SLANT_NORMAL,
                         CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, 200);
  cairo_set_source_rgb(cr, 70, 50, 255);
  cairo_move_to(cr, 10, 15);
  cairo_show_text(cr, "MyC64");

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
      MyC64KeybMaskNext |= mask;
      break;
    }
  }

  MyC64KeybSubmit();

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
      MyC64KeybMaskNext &= ~mask;
      break;
    }
  }

  MyC64KeybSubmit();

  return FALSE;
}

void MyC64LoadPrgCB(struct libusb_transfer *transfer);

class PrgLoader {
public:
  PrgLoader(const char *path) {
    FILE *fp = fopen(path, "rb");
    size_t res;
    fseek(fp, 0, SEEK_END);
    m_PrgSize = ftell(fp) - sizeof(uint16_t);
    rewind(fp);
    res = fread(&m_PrgStartAddr, sizeof(m_PrgStartAddr), 1, fp);
    assert(res == 1);
    m_PrgBuffer = new uint8_t[m_PrgSize];
    res = fread(m_PrgBuffer, m_PrgSize, 1, fp);
    assert(res == 1);
    fclose(fp);

    m_Transf = libusb_alloc_transfer(0);
    m_TransfBuffer = new uint8_t[MaxTransfSize];
    m_PrgEndAddr = m_PrgStartAddr + m_PrgSize;
    m_PrgSentSize = 0;

    uint16_t ChunkSize = std::min<uint16_t>(m_PrgSize, MaxTransfSize - 8);
    sendMemWrite(m_PrgStartAddr, ChunkSize, m_PrgBuffer);
    m_PrgPendSize = ChunkSize;
    m_CurrState = s_data;
  }

  void sendMemWriteCallBack(struct libusb_transfer *Transfer) {
    if (Transfer->status == LIBUSB_TRANSFER_COMPLETED) {
      m_CurrState = m_NextState;
      m_PrgSentSize += m_PrgPendSize;
    } else {
      // XXX: Allow for a few retries, not infinitely many.
      printf("usb error - retry.\n");
    }

    switch (m_CurrState) {
    case s_data: {
      uint16_t ChunkSize =
          std::min<uint16_t>(m_PrgSize - m_PrgSentSize, MaxTransfSize - 8);
      if (ChunkSize > 0) {
        sendMemWrite(m_PrgStartAddr + m_PrgSentSize, ChunkSize,
                     &m_PrgBuffer[m_PrgSentSize]);
        m_PrgPendSize = ChunkSize;
      } else {
        // Update various zero page pointers to adjust for loaded program.
        // - Pointer to beginning of variable area. (End of program plus 1.)
        // - Pointer to beginning of array variable area.
        // - Pointer to end of array variable area.
        // - Load address read from input file and pointer to current byte
        // during LOAD/VERIFY from serial bus.
        //   End address after LOAD/VERIFY from serial bus or datasette.
        // For details see https://sta.c64.org/cbm64mem.html and
        // VICE source: src/c64/c64mem.c:mem_set_basic_text()
        // ram[0x2d] = ram[0x2f] = ram[0x31] = ram[0xae] = loadAddress & 0xff;
        // ram[0x2e] = ram[0x30] = ram[0x32] = ram[0xaf] = loadAddress >> 8;

        sendMemWrite(0x002d, sizeof(m_PrgEndAddr), (uint8_t *)&m_PrgEndAddr);
        m_NextState = s_basic_0;
      }
    } break;
    case s_basic_0:
      sendMemWrite(0x002f, sizeof(m_PrgEndAddr), (uint8_t *)&m_PrgEndAddr);
      m_NextState = s_basic_1;
      break;
    case s_basic_1:
      sendMemWrite(0x0031, sizeof(m_PrgEndAddr), (uint8_t *)&m_PrgEndAddr);
      m_NextState = s_basic_2;
      break;
    case s_basic_2:
      sendMemWrite(0x00ae, sizeof(m_PrgEndAddr), (uint8_t *)&m_PrgEndAddr);
      m_NextState = s_done;
      break;
    case s_done:
      printf("Done loading .prg\n");
      break;
    }
  }

private:
  void sendMemWrite(uint16_t DstAddr, uint16_t Length, uint8_t *Data) {
    assert(Length <= MaxTransfSize - 8);
    libusb_fill_control_setup(&m_TransfBuffer[0], 0x42, 0x01, DstAddr, 0,
                              Length);
    memcpy(&m_TransfBuffer[8], Data, Length);
    libusb_fill_control_transfer(m_Transf, MyC64DevHandle, m_TransfBuffer,
                                 MyC64LoadPrgCB, NULL, 2500);
    m_Transf->user_data = this;
    int res = libusb_submit_transfer(m_Transf);
    assert(res == 0);
  }

  const uint16_t MaxTransfSize =
      2048; // Max control transfer size on Linux is 4096.

  enum {
    s_data,
    s_basic_0,
    s_basic_1,
    s_basic_2,
    s_done
  } m_CurrState,
      m_NextState;

  uint8_t *m_PrgBuffer;
  uint16_t m_PrgStartAddr;
  uint16_t m_PrgEndAddr;
  uint16_t m_PrgSize;
  uint16_t m_PrgPendSize;
  uint16_t m_PrgSentSize;

  struct libusb_transfer *m_Transf;
  uint8_t *m_TransfBuffer;
};

void MyC64LoadPrgCB(struct libusb_transfer *transfer) {
  static_cast<PrgLoader *>(transfer->user_data)->sendMemWriteCallBack(transfer);
}

int main(int argc, char *argv[]) {

  GtkWidget *window;
  GtkWidget *darea;

  gtk_init(&argc, &argv);

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

  gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
  gtk_window_set_title(GTK_WINDOW(window), argv[0]);

  gtk_widget_show_all(window);

  int res = libusb_init(NULL);
  assert(res == LIBUSB_SUCCESS);
  MyC64DevHandle = libusb_open_device_with_vid_pid(NULL, 0xabc0, 0x0064);
  assert(MyC64DevHandle);
  res = libusb_set_configuration(MyC64DevHandle, 1);
  assert(res == 0);
  res = libusb_claim_interface(MyC64DevHandle, 0);
  assert(res == 0);

  MyC64KeybIntTransf = libusb_alloc_transfer(0);
  libusb_fill_interrupt_transfer(MyC64KeybIntTransf, MyC64DevHandle, 0x1,
                                 MyC64KeybData, 8, MyC64KeybDataCB, NULL, 0);
  res = libusb_submit_transfer(MyC64KeybIntTransf);
  assert(res == 0);

  if (argc > 1)
    new PrgLoader(argv[1]);

  const struct libusb_pollfd **fds = libusb_get_pollfds(NULL);
  for (int i = 0; fds[i]; i++)
    addLibUsbFd(fds[i]->fd, fds[i]->events, NULL);
  libusb_set_pollfd_notifiers(NULL, addLibUsbFd, delLibUsbFd, NULL);

  gtk_main();

  return 0;
}
