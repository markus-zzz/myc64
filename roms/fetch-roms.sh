#!/bin/bash

# exit when any command fails
set -e

# basic.901226-01.bin  characters.901225-01.bin  kernal.901227-03.bin
wget http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c64/kernal.901227-03.bin
wget http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c64/characters.901225-01.bin
wget http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c64/basic.901226-01.bin

cp kernal.901227-03.bin kernal.bin
cp basic.901226-01.bin basic.bin
cp characters.901225-01.bin characters.bin

xxd -i kernal.bin > kernal.h
xxd -i basic.bin > basic.h
xxd -i characters.bin > characters.h
