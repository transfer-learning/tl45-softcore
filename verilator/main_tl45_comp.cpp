//
// Created by Will Gulian on 10/27/19.
//

#include <iostream>
#include "testbench.h"
#include "Vtl45_comp.h"
#include "wb_slave.h"

class SerialDevice : public WB_Slave {
public:
  explicit SerialDevice(WB_Bus &bus) : WB_Slave(bus) {}

  bool getData(unsigned int address, bool we, unsigned int &data) override {

    if (we) {
      char c = ' ';
      if (isprint((int) data)) {
        c = (char) data;
      }

      printf(" Got %x: %x %c\n", address, data, c);
    } else {
      data = 0xdeadbeef;
      printf("Sent %x: %x\n", address, data);
    }



    return true;
  }
};

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  TESTBENCH<Vtl45_comp> *tb = new TESTBENCH<Vtl45_comp>();

  auto &ram = tb->m_core->tl45_comp__DOT__my_mem__DOT__mem;
//#define LOAD
#ifdef LOAD
  FILE *f;
  if (argc > 1)
    f = fopen(argv[1], "r");
  else
    f = fopen("/Users/will/Work/transfer-learning/llvm-tl45/llvm/bbb/a.out", "r");
  if (!f) {
    printf("Fail!\n");
    return 1;
  }

  size_t mem_ptr = 0;

  unsigned char temp[4];
  int read = 0;
  while (true) {

    int r = fread(temp, 1, 4 - read, f);
    if (r == 0) {
      break;
    }

    read += r;

    if (read == 4) {
      ram[mem_ptr] = temp[0u] << 24u | temp[1u] << 16u | temp[2u] << 8u | temp[3u];
      read = 0;
      mem_ptr++;
    }
  }

  printf("Initialized memory with %zu words\n", mem_ptr);
  fclose(f);
#else
  ram[0] = 0x0d100003;
  ram[1] = 0x0d200002;
  ram[2] = 0x18312000;
  ram[3] = 0x0d100009;
#endif
#define DO_TRACE 1

#if DO_TRACE
  tb->opentrace("trace.vcd");
#endif

  CData unused;

  WB_Bus bus(
      tb->m_core->tl45_comp__DOT__master_o_wb_cyc,
      tb->m_core->tl45_comp__DOT__v_hook_stb,
      tb->m_core->tl45_comp__DOT__master_o_wb_we,
      tb->m_core->tl45_comp__DOT__master_o_wb_addr,
      tb->m_core->tl45_comp__DOT__master_o_wb_data,
      tb->m_core->tl45_comp__DOT__v_hook_ack,
      unused,
      tb->m_core->tl45_comp__DOT__v_hook_data
  );

  SerialDevice s(bus);

  while (!tb->done()  && (!(DO_TRACE) || tb->m_tickcount < 100 * 20)) {
    tb->tick();

    s.eval();

#if DO_TRACE
    if (tb->m_tickcount % 10 == 0) {
      std::cout << "SP: " << std::hex << tb->m_core->tl45_comp__DOT__dprf__DOT__registers[14] << "\n";
      std::cout << "PC: " << std::hex << tb->m_core->tl45_comp__DOT__decode__DOT__i_buf_pc << "\n";

      if (tb->m_core->tl45_comp__DOT__decode__DOT__decode_err) {
        exit(5);
      }
    }
#else
  if (tb->m_tickcount % 100000 == 0) {
    printf("PC: 0x%08x\r", tb->m_core->tl45_comp__DOT__fetch__DOT__current_pc);
    fflush(stdout);
  }
#endif

//    printf("%d\n", tb->m_core->tl45_comp__DOT__master_i_wb_data);
  }

  exit(EXIT_SUCCESS);
}