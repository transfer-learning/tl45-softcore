#!/bin/sh

verilator --cc -Mdir obj_dir -public ../rtl/tl45_core/tl45_prefetch.sv

(cd obj_dir ; make -f Vtl45_prefetch.mk)


