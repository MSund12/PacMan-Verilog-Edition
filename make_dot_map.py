from PIL import Image

IMG_FILE = "PacManMap.bmp"  # Use the map with dots
OUT_FILE = "dot_map.bin"

TILE_W, TILE_H = 8, 8
DOT_INDEX = 15          # 0xF: white dots in the maze
WALL_INDEX = 12         # 0xC: blue walls (no dots)

img = Image.open(IMG_FILE).convert("P")
w, h = img.size
tiles_x = w // TILE_W    # 28
tiles_y = h // TILE_H    # 36

with open(OUT_FILE, "w") as f:
    for ty in range(tiles_y):
        for tx in range(tiles_x):
            has_dot = 0
            is_wall = 0
            
            # Check all pixels in this tile
            for py in range(ty*TILE_H, (ty+1)*TILE_H):
                for px in range(tx*TILE_W, (tx+1)*TILE_W):
                    pixel = img.getpixel((px, py))
                    if pixel == WALL_INDEX:
                        is_wall = 1
                        break
                    elif pixel == DOT_INDEX:
                        has_dot = 1
                if is_wall:
                    break
            
            # Only set dot if tile is not a wall
            if not is_wall and has_dot:
                f.write("1\n")
            else:
                f.write("0\n")

print(f"Generated {OUT_FILE} with dot map for {tiles_x}x{tiles_y} tiles")

