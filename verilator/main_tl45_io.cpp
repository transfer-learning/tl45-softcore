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

class SerialDevice : public WB_Slave {
public:
  explicit SerialDevice(WB_Bus &bus) : WB_Slave(bus) {}

  bool getData(unsigned int address, bool we, unsigned int &data) override {

    if (we) {
      std::cout << std::hex << data << "\n";
    } else {
      std::cerr << "want input" << "\n";
      std::cin >> std::hex >> data;
      std::cerr << "got input: " << std::hex << data << "\n";

      if (std::cin.fail() || std::cin.bad() || std::cin.eof()) {
        throw std::runtime_error("EOF while expecting input");
      }

    }

    return true;
  }
};

std::string disassemble(uint32_t instruction) {
  uint8_t opcode = instruction >> (32U - 5U) & 0x1FU;
  uint8_t RHZ = instruction >> (32U - 5U - 3U) & 0x7U;
  uint16_t IMM16 = instruction & 0xFFFF;
  uint16_t SR2 = (instruction >> 12) & 0xFU;
  uint16_t SR1 = (instruction >> 16) & 0xFU;
  uint16_t DR = (instruction >> 20) & 0xFU;
  std::string opcode_part;
  switch (opcode) {
  case 0x0:
    opcode_part = "NOP ";
    break;
  case 0x1:
    opcode_part = "ADD";
    break;
  case 0x2:
    opcode_part = "SUB ";
    break;
  case 0x3:
    opcode_part = "MUL ";
    break;
  case 0x4:
    opcode_part = "DIV(NI) ";
    break;
  case 0x5:
    opcode_part = "SHRA";
    break;
  case 0x6:
    opcode_part = "OR ";
    break;
  case 0x7:
    opcode_part = "XOR ";
    break;
  case 0x8:
    opcode_part = "AND ";
    break;
  case 0x9:
    opcode_part = "NOT ";
    break;
  case 0xa:
    opcode_part = "SHL ";
    break;
  case 0xb:
    opcode_part = "SHR ";
    break;
  case 0xc:
    opcode_part = "J";
    break;
  case 0xd:
    opcode_part = "CALL ";
    break;
  case 0xe:
    opcode_part = "RET ";
    break;
  case 0xf:
    opcode_part = "LBSE ";
    break;
  case 0x10:
    opcode_part = "LHW ";
    break;
  case 0x11:
    opcode_part = "LHWSE ";
    break;
  case 0x12:
    opcode_part = "LB ";
    break;
  case 0x13:
    opcode_part = "SB ";
    break;
  case 0x14:
    opcode_part = "LW ";
    break;
  case 0x15:
    opcode_part = "SW ";
    break;
  default:
    opcode_part = "INVALID";
    break;
  }
  if (opcode == 0xc) {
    switch (DR) {
    case 0x0:
      opcode_part += "O ";
      break;
    case 0x1:
      opcode_part += "NO ";
      break;
    case 0x2:
      opcode_part += "S ";
      break;
    case 0x3:
      opcode_part += "NS ";
      break;
    case 0x4:
      opcode_part += "E ";
      break;
    case 0x5:
      opcode_part += "NE ";
      break;
    case 0x6:
      opcode_part += "B ";
      break;
    case 0x7:
      opcode_part += "NB ";
      break;
    case 0x8:
      opcode_part += "BE ";
      break;
    case 0x9:
      opcode_part += "A ";
      break;
    case 0xa:
      opcode_part += "L ";
      break;
    case 0xb:
      opcode_part += "GE ";
      break;
    case 0xc:
      opcode_part += "LE ";
      break;
    case 0xe:
      opcode_part += "G ";
      break;
    case 0xf:
      opcode_part += "UMP ";
      break;
    }
  }
  std::string operand_part;
  return opcode_part;
}

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
}


int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  TESTBENCH<Vtl45_comp> *tb = new TESTBENCH<Vtl45_comp>();

  std::cout.setf(std::ios::unitbuf);
  std::cerr.setf(std::ios::unitbuf);
  std::cin.setf(std::ios::unitbuf);

  if (argc == 1) {
    printf("No file specified\n");
    return 1;
  }

  std::string filename(argv[1]);

  std::vector<uint32_t> words = read_file(filename);
  if (words.empty()) {
    printf("Failed to read file or file is empty\n");
    return 1;
  }

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

  SerialDevice s(bus);

  std::cerr << "simulating\n";

  while (!tb->done()) {
    tb->tick();

    s.eval();
//    printf("%d\n", tb->m_core->tl45_comp__DOT__master_i_wb_data);
  }

  exit(EXIT_SUCCESS);
}
