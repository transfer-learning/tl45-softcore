//
// Created by Will Gulian on 10/27/19.
//

#include "testbench.h"
#include "Vtl45_comp.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  TESTBENCH<Vtl45_comp> *tb = new TESTBENCH<Vtl45_comp>();

  tb->opentrace("trace.vcd");

  while(!tb->done() && tb->m_tickcount < 100) {
    tb->tick();
  }

  exit(EXIT_SUCCESS);
}