#!/bin/bash

set -e

OBJ_DIR=obj_dir_myc64
rm -rf $OBJ_DIR

echo "nMigen..."
python ../rtl/myc64/myc64.py generate > nmigen.v
echo "verilator..."
verilator -trace -cc ../rtl/myc64/*.v nmigen.v +1364-2005ext+v --top-module myc64_top -Wno-fatal --Mdir $OBJ_DIR -comp-limit-members 1024

VERILATOR_ROOT=/usr/share/verilator/
cd $OBJ_DIR; make -f Vmyc64_top.mk; cd ..
g++ -std=c++14 myc64-sim.cpp $OBJ_DIR/Vmyc64_top__ALL.a -I$OBJ_DIR -I $VERILATOR_ROOT/include/ -I $VERILATOR_ROOT/include/vltstd $VERILATOR_ROOT/include/verilated.cpp $VERILATOR_ROOT/include/verilated_vcd_c.cpp -Werror -I../sw -o myc64-sim -O0 -g3 `pkg-config --cflags --libs gtk+-3.0`
