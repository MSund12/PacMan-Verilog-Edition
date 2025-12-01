// Top-level and vga_core with unified sprite/tile anchoring and fixed Blinky module
module PacMan(
  input  wire CLOCK_50,
  input  wire KEY0,
  input  wire [9:0] SW,        // NEW: onboard switches

  output wire [9:0] LEDR,
  output wire [6:0] HEX0, HEX1,
  output wire [3:0] VGA_R,
  output wire [3:0] VGA_G,
  output wire [3:0] VGA_B,
  output wire       VGA_HS,
  output wire       VGA_VS
);
  wire rst_n = KEY0;                // KEY0 is active-low
  wire pclk, pll_locked;

  pll_50_to_25 UPLL(
    .inclk0(CLOCK_50),
    .c0    (pclk),
    .locked(pll_locked)
  );

  wire [9:0] h;
  wire [9:0] v;
  wire       hs, vs;
  wire [3:0] r,g,b;

  vga_core_640x480 UCORE(
    .pclk(pclk),
    .rst_n(rst_n & pll_locked),

    // NEW: movement controls from switches
    .move_up   (SW[3]),
    .move_down (SW[2]),
    .move_left (SW[1]),
    .move_right(SW[0]),

    .h(h),
    .v(v),
    .hs(hs),
    .vs(vs),
    .r(r),
    .g(g),
    .b(b)
  );

  // Hook up physical VGA pins
  assign VGA_HS = hs;
  assign VGA_VS = vs;
  assign VGA_R  = r;
  assign VGA_G  = g;
  assign VGA_B  = b;

  // Debug LEDs
  assign LEDR[0] = hs;
  assign LEDR[1] = vs;
  assign LEDR[2] = 1'b0;
  assign LEDR[3] = h[5];
  assign LEDR[4] = h[8];
  assign LEDR[5] = v[5];
  assign LEDR[6] = v[8];
  assign LEDR[9:7] = 3'b000;

  // Turn off seven-seg displays (DE10-Lite HEX are active-low)
  assign HEX0 = 7'b1111111;
  assign HEX1 = 7'b1111111;
endmodule



