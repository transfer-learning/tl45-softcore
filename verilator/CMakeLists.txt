cmake_minimum_required(VERSION 3.1)
project(sim_tl45)

set(CMAKE_CXX_FLAGS -fsanitize=address)

include_directories(/usr/local/Cellar/verilator/4.020/share/verilator/include)
include_directories(obj_dir)


add_executable(sim_tl45_prefetch /usr/local/Cellar/verilator/4.020/share/verilator/include/verilated.cpp main_prefetch.cpp)

target_link_libraries(sim_tl45_prefetch ${CMAKE_CURRENT_SOURCE_DIR}/obj_dir/Vtl45_prefetch__ALL.a)

add_executable(sim_tl45_comp
        /usr/local/Cellar/verilator/4.020/share/verilator/include/verilated.cpp
        /usr/local/Cellar/verilator/4.020/share/verilator/include/verilated_vcd_c.cpp
        main_tl45_comp.cpp)

target_link_libraries(sim_tl45_comp ${CMAKE_CURRENT_SOURCE_DIR}/obj_dir/Vtl45_comp__ALL.a)





