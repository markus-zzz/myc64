#!/bin/bash

# exit when any command fails
set -e

# basic.901226-01.bin  characters.901225-01.bin  kernal.901227-03.bin
wget http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c64/kernal.901227-03.bin
wget http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c64/characters.901225-01.bin
wget http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c64/basic.901226-01.bin

hexdump -v -e '4/1 "%02x " "\n"' kernal.901227-03.bin > kernal.vh
hexdump -v -e '4/1 "%02x " "\n"' basic.901226-01.bin > basic.vh
hexdump -v -e '4/1 "%02x " "\n"' characters.901225-01.bin > characters.vh
