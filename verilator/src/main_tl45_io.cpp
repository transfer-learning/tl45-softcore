//
// Created by Will Gulian on 10/27/19.
//

#include <chrono>
#include <fstream>
#include <iostream>
#include <memory>
#include <random>
#include <thread>

#include "testbench.h"
#include "Vtl45_comp.h"
#include "wb_slave.h"
#include "tl45_isa.h"

#include <nlohmann/json.hpp>

using json = nlohmann::json;

json wait_for_input(std::string type) {
  static std::vector<json> previous_messages;

  // check previous messages
  for (auto it = previous_messages.begin(); it != previous_messages.end(); ++it) {
    if (type.empty() || (*it)["type"] == type) {
      json value = *it;
      previous_messages.erase(it);
      return value;
    }
  }

  // not found, go into waiting mode

  while (true) {
    std::string s;
    std::getline(std::cin, s);

    auto j = json::parse(s);

    if (type.empty() || j["type"] == type) {
      return j;
    } else {
      previous_messages.push_back(j);
    }
  }
}


class SerialDevice : public WB_Slave {
public:
  explicit SerialDevice(WB_Bus &bus) : WB_Slave(bus) {}

  bool getData(unsigned int address, bool we, unsigned int &data) override {

    if (we) {
      json j;
      j["type"] = "output";
      j["address"] = std::to_string(address);
      j["data"] = std::to_string(data);
      std::cout << j.dump() << "\n";

//      printf("%08x\n", data);
    } else {
      json j;
      j["type"] = "input_request";
      j["address"] = std::to_string(address);
      std::cout << j.dump() << "\n";

      auto response = wait_for_input("input_response");

      assert(response["address"] == std::to_string(address) && "address mismatch");
      assert(response["data"].is_string() && "expected data field");

      uint64_t response_data = std::stoul(response["data"].get<std::string>());

      data = (unsigned int) response_data;

//      std::cerr << "want input" << "\n";
//      std::cin >> std::hex >> data;
//      std::cerr << "got input: " << std::hex << data << "\n";
//
//      if (std::cin.fail() || std::cin.bad() || std::cin.eof()) {
//        throw std::runtime_error("EOF while expecting input");
//      }

    }

    return true;
  }
};

void log_message(std::string str) {
  json j;
  j["type"] = "log";
  j["message"] = str;
  std::cout << j.dump() << "\n";
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


  std::string s;
  s += "Initialized memory with ";
  s += std::to_string(words.size());
  s += " words";
  log_message(s);

  fclose(f);

  return words;
}

void load_memory(Vtl45_comp *core, const std::vector<uint32_t> &words) {
  auto &ram = core->tl45_comp__DOT__my_mem__DOT__mem;

  for (size_t i = 0; i < words.size(); i++) {
    ram[i] = words[i];
  }
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

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  auto *tb = new TESTBENCH<Vtl45_comp>();

  if (argc == 1) {
    log_message("No file specified");
    return 1;
  }

  std::string filename(argv[1]);

  std::vector<uint32_t> words = read_file(filename);
  if (words.empty()) {
    log_message("Failed to read file or file is empty");
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

  log_message("simulating");

  while (!tb->done()) {
    tb->tick();

    s.eval();
//    printf("%d\n", tb->m_core->tl45_comp__DOT__master_i_wb_data);
  }

  exit(EXIT_SUCCESS);
}