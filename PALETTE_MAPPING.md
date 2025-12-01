# Unified Palette Mapping

## Overview
The codebase now uses a unified 4-bit color palette where each index (0-15) maps to a specific color. This eliminates context-dependent color mapping and makes it easier to add new sprites.

## Palette Definition

| Index | Hex | Color | RGB | Usage |
|-------|-----|-------|-----|-------|
| 0x0 | 0 | Black | (0,0,0) | Transparent/Background |
| 0x1 | 1 | Dark Red | (128,0,0) | Available |
| 0x2 | 2 | Dark Green | (0,128,0) | Available |
| 0x3 | 3 | Orange | (255,160,0) | Clyde (Orange Ghost) |
| 0x4 | 4 | Dark Blue | (0,0,128) | Available |
| 0x5 | 5 | Dark Magenta/Purple | (128,0,128) | Available |
| 0x6 | 6 | Brown | (144,64,16) | Pellets/Dots |
| 0x7 | 7 | Red | (255,0,0) | Blinky (Red Ghost) |
| 0x8 | 8 | Gray | (128,128,128) | Available |
| 0x9 | 9 | Pink | (255,128,255) | Pinky (Pink Ghost) |
| 0xA | A | Green | (0,255,0) | Available |
| 0xB | B | Yellow | (255,255,0) | Pac-Man |
| 0xC | C | Blue | (0,0,255) | Maze Walls |
| 0xD | D | Magenta | (255,0,255) | Available |
| 0xE | E | Cyan | (0,255,255) | Inky (Cyan Ghost) |
| 0xF | F | White | (255,255,255) | Dots/Pellets |

## Current BMP File Status

**Note:** The existing BMP files need to be remapped to use the unified palette indices:

- **Pacman.bmp**: Currently uses index 7 for yellow → Should use index 0xB
- **Blinky.bmp**: Currently uses index 7 for red → Already correct (index 7)
- **Pinky.bmp**: Currently uses index 7 for pink → Should use index 0x9
- **Inky.bmp**: Currently uses index 0xE for cyan → Already correct (index 0xE)
- **Clyde.bmp**: Currently uses index 7 for orange → Should use index 0x3
- **PacManMap.bmp**: Uses indices 0x0, 0x7, 0xC, 0xF → Pellets (index 0xF) should be remapped to index 0x6 for brown color

## Remapping BMP Files

To remap BMP files to use the unified palette:

1. Open the BMP file in an image editor (e.g., GIMP, Photoshop)
2. Convert to indexed color mode (4-bit, 16 colors)
3. Edit the color palette:
   - Set index 0xB to Yellow (RGB 255,255,0) for Pac-Man
   - Set index 0x7 to Red (RGB 255,0,0) for Blinky
   - Set index 0x9 to Pink (RGB 255,128,255) for Pinky
   - Set index 0x3 to Orange (RGB 255,160,0) for Clyde
   - Set index 0xE to Cyan (RGB 0,255,255) for Inky
   - Set index 0xC to Blue (RGB 0,0,255) for walls
   - Set index 0x6 to Brown (RGB 144,64,16) for pellets/dots
   - Set index 0xF to White (RGB 255,255,255) for white elements
4. Remap the pixels:
   - For Pac-Man: Change all yellow pixels (index 7) to index 0xB
   - For Pinky: Change all pink pixels (index 7) to index 0x9
   - For Clyde: Change all orange pixels (index 7) to index 0x3
   - For PacManMap: Change all pellet pixels (index 0xF) to index 0x6 for brown pellets
5. Save and regenerate the .hex files using `bmp_to_hex.py`

## Benefits

- **Consistent colors**: Same index always means the same color
- **Easier maintenance**: Single palette lookup function
- **Sprite overlap**: Multiple sprites can overlap without color conflicts
- **Extensible**: Easy to add new sprites using available indices

