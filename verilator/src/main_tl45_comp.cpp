//
// Created by Will Gulian on 10/27/19.
//

#include <chrono>
#include <fstream>
#include <iostream>
#include <memory>
#include <random>
#include "testbench.h"
#include "Vtl45_comp.h"
#include "wb_slave.h"
#include "tl45_isa.h"

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

class TestDevice : public WB_Slave {
  const std::vector<uint32_t> &inputs;
  const std::vector<uint32_t> &expected_outputs;
  std::vector<uint32_t> &outputs;

  size_t read_index;
  size_t write_index;

public:
  size_t max_writes;

  explicit TestDevice(WB_Bus &bus, const std::vector<uint32_t> &inputs, std::vector<uint32_t> &outputs, const std::vector<uint32_t> &expected_outputs)
      : WB_Slave(bus), inputs(inputs), outputs(outputs), expected_outputs(expected_outputs), read_index(0), write_index(0), max_writes(100000) {}

  bool getData(unsigned int address, bool we, unsigned int &data) override {

    if (we) {

      if (outputs.size() >= max_writes) {
        throw std::runtime_error("cannot accept more writes");
      }

      int i = outputs.size();
      outputs.push_back(data);

      if (i < expected_outputs.size()) {
        uint32_t e = expected_outputs[i];

        if (data != e) {
          throw std::runtime_error("mismatched output");
        }
      }

    } else {

      if (read_index >= inputs.size()) {
        throw std::runtime_error("cannot read more");
      }

      data = inputs[read_index++];
    }

    return true;
  }
};


std::vector<uint32_t> read_file(const std::string &file) {
  std::vector<uint32_t> words;

  FILE *f = fopen(file.c_str(), "r");
  if (!f) {
    return words;
  }

  unsigned char temp[4];
  int read = 0;
  while (true) {

    int r = fread(temp, 1, 4 - read, f);
    if (r == 0) {
      break;
    }

    read += r;

    if (read == 4) {
      words.push_back(temp[0u] << 24u | temp[1u] << 16u | temp[2u] << 8u | temp[3u]);
      read = 0;
    }
  }

  printf("Initialized memory with %zu words\n", words.size());
  fclose(f);

  return words;
}

void load_memory(Vtl45_comp *core, const std::vector<uint32_t> &words) {
  auto &ram = core->tl45_comp__DOT__my_mem__DOT__mem;

  for (size_t i = 0; i < words.size(); i++) {
    ram[i] = words[i];
  }

  printf("Word at 0xFFFC is 0x%08X", ram[0xFFFCU >> 2U]);
}

std::vector<uint32_t> read_expected(const std::string &file) {
  std::vector<uint32_t> words;

  std::ifstream infile(file);

  unsigned char temp[4];
  int read = 0;

  for (std::string line; std::getline(infile, line); ) {

    int i = line.find(" = ", 0);
    i += 3;

    std::string s;
    s += "0x";
    s += line.substr(i, 8);

    auto result = (uint32_t ) std::stoul(s, nullptr, 16);

    words.push_back(result);
  }

  return words;
}

void test_case(const std::vector<uint32_t> &words, const std::vector<uint32_t> &inputs,
               std::vector<uint32_t> &outputs, const std::vector<uint32_t> &expected_outputs, int tick_count = 10000000) {
  auto tb = std::make_unique<TESTBENCH<Vtl45_comp>>();

  auto t1 = std::chrono::high_resolution_clock::now();


  load_memory(tb->m_core, words);

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

  TestDevice s(bus, inputs, outputs, expected_outputs);

  // stabilize
  tb->tick();

  while (!tb->done() && tb->m_tickcount < tick_count) {
    tb->tick();
    try {
      s.eval();
    } catch (std::runtime_error &e) {
      std::cout << "Error: " << e.what() << "\n";
      break;
    }
  }

  auto t2 = std::chrono::high_resolution_clock::now();
  auto duration = std::chrono::duration_cast<std::chrono::milliseconds>( t2 - t1 ).count();

  float frequency = 1000.0f * ((float) tb->m_tickcount) / (float) duration;

  std::cout << "test case ran at: " << ((int)frequency) << "Hz with " << tb->m_tickcount << " total cycles\n";


}


std::string to_string(const std::vector<uint32_t> &vec) {
  std::string s;
  s += "[";
  for (size_t i = 0; i < vec.size(); i++) {
    if (i > 0) {
      s += ", ";
    }
    s += std::to_string(vec[i]);
  }
  s += "]";
  return s;
}





int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  auto *tb = new TESTBENCH<Vtl45_comp>();

   auto &ram = tb->m_core->tl45_comp__DOT__my_mem__DOT__mem;
#define LOAD
#ifdef LOAD

  if (argc == 1) {
    printf("No file specified\n");
  }

  std::vector<uint32_t> words = read_file(argv[1]);
  if (words.empty()) {
    printf("Failed to read file or file is empty\n");
    return 1;
  }

  load_memory(tb->m_core, words);

//  std::vector<uint32_t> inputs{};
//
//  std::vector<uint32_t> expected_outputs = read_expected("../output.txt");
//  std::cout << to_string(expected_outputs) << "\n";
//
//  std::vector<uint32_t> outputs;
//  test_case(words, inputs, outputs, expected_outputs);
//
//  std::cout << "expected outputs size: " << expected_outputs.size() << "\n";
//  std::cout << "outputs size: " << outputs.size() << "\n";
//
//  int diffs = 0;
//  for (int i = 0; i < std::min(outputs.size(), expected_outputs.size()); i++) {
//    if (outputs[i] != expected_outputs[i]) {
//      std::cout << "Diff: " << i << "\n";
//      diffs++;
//    }
//  }
//
//  std::cout << "Diffs: " << std::to_string(diffs) << "\n";
//
//  std::cout << to_string(inputs) << "\n";
  // std::cout << to_string(outputs) << "\n";



#else
  ram[0] = 0x0d20FFFF;
  ram[1] = 0x0d100003;
  ram[2] = 0xb8312000;
  ram[3] = 0x08403000;
#endif

#if 1

#define DO_TRACE 1

  tb->tick();

  tb->m_core->tl45_comp__DOT__dprf__DOT__registers[4] = 0;
  tb->m_core->tl45_comp__DOT__dprf__DOT__registers[7] = 0x80000000;

#if DO_TRACE
  tb->opentrace("trace.vcd");
#endif

  CData unused;

//  WB_Bus bus(
//      tb->m_core->tl45_comp__DOT__master_o_wb_cyc,
//      tb->m_core->tl45_comp__DOT__v_hook_stb,
//      tb->m_core->tl45_comp__DOT__master_o_wb_we,
//      tb->m_core->tl45_comp__DOT__master_o_wb_addr,
//      tb->m_core->tl45_comp__DOT__master_o_wb_data,
//      tb->m_core->tl45_comp__DOT__v_hook_ack,
//      unused,
//      tb->m_core->tl45_comp__DOT__v_hook_data
//  );
//
//  SerialDevice s(bus);
//
  while (!tb->done() && (!(DO_TRACE) || tb->m_tickcount < 100 * 20)) {
    tb->tick();

//    s.eval();

#if DO_TRACE
    if (tb->m_tickcount % 10 == 0 && 0) {
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

#endif

  exit(EXIT_SUCCESS);
}