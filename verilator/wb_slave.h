//
// Created by Will Gulian on 10/26/19.
//

#ifndef SIM_TL45_WB_SLAVE_H
#define SIM_TL45_WB_SLAVE_H

#include <exception>
#include <verilated.h>

struct WB_Bus {

  // slave inputs / master outputs
  CData &o_wb_cyc;
  CData &o_wb_stb;
  CData &o_wb_we;
  IData &o_wb_addr;
  IData &o_wb_data;

  // slave outputs / master inputs
  CData &i_wb_ack;
  CData &i_wb_stall;
  IData &i_wb_data;

  WB_Bus(CData &oWbCyc, CData &oWbStb, CData &oWbWe, IData &oWbAddr, IData &oWbData, CData &iWbAck, CData &iWbStall,
         IData &iWbData) : o_wb_cyc(oWbCyc), o_wb_stb(oWbStb), o_wb_we(oWbWe), o_wb_addr(oWbAddr), o_wb_data(oWbData),
                           i_wb_ack(iWbAck), i_wb_stall(iWbStall), i_wb_data(iWbData) {}
};

struct WB_Slave {
  WB_Bus &bus;

  bool tx_in_progress;
  bool we;
  unsigned int address;
  unsigned int data;
  bool ack;

  explicit WB_Slave(WB_Bus &bus) : bus(bus) {}

  // if true, did read
  virtual bool getData(unsigned int address, bool we, unsigned int &data) = 0;

  virtual bool isStalled() {
    return false;
  }

  void eval() {
    bus.i_wb_stall = isStalled();
    if (!bus.i_wb_stall) {

      if (bus.o_wb_cyc && bus.o_wb_stb && !tx_in_progress) {
        tx_in_progress = true;
        we = bus.o_wb_we;
        address = bus.o_wb_addr;
        if (we) {
          data = bus.o_wb_data;
        }
      }

      if (tx_in_progress) {
        if (!bus.o_wb_cyc && !ack) {
          throw std::runtime_error("lmao cyc went low");
        }

        if (ack) {
          bus.i_wb_ack = 0;
          ack = false;
          tx_in_progress = false;
        } else if (!bus.o_wb_stb)  {

          unsigned int data;
          if (we) {
            data = this->data;
          }
          bool success = getData(address, we, data);

          if (success) {
            if (!we) {
              bus.i_wb_data = data;
            }
            bus.i_wb_ack = true;
            ack = true;
          }

        }

      }
    }
  }

};



#endif //SIM_TL45_WB_SLAVE_H
