"""
This file takes a .bin file and output of objcopy and creates a hexfile ready for $readmemh in Verilog.
"""

import struct
import sys
import binascii

def read_binary_file_to_big_endian(input_file, output_file):
    with open(input_file, 'rb') as f:
        binary_data = f.read()

    with open(output_file, 'w') as f:
        for i in range(0, len(binary_data), 4):
            chunk = binary_data[i:i+4]
            if len(chunk) == 4:
                big_endian_value = struct.unpack('<I', chunk)[0]
                value = binascii.hexlify(big_endian_value.to_bytes(4, byteorder='big' if i < 0x2000 or 'fence_i' in input_file else 'little')).decode()
                out = f"{value[0:2]} {value[2:4]} {value[4:6]} {value[6:8]} "
                f.write(out)

if __name__ == "__main__":
    read_binary_file_to_big_endian(sys.argv[1], sys.argv[2])

