//
// Created by Will Gulian on 10/26/19.
//

#include <stdio.h>
#include <iostream>

#include "Vtl45_prefetch.h"
#include "wb_slave.h"

struct TestMem : public WB_Slave {
  unsigned int my_mem[50];

  explicit TestMem(WB_Bus &bus) : WB_Slave(bus) {
    my_mem[0] = 0xdeadbeef;
    my_mem[1] = 0xb0bacafe;
  }

  bool getData(unsigned int address, bool we, unsigned int &data) override {
    if (address >= 50) {
      data = 0;
      return true;
    }

    if (we) {
      my_mem[address] = data;
    } else {
      data = my_mem[address];
    }
    return true;
  }

};

int main() {

  Vtl45_prefetch sim;

  WB_Bus wb_bus(
      sim.o_wb_cyc,
      sim.o_wb_stb,
      sim.o_wb_we,
      sim.o_wb_addr,
      sim.o_wb_data,
      sim.i_wb_ack,
      sim.i_wb_stall,
      sim.i_wb_data
  );

  std::cout << "Hello world\n";

  TestMem mem(wb_bus);

  for (int i = 0; i < 50; i++) {
    sim.i_clk = 1;
    sim.eval();
    sim.i_clk = 0;
    sim.eval();

    mem.eval();

    std::cout << "wb_cyc: " << (int) sim.o_wb_cyc << "\n";
    std::cout << "wb_ack: " << (int) sim.i_wb_ack << "\n";

    std::cout << "PC: " << (int) sim.tl45_prefetch__DOT__current_pc << "\n";
    std::cout << "current_state: " << (int) sim.tl45_prefetch__DOT__current_state << "\n";

    std::cout << "BUF[  PC]: " << std::hex << (int) sim.o_buf_pc << "\n";
    std::cout << "BUF[Inst]: " << std::hex << (int) sim.o_buf_inst << "\n";

  }

}