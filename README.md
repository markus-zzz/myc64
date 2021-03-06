# [WIP] MyC64 - My C64 implementation in Verilog [WIP]

## Getting started

Fetch and prepare the ROM images.
```
cd roms
./fetch-roms.sh
```
### Simulation of MyC64
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

### MyC64-SoC

The SoC makes use of some additional components and the current scripts assume
the following repository structure
```
git clone https://github.com/markus-zzz/usbdev.git && pushd usbdev && git checkout dev && pushd sw && ./build-sw-clang.sh && popd && popd
git clone https://github.com/markus-zzz/retrocon.git && pushd retrocon && git checkout dev && popd
git clone https://github.com/markus-zzz/myc64.git && cd myc64
```

#### Simulation
Build the Verilator based simulator.
```
cd sim
./build-myc64-soc-sim.sh
```
Running produces `.png` at both VIC-II and VGA level in current working directory.

#### Synthesis (for ULX3S)
```
cd syn
./build-ulx3s.sh
```

#### Running (on ULX3S)
Connect the ULX3S secondary USB port to the host computer and then connect with
the keyboard and `.prg` injector program.
```
cd sw
./build-myc64-keyb.sh
./myc64-keyb <.prg file to inject>
```

## Misc

### Machine-language monitor
https://github.com/jblang/supermon64
```
./myc64-sim --cmd-load-prg=130:supermon64.prg --cmd-inject-keys=131:"RUN<RETURN>"
```
