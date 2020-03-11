#!/bin/sh
set -e

verilator --cc -Wno-fatal --trace -Mdir obj_dir -public -I../rtl/tl45_core -I../rtl -I../rtl/bus -I../testbenches \
-I../rtl/wb_iodevice -I../rtl/ihex -I../rtl/wbuart_with_ihex -I../rtl/sdspi -I../rtl/lpm_mult -I../rtl/gen ../rtl/tl45_core/tl45_comp.sv

cd obj_dir

make -f Vtl45_prefetch.mk
make -f Vtl45_comp.mk


