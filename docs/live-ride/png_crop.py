import struct, zlib, sys

def chunks(data):
    i = 8
    while i < len(data):
        (length,) = struct.unpack('>I', data[i:i + 4])
        kind = data[i + 4:i + 8]
        payload = data[i + 8:i + 8 + length]
        yield kind, payload
        i += 12 + length

def crop_top(src, dst, keep_height):
    data = open(src, 'rb').read()
    ihdr = None
    idat = b''
    for kind, payload in chunks(data):
        if kind == b'IHDR':
            ihdr = payload
        elif kind == b'IDAT':
            idat += payload
    width, height, depth, colour, comp, filt, interlace = struct.unpack('>IIBBBBB', ihdr)
    assert depth == 8 and interlace == 0, (depth, interlace)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    stride = width * channels
    raw = zlib.decompress(idat)

    out = bytearray()
    previous = bytearray(stride)
    offset = 0
    for row in range(height):
        ftype = raw[offset]
        line = bytearray(raw[offset + 1:offset + 1 + stride])
        offset += 1 + stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = previous[x]
            c = previous[x - channels] if x >= channels else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 0xFF
            elif ftype == 2:
                line[x] = (line[x] + b) & 0xFF
            elif ftype == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 0xFF
        if row < keep_height:
            out += b'\x00' + line
        previous = line

    def chunk(kind, payload):
        return (struct.pack('>I', len(payload)) + kind + payload
                + struct.pack('>I', zlib.crc32(kind + payload) & 0xFFFFFFFF))

    new_ihdr = struct.pack('>IIBBBBB', width, keep_height, depth, colour, comp, filt, interlace)
    open(dst, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', new_ihdr)
        + chunk(b'IDAT', zlib.compress(bytes(out), 9))
        + chunk(b'IEND', b''))

if __name__ == '__main__':
    crop_top(sys.argv[1], sys.argv[2], int(sys.argv[3]))
