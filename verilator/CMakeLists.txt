cmake_minimum_required(VERSION 3.1)
project(sim_tl45)

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake ${CMAKE_MODULE_PATH})
set(CMAKE_CXX_FLAGS -fsanitize=address)

find_package(Verilator REQUIRED)

message(${CMAKE_SYSTEM_NAME})
if(${CMAKE_SYSTEM_NAME} STREQUAL Linux)
    set(VERILATOR_INCLUDE_DIR /usr/share/verilator/include)
else(${CMAKE_SYSTEM_NAME} STREQUAL Linux)
    set(VERILATOR_INCLUDE_DIR  /usr/local/Cellar/verilator/4.020/share/verilator/include)
endif(${CMAKE_SYSTEM_NAME} STREQUAL Linux)
include_directories(${VERILATOR_INCLUDE_DIR})
include_directories(obj_dir)


add_executable(sim_tl45_prefetch ${VERILATOR_INCLUDE_DIR}/verilated.cpp main_prefetch.cpp)

target_link_libraries(sim_tl45_prefetch ${CMAKE_CURRENT_SOURCE_DIR}/obj_dir/Vtl45_prefetch__ALL.a)

add_executable(sim_tl45_comp
        ${VERILATOR_INCLUDE_DIR}/verilated.cpp
        ${VERILATOR_INCLUDE_DIR}/verilated_vcd_c.cpp
        main_tl45_comp.cpp)

target_link_libraries(sim_tl45_comp ${CMAKE_CURRENT_SOURCE_DIR}/obj_dir/Vtl45_comp__ALL.a)





