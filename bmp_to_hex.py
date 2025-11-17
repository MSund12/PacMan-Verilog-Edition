import struct
import glob
import os

def bmp_to_hex_no_deps(bmp_path, hex_path=None):
    with open(bmp_path, 'rb') as f:
        data = f.read()

    # --- BMP FILE HEADER (14 bytes) ---
    bfType, bfSize, bfReserved1, bfReserved2, bfOffBits = struct.unpack_from('<2sIHHI', data, 0)
    if bfType != b'BM':
        raise ValueError(f"{bmp_path}: not a BMP file (bfType={bfType})")

    # --- BITMAPINFOHEADER (40 bytes) ---
    (
        biSize,
        biWidth,
        biHeight,
        biPlanes,
        biBitCount,
        biCompression,
        biSizeImage,
        biXPelsPerMeter,
        biYPelsPerMeter,
        biClrUsed,
        biClrImportant,
    ) = struct.unpack_from('<IIIHHIIIIII', data, 14)

    # Your files are paletted, 4 or 8 bpp, uncompressed
    if biBitCount not in (4, 8):
        raise ValueError(f"{bmp_path}: expected 4bpp or 8bpp paletted, got {biBitCount} bpp")
    if biCompression != 0:
        raise ValueError(f"{bmp_path}: expected BI_RGB (0) compression, got {biCompression}")

    width = biWidth
    height = abs(biHeight)
    top_down = biHeight < 0

    # Row size in bytes, padded to 4-byte boundary
    # (standard BMP formula)
    row_size = ((biBitCount * width + 31) // 32) * 4

    pixels = []

    # Read rows in logical top->bottom order
    for row in range(height):
        # BMP stores bottom row first if biHeight > 0
        file_row = row if top_down else (height - 1 - row)
        offset = bfOffBits + file_row * row_size
        row_bytes = data[offset: offset + row_size]

        if biBitCount == 8:
            # 1 byte = 1 pixel index
            row_pixels = list(row_bytes[:width])
        else:
            # 4bpp: 2 pixels per byte (high nibble, then low nibble)
            row_pixels = []
            for b in row_bytes[: (width + 1) // 2]:
                hi = (b >> 4) & 0xF
                lo = b & 0xF
                row_pixels.append(hi)
                if len(row_pixels) < width:
                    row_pixels.append(lo)

        pixels.extend(row_pixels[:width])

    if hex_path is None:
        hex_path = os.path.splitext(bmp_path)[0] + ".hex"

    with open(hex_path, 'w') as out:
        for v in pixels:
            if v >= 16:
                raise ValueError(f"{bmp_path}: pixel value {v} does not fit in 4 bits (0–15)")
            out.write(f"{v:X}\n")

    print(f"Converted {os.path.basename(bmp_path)} "
          f"({width}x{height}, {biBitCount}bpp) -> {os.path.basename(hex_path)} "
          f"({len(pixels)} pixels)")
    return hex_path


def main():
    bmp_files = glob.glob("*.bmp")
    if not bmp_files:
        print("No .bmp files found in current directory.")
        return

    for bmp in bmp_files:
        bmp_to_hex_no_deps(bmp)


if __name__ == "__main__":
    main()
