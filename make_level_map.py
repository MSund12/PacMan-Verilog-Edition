from PIL import Image

IMG_FILE = "WithoutDots.bmp"
OUT_FILE = "level_map.bin"

TILE_W, TILE_H = 8, 8
WALL_INDEX = 12          # 0xC: blue walls in your maze

img = Image.open(IMG_FILE).convert("P")
w, h = img.size
tiles_x = w // TILE_W    # 28
tiles_y = h // TILE_H    # 36

with open(OUT_FILE, "w") as f:
    for ty in range(tiles_y):
        for tx in range(tiles_x):
            wall = 0
            for py in range(ty*TILE_H, (ty+1)*TILE_H):
                for px in range(tx*TILE_W, (tx+1)*TILE_W):
                    if img.getpixel((px, py)) == WALL_INDEX:
                        wall = 1
                        break
                if wall:
                    break
            f.write(str(wall) + "\n")
