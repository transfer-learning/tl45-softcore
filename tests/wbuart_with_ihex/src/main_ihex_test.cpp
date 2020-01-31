#include <iostream>
#include "testbench.h"
#include "Vwbuart_with_ihex.h"

struct uart {
  uint8_t *send;
  uint8_t send_state;
  uint8_t *line;
  uint8_t need_send;
  uint8_t sending;

  void tick_send() {
    if (need_send) {
      if (send_state == 0) {
        *line = 0;
        send_state++;
      } else {
        if (send_state == 9) {
          *line = 1;
        } else {
          *line = (send[sending] >> (send_state - 1)) & 0x1U;
        }
        if (send_state == 9) {
          send_state = 0;
          need_send--;
          sending++;
        } else {
          send_state++;
        }
      }
    } else {
      *line = 1;
    }
  }
};


int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  auto *tb = new TESTBENCH<Vwbuart_with_ihex>();
  tb->opentrace("ihex_uart_trace.vcd");

  uart u{};
  u.line = &tb->m_core->i_rx;
  std::string a = ":00000001FF";
  u.send = (uint8_t *) a.c_str();
  u.sending = 0;
  u.need_send = a.length();

  tb->m_core->i_rx = 1;
  tb->reset();
  for (int i = 0; i < 5000; ++i) {
    tb->tick();
    if (i % 10 == 8) {
      u.tick_send();
    }
  }
  tb->close();
  return 0;
}
