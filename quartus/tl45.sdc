create_clock -name i_clk -period 20.000 [get_ports {i_clk}]

set_false_path -from [get_ports {i_switches[0] i_switches[1] i_switches[2] i_switches[3] i_switches[4] i_switches[5] i_switches[6] i_switches[7] i_switches[8] i_switches[9] i_switches[10] i_switches[11] i_switches[12] i_switches[13] i_switches[14] i_switches[15] i_reset}]

set_false_path -from [get_ports {i_reset i_halt_proc}]

set_input_delay -clock { i_clk } -max 6 [get_ports *]