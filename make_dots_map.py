from PIL import Image

# Configuration
IMG_FILE = "PacManMap.bmp"
OUT_FILE = "dots_map.bin"

TILE_W, TILE_H = 8, 8
YELLOW_INDEX = 11  # 0xB: Yellow (dots in PacManMap.bmp)

img = Image.open(IMG_FILE).convert("P")
w, h = img.size
tiles_x = w // TILE_W    # Should be 28
tiles_y = h // TILE_H    # Should be 36

print(f"Image size: {w}x{h}")
print(f"Tile grid: {tiles_x}x{tiles_y}")

dots_count = 0
with open(OUT_FILE, "w") as f:
    for ty in range(tiles_y):
        for tx in range(tiles_x):
            has_dot = 0
            # Check each pixel in the 8x8 tile
            for py in range(ty*TILE_H, (ty+1)*TILE_H):
                for px in range(tx*TILE_W, (tx+1)*TILE_W):
                    pixel = img.getpixel((px, py))
                    if pixel == YELLOW_INDEX:
                        has_dot = 1
                        break
                if has_dot:
                    break
            
            if has_dot:
                dots_count += 1
            
            f.write(str(has_dot) + "\n")

print(f"Total dots found: {dots_count} out of {tiles_x * tiles_y} tiles")
print(f"Output written to {OUT_FILE}")

