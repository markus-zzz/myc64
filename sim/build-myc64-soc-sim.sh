#!/bin/bash

set -e
OBJ_DIR=obj_dir_myc64_soc
rm -rf $OBJ_DIR

verilator -trace -cc +1364-2005ext+v --top-module myc64_soc_top -Wno-fatal --Mdir $OBJ_DIR \
+define+MYC64_CHARACTERS_VH='"../roms/characters.vh"' \
+define+MYC64_BASIC_VH='"../roms/basic.vh"' \
+define+MYC64_KERNAL_VH='"../roms/kernal.vh"' \
+define+USBDEV_ROM_VH='"../../usbdev/sw/rom.vh"' \
../rtl/myc64/*.v \
../rtl/myc64-soc/*.v \
../../usbdev/rtl/crc16.v \
../../usbdev/rtl/crc5.v \
../../usbdev/rtl/usb-enc.v \
../../usbdev/rtl/picorv32.v \
../../usbdev/rtl/usb-dec.v \
../../usbdev/rtl/usb-sync.v \
../../usbdev/rtl/soc-top.v \
../../usbdev/rtl/usb-dev.v \
../../retrocon/rtl/vga_video.v

VERILATOR_ROOT=/usr/share/verilator/
cd $OBJ_DIR; make -f Vmyc64_soc_top.mk; cd ..
g++ -std=c++14 myc64-soc-sim.cpp $OBJ_DIR/Vmyc64_soc_top__ALL.a -I$OBJ_DIR/ -I$VERILATOR_ROOT/include/ -I$VERILATOR_ROOT/include/vltstd $VERILATOR_ROOT/include/verilated.cpp $VERILATOR_ROOT/include/verilated_vcd_c.cpp -Werror -I. -o myc64-soc-sim -O0 -g3 `pkg-config --cflags --libs gtk+-3.0`
