#!/bin/bash

set -e

rm -rf obj_dir

verilator -trace -cc ../rtl/*.v +1364-2005ext+v --top-module top -Wno-fatal
VERILATOR_ROOT=/usr/share/verilator/
cd obj_dir; make -f Vtop.mk; cd ..
g++ -std=c++14 c64-sim.cpp obj_dir/Vtop__ALL.a -I obj_dir/ -I $VERILATOR_ROOT/include/ -I $VERILATOR_ROOT/include/vltstd $VERILATOR_ROOT/include/verilated.cpp $VERILATOR_ROOT/include/verilated_vcd_c.cpp -Werror -I. -o myc64-sim -O0 -g3 `pkg-config --cflags --libs gtk+-3.0`
