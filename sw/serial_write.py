from __future__ import print_function

import time

import serial
import glob
import sys


IO_SEVEN_SEG = 0x1000000

# hexes = []
# with open(sys.argv[1]) as f:
#     for line in f:
#         if line.startswith(':'):
#             hexes.append(line.strip())


if sys.platform == 'darwin':
    # mac_irl
    serial_ifs = glob.glob('/dev/cu.usbserial*')
else:
    serial_ifs = glob.glob('/dev/ttyUSB0')

if not serial_ifs:
    print('No serial interfaces found!')
    exit(1)

print('Using serial:', serial_ifs[0])


def write_ack(ser, address, data, verify=False):
    payload = 'A' + hex(address)[2:] + 'W' + hex(data)[2:] + '\n'

    ser.write(payload.encode('ascii'))
    print(payload)
    time.sleep(0.1)

    while True:
        response = ser.readline().decode('ascii')
        print(response)
        if 'K' in response:
            break
        if response == '':
            raise ValueError('didnt ACK')

    # time.sleep(0.1)

    if verify:
        read_val = read_ack(ser, address)
        # print(read_val, data)
        assert read_val == data


def parsehex(num):
    return int('0x' + num, 16)


def read_ack(ser, address):
    payload = 'A' + hex(address)[2:] + 'R' + '\n'

    ser.write(payload.encode('ascii'))
    print(payload)
    time.sleep(0.1)

    while True:
        response = ser.readline().decode('ascii')
        print(response)
        if 'R' in response:
            break
        if response == '':
            raise ValueError('didnt get ACK')

    ack_address, _, mem = response.strip().partition('R')
    assert len(ack_address) == 9  # R + addr
    assert len(mem) == 8

    assert address == parsehex(ack_address[1:])

    # time.sleep(0.1)

    return parsehex(mem)


with serial.Serial(serial_ifs[0], 115200, timeout=0.1) as ser:
    print('Serial Name:', ser.name)

    while ser.read(size=10000):
        pass

    prog = open('a.out', 'rb').read()

    addr = 0
    for i in range(0, len(prog), 4):
        num = prog[i] << 24 | prog[i+1] << 16 | prog[i+2] << 8 | prog[i+3]
        print(hex(num))
        write_ack(ser, addr*4, num, verify=True)
        addr += 1

    # for i in range(1000):
    #     write_ack(ser, 0x1000000, i)
    #     time.sleep(0.5)







