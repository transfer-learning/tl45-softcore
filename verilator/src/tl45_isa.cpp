//
// Created by Will Gulian on 11/16/19.
//

#include "wb_slave.h"
#include "Vtl45_comp.h"
#include "testbench.h"
#include <random>
#include <memory>
#include <iostream>
#include <fstream>
#include <chrono>
#include "tl45_isa.h"

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

