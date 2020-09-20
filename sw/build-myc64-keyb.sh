#!/bin/bash

set -e

g++ -std=c++14 myc64-keyb.cpp -Werror -I. -o myc64-keyb -O0 -g3 `pkg-config --cflags --libs gtk+-3.0` `pkg-config --cflags --libs libusb-1.0`
