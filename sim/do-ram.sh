dd bs=1 skip=153 count=65536 if=../roms/foo.dmp of=vice-ram.bin
hexdump -C vice-ram.bin > vice-ram.hex
hexdump ram954.bin -C > ram954.hex
