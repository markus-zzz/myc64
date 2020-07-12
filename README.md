# [WIP] MyC64 - My C64 implementation in Verilog [WIP]

## Getting started
Fetch and prepare the ROM images.
```
cd roms
./fetch-roms.sh
```
Build the Verilator based simulator.
```
cd sim
./build-myc64-sim.sh
```
Test by injecting a BASIC program.
```
./myc64-sim --cmd-inject-keys=135:"10<SPACE>PRINT<SPACE>CHR<LSHIFT>4<LSHIFT>8205.5+RND<LSHIFT>81<LSHIFT>9<LSHIFT>9;:GOTO<SPACE>10<RETURN>RUN<RETURN>"
```
Test by loading a `.prg` into RAM, inject keys to `RUN` it and then dump screen RAM
afterwards.
```
cl65 -o test_001.prg -t c64 -C c64-asm.cfg -u __EXEHDR__ testasm/test_001.s
./myc64-sim --cmd-load-prg=130:test_001.prg --cmd-inject-keys=135:"LIST<RETURN>RUN<RETURN>" --cmd-dump-ram=170:0x400:0x100

```
