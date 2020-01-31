verilator -I../../rtl/ihex -I../../rtl/wb_iodevice -I../../rtl/wbuart_with_ihex --cc --trace \
-GI_CLOCK_FREQ=100000000 -GBAUD_RATE=10000000 \
../../rtl/wbuart_with_ihex/wbuart_with_ihex.sv

cd obj_dir && make -f Vwbuart_with_ihex.mk