module vga_core_640x480(
  input  wire        pclk,
  input  wire        rst_n,

  // NEW: movement controls
  input  wire        move_up,
  input  wire        move_down,
  input  wire        move_left,
  input  wire        move_right,

  output reg  [9:0]  h,
  output reg  [9:0]  v,
  output wire        hs,
  output wire        vs,
  output reg  [3:0]  r,
  output reg  [3:0]  g,
  output reg  [3:0]  b
);


  // 640x480 @ 60 Hz timing
  localparam H_VIS=640, H_FP=16, H_SYNC=96, H_BP=48, H_TOT=800;
  localparam V_VIS=480, V_FP=10, V_SYNC=2,  V_BP=33, V_TOT=525;

  // Image window (224x288) centered in 640x480
  localparam IMG_W  = 224;
  localparam IMG_H  = 288;
  localparam IMG_X0 = 208;  
  localparam IMG_Y0 = 96;

  // Tile grid: 28 x 36 tiles of 8x8 pixels
  localparam TILE_W   = 8;
  localparam TILE_H   = 8;
  localparam TILES_X  = 28;   // 224/8 = 28
  localparam TILES_Y  = 36;   // 288/8 = 36

  // Pac-Man sprite parameters
  localparam PAC_R = 6;        // 13x13 sprite radius
  localparam SPR_W = 13;
  localparam SPR_H = 13;
  
  // Ghost sprite parameters (16x16)
  localparam GHOST_R = 8;      // 16x16 sprite radius
  localparam GHOST_W = 16;
  localparam GHOST_H = 16;

  // -------------------------
  // H/V counters (stage 0)
  // -------------------------
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      h <= 10'd0;
      v <= 10'd0;
    end else begin
      if (h == H_TOT-1) begin
        h <= 10'd0;
        v <= (v == V_TOT-1) ? 10'd0 : v + 10'd1;
      end else begin
        h <= h + 10'd1;
      end
    end
  end

  wire frame_tick = (h == 10'd0 && v == 10'd0);

  // Sync and raw visible (stage 0)
  wire h_vis_raw = (h < H_VIS);
  wire v_vis_raw = (v < V_VIS);

  assign hs = ~((h >= H_VIS+H_FP) && (h < H_VIS+H_FP+H_SYNC));
  assign vs = ~((v >= V_VIS+V_FP) && (v < V_VIS+V_FP+V_SYNC));

  // ROM address for maze bitmap (stage 0)
  wire in_img_area_addr =
        h_vis_raw && v_vis_raw &&
        (h >= IMG_X0) && (h < IMG_X0 + IMG_W) &&
        (v >= IMG_Y0) && (v < IMG_Y0 + IMG_H);

  wire [8:0] img_x_addr = h - IMG_X0;  // 0..223 when in_img_area_addr
  wire [8:0] img_y_addr = v - IMG_Y0;  // 0..287 when in_img_area_addr

  wire [15:0] addr_y   = (img_y_addr << 8) - (img_y_addr << 5); // y*224
  wire [15:0] img_addr = in_img_area_addr ? (addr_y + img_x_addr) : 16'd0;

  // One-cycle delayed coordinates for display (stage 1)
  reg [9:0] h_d, v_d;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      h_d <= 10'd0;
      v_d <= 10'd0;
    end else begin
      h_d <= h;
      v_d <= v;
    end
  end

  // Visible / image window for display stage (aligned with pix_data)
  wire h_vis = (h_d < H_VIS);
  wire v_vis = (v_d < V_VIS);

  wire in_img_area =
        h_vis && v_vis &&
        (h_d >= IMG_X0) && (h_d < IMG_X0 + IMG_W) &&
        (v_d >= IMG_Y0) && (v_d < IMG_Y0 + IMG_H);

  // Delayed image coordinates for display stage (aligned with pix_data)
  wire [8:0] img_x_addr_d = h_d - IMG_X0;  // 0..223 when in_img_area
  wire [8:0] img_y_addr_d = v_d - IMG_Y0;  // 0..287 when in_img_area

  // Tile coordinates for dot lookup
  wire [4:0] tile_x = img_x_addr_d[7:3];  // 0..27 (divide by 8)
  wire [5:0] tile_y = img_y_addr_d[8:3];  // 0..35 (divide by 8) - FIX: use [8:3] not [7:3] for 9-bit value
  // Use the same optimization pattern as blinky_tile_idx: tile_y*28 = (tile_y << 5) - (tile_y << 2)
  wire [9:0] tile_index_dot_raw = ((tile_y << 5) - (tile_y << 2)) + tile_x;  // tile_y*28 + tile_x
  wire [9:0] tile_index_dot = (tile_index_dot_raw > 10'd1007) ? 10'd1007 : tile_index_dot_raw;  // Clamp to valid range
  
  // Dot ROM lookup
  wire tile_has_dot;
  dots_rom UDOTS (
    .tile_index(tile_index_dot),
    .has_dot(tile_has_dot)
  );
  
  // Check if current pixel is in center of tile (for dot rendering)
  // Dots are typically 2x2 pixels in center of 8x8 tile
  wire [2:0] pix_in_tile_x = img_x_addr_d[2:0];  // 0..7 within tile
  wire [2:0] pix_in_tile_y = img_y_addr_d[2:0];  // 0..7 within tile
  wire in_dot_area = (pix_in_tile_x >= 3) && (pix_in_tile_x <= 4) &&
                     (pix_in_tile_y >= 3) && (pix_in_tile_y <= 4);
  
  // Dot pixel (brown, index 0x6)
  wire dot_pixel = tile_has_dot && in_dot_area && in_img_area;
  

  // Maze ROM: 4-bit pixels, 1-cycle latency
  wire [3:0] pix_data;
  image_rom_224x288_4bpp UIMG (
    .clk (pclk),
    .addr(img_addr),
    .data(pix_data)
  );

    // -------------------------
  // Pac-Man position and tile-based collision
  // -------------------------
  // Pac-Man collision hitbox (13 wide × 13 tall)
  localparam HIT_W  = 13;
  localparam HIT_H  = 13;

  // Hitbox radius: ±6 pixels from center
  localparam HIT_RX = 6;
  localparam HIT_RY = 6;


  reg [9:0] pac_x, pac_y;     // center position (screen coords) - CENTER OF TILE anchor
  reg [1:0] pac_dir;          // 0=right,1=left,2=up,3=down

  // fractional speed accumulator for 125/99 pixels per frame
  // (≈ 75.7576 px/s at 60 Hz)
  reg [7:0] speed_acc;        // remainder modulo 99
  reg [7:0] tmp_acc;
  reg [1:0] step_px;          // 0,1,2 pixels this frame

  // center relative to maze origin (unsigned; only used when inside maze)
  wire [9:0] pac_local_x = pac_x - IMG_X0;
  wire [9:0] pac_local_y = pac_y - IMG_Y0;

  wire pac_in_maze =
      (pac_x >= IMG_X0) && (pac_x < IMG_X0 + IMG_W) &&
      (pac_y >= IMG_Y0) && (pac_y < IMG_Y0 + IMG_H);

  // Calculate step_px for this frame (combinational, based on current speed_acc)
  wire [7:0] tmp_acc_calc = speed_acc + 8'd125;
  wire [1:0] step_px_calc;
  wire [7:0] tmp_acc_after_first;
  wire [7:0] tmp_acc_after_second;
  
  assign tmp_acc_after_first = (tmp_acc_calc >= 8'd99) ? (tmp_acc_calc - 8'd99) : tmp_acc_calc;
  assign step_px_calc = (tmp_acc_calc >= 8'd99) ? 2'd1 : 2'd0;
  assign tmp_acc_after_second = (tmp_acc_after_first >= 8'd99) ? (tmp_acc_after_first - 8'd99) : tmp_acc_after_first;
  wire [1:0] step_px_wire = step_px_calc + ((tmp_acc_after_first >= 8'd99) ? 2'd1 : 2'd0);

  // Pixel-based collision detection: check all pixels along movement path
  // This prevents Pac-Man from skipping over 1-pixel-wide walls
  
  // Calculate positions for 1px and 2px ahead along movement direction
  wire [9:0] pac_local_x_1px, pac_local_y_1px;
  wire [9:0] pac_local_x_2px, pac_local_y_2px;
  
  assign pac_local_x_1px = (pac_dir == 2'd0) ? (pac_local_x + 10'd1) :  // right
                           (pac_dir == 2'd1) ? (pac_local_x - 10'd1) :  // left
                           pac_local_x;  // up/down: no change
  assign pac_local_y_1px = (pac_dir == 2'd2) ? (pac_local_y - 10'd1) :  // up
                           (pac_dir == 2'd3) ? (pac_local_y + 10'd1) :  // down
                           pac_local_y;  // left/right: no change
                           
  assign pac_local_x_2px = (pac_dir == 2'd0) ? (pac_local_x + 10'd2) :  // right
                           (pac_dir == 2'd1) ? (pac_local_x - 10'd2) :  // left
                           pac_local_x;  // up/down: no change
  assign pac_local_y_2px = (pac_dir == 2'd2) ? (pac_local_y - 10'd2) :  // up
                           (pac_dir == 2'd3) ? (pac_local_y + 10'd2) :  // down
                           pac_local_y;  // left/right: no change

  // Calculate check positions at front edge of hitbox for 1px and 2px ahead
  // For horizontal movement: check left/right edge; for vertical: check top/bottom edge
  wire [9:0] check_x_1px, check_y_1px;
  wire [9:0] check_x_2px, check_y_2px;
  
  assign check_x_1px = (pac_dir == 2'd0) ? (pac_local_x_1px + HIT_RX) :  // right: check right edge
                        (pac_dir == 2'd1) ? ((pac_local_x_1px >= HIT_RX) ? (pac_local_x_1px - HIT_RX) : 10'd0) :  // left: check left edge
                        pac_local_x_1px;  // up/down: use center x
  assign check_y_1px = (pac_dir == 2'd2) ? ((pac_local_y_1px >= HIT_RY) ? (pac_local_y_1px - HIT_RY) : 10'd0) :  // up: check top edge
                        (pac_dir == 2'd3) ? (pac_local_y_1px + HIT_RY) :  // down: check bottom edge
                        pac_local_y_1px;  // left/right: use center y
                        
  assign check_x_2px = (pac_dir == 2'd0) ? (pac_local_x_2px + HIT_RX) :  // right: check right edge
                        (pac_dir == 2'd1) ? ((pac_local_x_2px >= HIT_RX) ? (pac_local_x_2px - HIT_RX) : 10'd0) :  // left: check left edge
                        pac_local_x_2px;  // up/down: use center x
  assign check_y_2px = (pac_dir == 2'd2) ? ((pac_local_y_2px >= HIT_RY) ? (pac_local_y_2px - HIT_RY) : 10'd0) :  // up: check top edge
                        (pac_dir == 2'd3) ? (pac_local_y_2px + HIT_RY) :  // down: check bottom edge
                        pac_local_y_2px;  // left/right: use center y

  // Clamp to valid image bounds
  wire [9:0] check_x_1px_clamped = (check_x_1px > IMG_W-1) ? IMG_W-1 : check_x_1px;
  wire [9:0] check_y_1px_clamped = (check_y_1px > IMG_H-1) ? IMG_H-1 : check_y_1px;
  wire [9:0] check_x_2px_clamped = (check_x_2px > IMG_W-1) ? IMG_W-1 : check_x_2px;
  wire [9:0] check_y_2px_clamped = (check_y_2px > IMG_H-1) ? IMG_H-1 : check_y_2px;

  // Calculate ROM addresses for pixel checks
  // Address = y * 224 + x = (y << 8) - (y << 5) + x
  wire [15:0] wall_addr_1px = ((check_y_1px_clamped << 8) - (check_y_1px_clamped << 5)) + check_x_1px_clamped;
  wire [15:0] wall_addr_2px = ((check_y_2px_clamped << 8) - (check_y_2px_clamped << 5)) + check_x_2px_clamped;

  // Read pixel values from image ROM (wall pixels = 0xC = 4'hC)
  // ROM has 1-cycle latency (output is registered), so these values correspond
  // to addresses from the previous cycle. This is acceptable because:
  // 1. Addresses update every cycle based on current position
  // 2. We're checking positions ahead of current position (1px and 2px)
  // 3. Pac-Man moves slowly (1-2 pixels per frame at 60Hz)
  // The slight delay ensures we don't skip over 1-pixel-wide walls
  wire [3:0] wall_pix_1px, wall_pix_2px;
  image_rom_224x288_4bpp UWALL_1PX (
    .clk (pclk),
    .addr(wall_addr_1px),
    .data(wall_pix_1px)
  );
  image_rom_224x288_4bpp UWALL_2PX (
    .clk (pclk),
    .addr(wall_addr_2px),
    .data(wall_pix_2px)
  );

  // Collision detected if any checked pixel is a wall (0xC)
  // Check 1px position if moving at least 1px, check 2px position if moving 2px
  wire wall_at_1px = (wall_pix_1px == 4'hC);
  wire wall_at_2px = (wall_pix_2px == 4'hC);
  wire wall_at_target = (step_px_wire >= 2'd1 && wall_at_1px) || 
                        (step_px_wire >= 2'd2 && wall_at_2px);

  // Movement at ~75.7576 px/s using 125/99 pixels per frame
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      // Pac-Man starting tile: tile X=14, tile Y=28, facing left
      // Use center-of-tile anchor: IMG_X0 + tile*8 + 4
      pac_x     <= IMG_X0 + (14 << 3) + 4;        // center of tile 14
      pac_y     <= IMG_Y0 + (28 << 3) + 4;        // center of tile 28
      pac_dir   <= 2'd1;                          // left
      speed_acc <= 8'd0;
    end else begin
      if (frame_tick) begin
        // Use the pre-calculated step_px_wire for movement
        speed_acc <= tmp_acc_after_second;

        // move step_px_wire pixels this frame if path is clear
        if (step_px_wire != 2'd0 && pac_in_maze && !wall_at_target) begin
          case (pac_dir)
            2'd0: pac_x <= pac_x + step_px_wire;  // right
            2'd1: pac_x <= pac_x - step_px_wire;  // left
            2'd2: pac_y <= pac_y - step_px_wire;  // up
            2'd3: pac_y <= pac_y + step_px_wire;  // down
          endcase
        end
      end

      if (move_up)
        pac_dir <= 2'd2;   // up
      else if (move_down)
        pac_dir <= 2'd3;   // down
      else if (move_left)
        pac_dir <= 2'd1;   // left
      else if (move_right)
        pac_dir <= 2'd0;   // right
    end
  end

  // -------------------------
  // Blinky (Red Ghost) integration
  // -------------------------
  // Convert pacman center position to tile coordinates (6-bit) for blinky
  wire [5:0] pacman_tile_x = pac_local_x[9:3];  // 0..27
  wire [5:0] pacman_tile_y = pac_local_y[9:3];  // 0..35

  // Blinky position in tile coordinates (from blinky module)
  wire [5:0] blinky_tile_x, blinky_tile_y;

  // Blinky starting position (must match blinky.v)
  localparam [5:0] BLINKY_START_TILE_X = 6'd13;
  localparam [5:0] BLINKY_START_TILE_Y = 6'd16;
  localparam [3:0] BLINKY_START_OFFSET_X = 4'd8;  // 0-7: pixel offset within tile (8 = right edge, between tiles)
  localparam [3:0] BLINKY_START_OFFSET_Y = 4'd4;  // 4 = center

  // Check if Blinky is at starting position
  wire blinky_at_start = (blinky_tile_x == BLINKY_START_TILE_X) && (blinky_tile_y == BLINKY_START_TILE_Y);

  // Convert blinky tile position to screen coordinates
  // Use offset only at starting position, otherwise center of tile
  wire [3:0] blinky_offset_x = blinky_at_start ? BLINKY_START_OFFSET_X : 4'd4;
  wire [3:0] blinky_offset_y = blinky_at_start ? BLINKY_START_OFFSET_Y : 4'd4;
  wire [9:0] blinky_x = IMG_X0 + (blinky_tile_x << 3) + blinky_offset_x;
  wire [9:0] blinky_y = IMG_Y0 + (blinky_tile_y << 3) + blinky_offset_y;

  // Wall detection for blinky's current position (check all 4 directions)
  wire [9:0] blinky_tile_idx = ((blinky_tile_y << 5) - (blinky_tile_y << 2)) + blinky_tile_x;
  
  wire blinky_wall_up, blinky_wall_down, blinky_wall_left, blinky_wall_right;
  wire blinky_wall_up_rom, blinky_wall_down_rom, blinky_wall_left_rom, blinky_wall_right_rom;
  
  // Check walls in adjacent tiles (or treat boundaries as walls)
  wire [9:0] blinky_tile_idx_up    = blinky_tile_idx - 10'd28;
  wire [9:0] blinky_tile_idx_down  = blinky_tile_idx + 10'd28;
  wire [9:0] blinky_tile_idx_left  = blinky_tile_idx - 10'd1;
  wire [9:0] blinky_tile_idx_right = blinky_tile_idx + 10'd1;

  level_rom ULEVEL_BLINKY_UP (
    .tile_index(blinky_tile_idx_up),
    .is_wall(blinky_wall_up_rom)
  );
  
  level_rom ULEVEL_BLINKY_DOWN (
    .tile_index(blinky_tile_idx_down),
    .is_wall(blinky_wall_down_rom)
  );
  
  level_rom ULEVEL_BLINKY_LEFT (
    .tile_index(blinky_tile_idx_left),
    .is_wall(blinky_wall_left_rom)
  );
  
  level_rom ULEVEL_BLINKY_RIGHT (
    .tile_index(blinky_tile_idx_right),
    .is_wall(blinky_wall_right_rom)
  );

  // Treat boundaries as walls
  assign blinky_wall_up    = (blinky_tile_y == 0) ? 1'b1 : blinky_wall_up_rom;
  assign blinky_wall_down  = (blinky_tile_y == 35) ? 1'b1 : blinky_wall_down_rom;
  assign blinky_wall_left  = (blinky_tile_x == 0) ? 1'b1 : blinky_wall_left_rom;
  assign blinky_wall_right = (blinky_tile_x == 27) ? 1'b1 : blinky_wall_right_rom;

  // Chase/scatter mode control (default to chase mode)
  reg isChase, isScatter;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      isChase <= 1'b1;
      isScatter <= 1'b0;
    end else begin
      // For now, always chase. Can be extended later with timing logic
      isChase <= 1'b1;
      isScatter <= 1'b0;
    end
  end

  // Instantiate cleaned blinky module (tile-based)
  blinky UBLINKY (
    .clk(pclk),
    .reset(!rst_n),   // blinky expects active-high reset
    .pacmanX(pacman_tile_x),
    .pacmanY(pacman_tile_y),
    .isChase(isChase),
    .isScatter(isScatter),
    .wallUp(blinky_wall_up),
    .wallDown(blinky_wall_down),
    .wallLeft(blinky_wall_left),
    .wallRight(blinky_wall_right),
    .blinkyX(blinky_tile_x),
    .blinkyY(blinky_tile_y)
  );

  // -------------------------
  // Inky (Cyan Ghost) integration
  // -------------------------
  // Inky position in tile coordinates (from inky module)
  wire [5:0] inky_tile_x, inky_tile_y;

  // Inky starting position (must match inky.v)
  localparam [5:0] INKY_START_TILE_X = 6'd11;
  localparam [5:0] INKY_START_TILE_Y = 6'd19;
  localparam [3:0] INKY_START_OFFSET_X = 4'd8;  // 0-7: pixel offset within tile (8 = right edge, between tiles)
  localparam [3:0] INKY_START_OFFSET_Y = 4'd4;  // 4 = center

  // Check if Inky is at starting position
  wire inky_at_start = (inky_tile_x == INKY_START_TILE_X) && (inky_tile_y == INKY_START_TILE_Y);

  // Convert inky tile position to screen coordinates
  // Use offset only at starting position, otherwise center of tile
  wire [3:0] inky_offset_x = inky_at_start ? INKY_START_OFFSET_X : 4'd4;
  wire [3:0] inky_offset_y = inky_at_start ? INKY_START_OFFSET_Y : 4'd4;
  wire [9:0] inky_x = IMG_X0 + (inky_tile_x << 3) + inky_offset_x;
  wire [9:0] inky_y = IMG_Y0 + (inky_tile_y << 3) + inky_offset_y;

  // Wall detection for inky's current position (check all 4 directions)
  wire [9:0] inky_tile_idx = ((inky_tile_y << 5) - (inky_tile_y << 2)) + inky_tile_x;
  
  wire inky_wall_up, inky_wall_down, inky_wall_left, inky_wall_right;
  wire inky_wall_up_rom, inky_wall_down_rom, inky_wall_left_rom, inky_wall_right_rom;
  
  // Check walls in adjacent tiles (or treat boundaries as walls)
  wire [9:0] inky_tile_idx_up    = inky_tile_idx - 10'd28;
  wire [9:0] inky_tile_idx_down  = inky_tile_idx + 10'd28;
  wire [9:0] inky_tile_idx_left  = inky_tile_idx - 10'd1;
  wire [9:0] inky_tile_idx_right = inky_tile_idx + 10'd1;

  level_rom ULEVEL_INKY_UP (
    .tile_index(inky_tile_idx_up),
    .is_wall(inky_wall_up_rom)
  );
  
  level_rom ULEVEL_INKY_DOWN (
    .tile_index(inky_tile_idx_down),
    .is_wall(inky_wall_down_rom)
  );
  
  level_rom ULEVEL_INKY_LEFT (
    .tile_index(inky_tile_idx_left),
    .is_wall(inky_wall_left_rom)
  );
  
  level_rom ULEVEL_INKY_RIGHT (
    .tile_index(inky_tile_idx_right),
    .is_wall(inky_wall_right_rom)
  );

  // Treat boundaries as walls
  assign inky_wall_up    = (inky_tile_y == 0) ? 1'b1 : inky_wall_up_rom;
  assign inky_wall_down  = (inky_tile_y == 35) ? 1'b1 : inky_wall_down_rom;
  assign inky_wall_left  = (inky_tile_x == 0) ? 1'b1 : inky_wall_left_rom;
  assign inky_wall_right = (inky_tile_x == 27) ? 1'b1 : inky_wall_right_rom;

  // Convert pac_dir to Inky's format: 00=UP, 01=RIGHT, 10=DOWN, 11=LEFT
  // Pac-Man uses: 0=right, 1=left, 2=up, 3=down
  wire [1:0] pac_dir_inky_format = (pac_dir == 2'd2) ? 2'b00 :  // up
                                    (pac_dir == 2'd0) ? 2'b01 :  // right
                                    (pac_dir == 2'd3) ? 2'b10 :  // down
                                    2'b11;                       // left

  // Instantiate inky module (tile-based)
  inky UINKY (
    .clk(pclk),
    .reset(!rst_n),   // inky expects active-high reset
    .pacX(pacman_tile_x),
    .pacY(pacman_tile_y),
    .pacDir(pac_dir_inky_format),
    .blinkyX(blinky_tile_x),
    .blinkyY(blinky_tile_y),
    .canMoveUp(!inky_wall_up),
    .canMoveRight(!inky_wall_right),
    .canMoveDown(!inky_wall_down),
    .canMoveLeft(!inky_wall_left),
    .inkyX(inky_tile_x),
    .inkyY(inky_tile_y),
    .dir()  // direction output not used for rendering
  );

  // -------------------------
  // Pac-Man sprite (13x13) using Pacman.hex
  // -------------------------
  // top-left of sprite box (sprite is centered on pac_x,pac_y)
  wire [9:0] pac_left = pac_x - PAC_R;
  wire [9:0] pac_top  = pac_y - PAC_R;

  // sprite-local coordinates at this pixel
  wire [9:0] spr_x_full = h_d - pac_left;
  wire [9:0] spr_y_full = v_d - pac_top;

  wire       in_pac_box = (spr_x_full < SPR_W) && (spr_y_full < SPR_H);

  // Clamp sprite coordinates to valid range (0-12) to prevent out-of-bounds ROM access
  wire [3:0] spr_x_raw = (spr_x_full >= SPR_W) ? 4'd12 : spr_x_full[3:0];  // 0..12
  wire [3:0] spr_y_raw = (spr_y_full >= SPR_H) ? 4'd12 : spr_y_full[3:0];  // 0..12

  // Transform sprite coordinates based on direction
  // Assuming sprite ROM stores Pacman facing right (mouth open to the right)
  // pac_dir: 0=right, 1=left, 2=up, 3=down
  wire [3:0] spr_x, spr_y;
  
  // 0° for right: no change
  // 180° for left: (x,y) -> (12-x, 12-y)
  // 90° CW for up: (x,y) -> (12-y, x)
  // 90° CCW for down: (x,y) -> (y, 12-x)
  assign spr_x = (pac_dir == 2'd0) ? spr_x_raw :                    // right: no change
                 (pac_dir == 2'd1) ? (4'd12 - spr_x_raw) :          // left: 180° rotation (x' = 12-x)
                 (pac_dir == 2'd2) ? (4'd12 - spr_y_raw) :          // up: rotate 90° CW (x' = 12-y)
                 spr_y_raw;                                         // down: rotate 90° CCW (x' = y)
                 
  assign spr_y = (pac_dir == 2'd0) ? spr_y_raw :                    // right: no change
                 (pac_dir == 2'd1) ? (4'd12 - spr_y_raw) :          // left: 180° rotation (y' = 12-y)
                 (pac_dir == 2'd2) ? spr_x_raw :                    // up: rotate 90° CW (y' = x)
                 (4'd12 - spr_x_raw);                               // down: rotate 90° CCW (y' = 12-x)

  // Address calculation: y*13 + x = y*8 + y*4 + y + x
  wire [7:0] pac_addr = ((spr_y << 3) + (spr_y << 2) + spr_y + spr_x);  // y*13 + x

  wire [3:0] pac_pix_data;
  pacman_rom_16x16_4bpp UPAC (
    .addr(pac_addr),
    .data(pac_pix_data)
  );

  // Pac-Man pixel is "active" when inside box and sprite index != 0 (0 = transparent)
  wire pac_pix = in_pac_box && (pac_pix_data != 4'h0);

  // -------------------------
  // Blinky sprite (16x16) using Blinky.hex
  // -------------------------
  // top-left of sprite box
  wire [9:0] blinky_left = blinky_x - GHOST_R;
  wire [9:0] blinky_top  = blinky_y - GHOST_R;

  // sprite-local coordinates at this pixel
  wire [9:0] blinky_spr_x_full = h_d - blinky_left;
  wire [9:0] blinky_spr_y_full = v_d - blinky_top;

  wire       in_blinky_box = (blinky_spr_x_full < GHOST_W) && (blinky_spr_y_full < GHOST_H);

  wire [3:0] blinky_spr_x = blinky_spr_x_full[3:0];  // 0..15
  wire [3:0] blinky_spr_y = blinky_spr_y_full[3:0];  // 0..15

  wire [7:0] blinky_addr = (blinky_spr_y << 4) | blinky_spr_x;  // y*16 + x

  wire [3:0] blinky_pix_data;
  blinky_rom_16x16_4bpp UBLINKY_ROM (
    .addr(blinky_addr),
    .data(blinky_pix_data)
  );

  // Blinky pixel is "active" when inside box and sprite index != 0 (0 = transparent)
  wire blinky_pix = in_blinky_box && (blinky_pix_data != 4'h0);

  // -------------------------
  // Inky sprite (16x16) using Inky.hex
  // -------------------------
  // top-left of sprite box
  wire [9:0] inky_left = inky_x - GHOST_R;
  wire [9:0] inky_top  = inky_y - GHOST_R;

  // sprite-local coordinates at this pixel
  wire [9:0] inky_spr_x_full = h_d - inky_left;
  wire [9:0] inky_spr_y_full = v_d - inky_top;

  wire       in_inky_box = (inky_spr_x_full < GHOST_W) && (inky_spr_y_full < GHOST_H);

  wire [3:0] inky_spr_x = inky_spr_x_full[3:0];  // 0..15
  wire [3:0] inky_spr_y = inky_spr_y_full[3:0];  // 0..15

  wire [7:0] inky_addr = (inky_spr_y << 4) | inky_spr_x;  // y*16 + x

  wire [3:0] inky_pix_data;
  inky_rom_16x16_4bpp UINKY_ROM (
    .addr(inky_addr),
    .data(inky_pix_data)
  );

  // Inky pixel is "active" when inside box and sprite index != 0 (0 = transparent)
  wire inky_pix = in_inky_box && (inky_pix_data != 4'h0);

  // -------------------------
  // Unified palette lookup function
  // Maps 4-bit color index to RGB values
  // -------------------------
  function [11:0] palette_lookup;
    input [3:0] color_index;
    begin
      case (color_index)
        4'h0: palette_lookup = {4'h0, 4'h0, 4'h0};      // Black (transparent/background)
        4'h1: palette_lookup = {4'h8, 4'h0, 4'h0};      // Dark Red
        4'h2: palette_lookup = {4'h0, 4'h8, 4'h0};      // Dark Green
        4'h3: palette_lookup = {4'hF, 4'hA, 4'h0};      // Orange (Clyde)
        4'h4: palette_lookup = {4'h0, 4'h0, 4'h8};      // Dark Blue
        4'h5: palette_lookup = {4'h8, 4'h0, 4'h8};      // Dark Magenta/Purple
        4'h6: palette_lookup = {4'h9, 4'h4, 4'h1};      // Brown (pellets/dots)
        4'h7: palette_lookup = {4'hF, 4'h0, 4'h0};      // Red (Blinky)
        4'h8: palette_lookup = {4'h8, 4'h8, 4'h8};      // Gray
        4'h9: palette_lookup = {4'hF, 4'h8, 4'hF};      // Pink (Pinky)
        4'hA: palette_lookup = {4'h0, 4'hF, 4'h0};      // Green
        4'hB: palette_lookup = {4'hF, 4'hF, 4'h0};      // Yellow (Pac-Man)
        4'hC: palette_lookup = {4'h0, 4'h0, 4'hF};      // Blue (walls)
        4'hD: palette_lookup = {4'hF, 4'h0, 4'hF};      // Magenta
        4'hE: palette_lookup = {4'h0, 4'hF, 4'hF};      // Cyan (Inky)
        4'hF: palette_lookup = {4'hF, 4'hF, 4'hF};      // White
        default: palette_lookup = {4'h0, 4'h0, 4'h0};   // Black (fallback)
      endcase
    end
  endfunction

  // -------------------------
  // RGB output with sprite overlay
  // Uses unified palette for all sprites and background
  // -------------------------
  wire [3:0] final_color_index;
  wire [11:0] palette_rgb;  // {r, g, b}
  
  // Determine which pixel to display (priority: Pac-Man > Blinky > Inky > Dots > Maze)
  assign final_color_index = pac_pix ? pac_pix_data :
                            blinky_pix ? blinky_pix_data :
                            inky_pix ? inky_pix_data :
                            dot_pixel ? 4'h6 :  // Brown dot
                            in_img_area ? pix_data :
                            4'h0;
  
  // Look up RGB from unified palette
  assign palette_rgb = palette_lookup(final_color_index);

  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      r <= 4'h0;
      g <= 4'h0;
      b <= 4'h0;
    end else begin
      if (h_vis && v_vis) begin
        r <= palette_rgb[11:8];
        g <= palette_rgb[7:4];
        b <= palette_rgb[3:0];
      end else begin
        r <= 4'h0; g <= 4'h0; b <= 4'h0;            // blanking
      end
    end
  end
endmodule


// 224 x 288, 4-bit pixels: DEPTH = 224*288 = 64512
module image_rom_224x288_4bpp (
    input  wire        clk,
    input  wire [15:0] addr,   // 0 .. 64511
    output reg  [3:0]  data
);
    reg [3:0] mem [0:64512-1];

    initial begin
        $readmemh("WithoutDots.hex", mem);
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end
endmodule


// Pac-Man sprite: 13x13, 4-bit pixels (0=transparent, uses unified palette) from Pacman.hex
// NOTE: Current BMP uses index 7 for yellow; should be remapped to index 0xB for unified palette
module pacman_rom_16x16_4bpp (
    input  wire [7:0] addr,   // 0 .. 168 (13*13-1)
    output reg  [3:0] data
);
    reg [3:0] mem [0:169-1];

    initial begin
        $readmemh("Pacman.hex", mem);
    end

    always @* begin
        data = mem[addr];
    end
endmodule


// Blinky sprite: 16x16, 4-bit pixels (0=transparent, uses unified palette) from Blinky.hex
// NOTE: Current BMP uses index 7 for red; matches unified palette index 7
module blinky_rom_16x16_4bpp (
    input  wire [7:0] addr,   // 0 .. 255
    output reg  [3:0] data
);
    reg [3:0] mem [0:256-1];

    initial begin
        $readmemh("Blinky.hex", mem);
    end

    always @* begin
        data = mem[addr];
    end
endmodule


// Inky sprite: 16x16, 4-bit pixels (0=transparent, uses unified palette) from Inky.hex
// NOTE: Current BMP uses index 0xE for cyan; matches unified palette index 0xE
module inky_rom_16x16_4bpp (
    input  wire [7:0] addr,   // 0 .. 255
    output reg  [3:0] data
);
    reg [3:0] mem [0:256-1];

    initial begin
        $readmemh("Inky.hex", mem);
    end

    always @* begin
        data = mem[addr];
    end
endmodule


// 28 x 36 = 1008 tiles, 1 bit per tile: 0=path, 1=wall/dead space
module level_rom (
    input  wire [9:0] tile_index,   // 0..1007 (y*28 + x)
    output wire       is_wall
);
    // Memory: 1008 entries, 1 bit each
    reg bits [0:1007];

    integer i;
    initial begin
        // Initialize to 0 in case file is missing/short
        for (i = 0; i < 1008; i = i + 1)
            bits[i] = 1'b0;

        // Load 0/1 values from file: one bit per line
        $readmemb("level_map.bin", bits);
    end

    assign is_wall = bits[tile_index];
endmodule


// 28 x 36 = 1008 tiles, 1 bit per tile: 0=no dot, 1=dot present
module dots_rom (
    input  wire [9:0] tile_index,   // 0..1007 (y*28 + x)
    output wire       has_dot
);
    // Memory: 1008 entries, 1 bit each
    reg bits [0:1007];

    integer i;
    initial begin
        // Initialize to 0 in case file is missing/short
        for (i = 0; i < 1008; i = i + 1)
            bits[i] = 1'b0;

        // Load 0/1 values from file: one bit per line
        $readmemb("dots_map.bin", bits);
    end

    assign has_dot = bits[tile_index];
endmodule