#!/bin/bash

set -e -x
yosys ulx3s-top.ys
nextpnr-ecp5 \
	--json myc64.json \
	--textcfg myc64.config \
	--lpf ulx3s.lpf \
	--25k \
	--package CABGA381

ecppack --idcode 0x21111043 myc64.config myc64.bit
