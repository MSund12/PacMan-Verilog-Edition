// Top-level Pac-Man game module for DE10-Lite FPGA
module PacMan(
  input  wire CLOCK_50,
  input  wire KEY0,
  input  wire KEY1,
  input  wire [9:0] SW,

  output wire [9:0] LEDR,
  output wire [6:0] HEX0, HEX1,
  output wire [3:0] VGA_R,
  output wire [3:0] VGA_G,
  output wire [3:0] VGA_B,
  output wire       VGA_HS,
  output wire       VGA_VS
);
  wire rst_n = KEY0;
  wire pclk, pll_locked;

  // Generate 25MHz pixel clock from 50MHz system clock
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

    .start_button(KEY1),

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

  // Connect VGA outputs
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

  // Turn off seven-segment displays
  assign HEX0 = 7'b1111111;
  assign HEX1 = 7'b1111111;
endmodule

// VGA core with game logic: 640x480 @ 60Hz, Pac-Man gameplay
module vga_core_640x480(
  input  wire        pclk,
  input  wire        rst_n,

  input  wire        start_button,

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

  // VGA timing parameters for 640x480 @ 60Hz
  localparam H_VIS=640, H_FP=16, H_SYNC=96, H_BP=48, H_TOT=800;
  localparam V_VIS=480, V_FP=10, V_SYNC=2,  V_BP=33, V_TOT=525;

  // Game area: 224x288 pixels centered on screen
  localparam IMG_W  = 224;
  localparam IMG_H  = 288;
  localparam IMG_X0 = 208;  
  localparam IMG_Y0 = 96;

  // Tile grid: 28x36 tiles, each 8x8 pixels
  localparam TILE_W   = 8;
  localparam TILE_H   = 8;
  localparam TILES_X  = 28;
  localparam TILES_Y  = 36;

  // Pac-Man sprite: 13x13 pixels
  localparam PAC_R = 6;
  localparam SPR_W = 13;
  localparam SPR_H = 13;
  
  // Ghost sprites: 16x16 pixels
  localparam GHOST_R = 8;
  localparam GHOST_W = 16;
  localparam GHOST_H = 16;

  // Horizontal and vertical counters for VGA timing
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

  // Frame tick: pulses once per frame at start of vertical blanking
  wire frame_tick = (h == 10'd0 && v == 10'd0);

  // Death animation: flash Pac-Man 3 times before hiding
  // Flash counter: 0-5 for 3 flashes (on/off/on/off/on/off)
  // Flash at ~10Hz: every 6 frames at 60Hz = ~0.1s per flash cycle
  reg [2:0] death_flash_count;      // Counts 0-5 for 3 flashes
  reg [2:0] flash_frame_counter;   // Frames between flashes (0-5)
  reg death_animation_done;        // Set when animation completes
  
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      death_flash_count <= 3'd0;
      flash_frame_counter <= 3'd0;
      death_animation_done <= 1'b0;
    end else begin
      if (game_state == STATE_DEAD && !death_animation_done) begin
        if (frame_tick) begin
          // Wait 6 frames before next flash
          if (flash_frame_counter >= 3'd5) begin
            flash_frame_counter <= 3'd0;
            // Increment flash count until 5 (3 flashes = 6 states)
            if (death_flash_count < 3'd5) begin
              death_flash_count <= death_flash_count + 3'd1;
            end else begin
              // Animation complete: hide Pac-Man permanently
              death_animation_done <= 1'b1;
            end
          end else begin
            flash_frame_counter <= flash_frame_counter + 3'd1;
          end
        end
      end else if (game_state != STATE_DEAD) begin
        // Reset animation when leaving DEAD state
        death_flash_count <= 3'd0;
        flash_frame_counter <= 3'd0;
        death_animation_done <= 1'b0;
      end
    end
  end
  
  // Flash signal: visible when flash_count is even (0, 2, 4)
  // LSB determines visibility: 0=visible, 1=hidden
  wire pacman_flash_visible = (death_flash_count[0] == 1'b0);

  // Game state machine: controls game flow
  localparam [1:0] STATE_WAITING = 2'd0;  // Waiting for start button
  localparam [1:0] STATE_PLAYING = 2'd1;  // Game is running
  localparam [1:0] STATE_DEAD   = 2'd2;   // Pac-Man died, game over
  
  reg [1:0] game_state = STATE_WAITING;
  reg start_button_prev = 1'b1;  // KEY1 is active-low, default to 1 (not pressed)
  // Detect falling edge: button goes from 1 to 0 (press)
  wire start_button_pressed = !start_button && start_button_prev;
  
  wire game_playing = (game_state == STATE_PLAYING);
  wire game_dead = (game_state == STATE_DEAD);
  wire game_waiting = (game_state == STATE_WAITING);

  // VGA sync signals: active-low pulses during blanking
  wire h_vis_raw = (h < H_VIS);  // Horizontal visible area
  wire v_vis_raw = (v < V_VIS);  // Vertical visible area

  // Horizontal sync: low during sync pulse (H_VIS+H_FP to H_VIS+H_FP+H_SYNC)
  assign hs = ~((h >= H_VIS+H_FP) && (h < H_VIS+H_FP+H_SYNC));
  // Vertical sync: low during sync pulse (V_VIS+V_FP to V_VIS+V_FP+V_SYNC)
  assign vs = ~((v >= V_VIS+V_FP) && (v < V_VIS+V_FP+V_SYNC));

  // Check if current pixel is in game area (for ROM addressing)
  wire in_img_area_addr =
        h_vis_raw && v_vis_raw &&
        (h >= IMG_X0) && (h < IMG_X0 + IMG_W) &&
        (v >= IMG_Y0) && (v < IMG_Y0 + IMG_H);

  // Calculate ROM address for maze bitmap
  // Convert screen coordinates to image-local coordinates
  wire [8:0] img_x_addr = h - IMG_X0;  // 0..223 when in image area
  wire [8:0] img_y_addr = v - IMG_Y0;  // 0..287 when in image area

  // Calculate address: y*224 + x
  // Optimized: y*224 = y*256 - y*32 = (y << 8) - (y << 5)
  wire [15:0] addr_y   = (img_y_addr << 8) - (img_y_addr << 5); // y*224
  wire [15:0] img_addr = in_img_area_addr ? (addr_y + img_x_addr) : 16'd0;

  // Delay coordinates by one cycle to align with ROM output
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

  // Visible area check for display stage
  wire h_vis = (h_d < H_VIS);
  wire v_vis = (v_d < V_VIS);

  wire in_img_area =
        h_vis && v_vis &&
        (h_d >= IMG_X0) && (h_d < IMG_X0 + IMG_W) &&
        (v_d >= IMG_Y0) && (v_d < IMG_Y0 + IMG_H);

  // Calculate tile coordinates for dot lookup
  wire [8:0] img_x_addr_d = h_d - IMG_X0;  // Image-local X coordinate
  wire [8:0] img_y_addr_d = v_d - IMG_Y0;  // Image-local Y coordinate

  // Extract tile coordinates: divide by 8 (shift right by 3 bits)
  wire [4:0] tile_x = img_x_addr_d[7:3];  // Tile X: 0..27
  wire [5:0] tile_y = img_y_addr_d[8:3];  // Tile Y: 0..35 (need [8:3] for 9-bit value)

  // Calculate tile index: tile_y*28 + tile_x
  // Optimized: tile_y*28 = tile_y*32 - tile_y*4 = (tile_y << 5) - (tile_y << 2)
  wire [9:0] tile_index_dot_raw = ((tile_y << 5) - (tile_y << 2)) + tile_x;
  // Clamp to valid range (28*36 = 1008 tiles, indices 0..1007)
  wire [9:0] tile_index_dot = (tile_index_dot_raw > 10'd1007) ? 10'd1007 : tile_index_dot_raw;
  
  wire tile_has_dot;
  wire pacman_tile_has_dot_ram;
  
  // Check if pixel is in center of tile (where dots are rendered)
  // Dots are 2x2 pixels in the center of 8x8 tile (pixels 3-4 in both X and Y)
  wire [2:0] pix_in_tile_x = img_x_addr_d[2:0];  // Pixel X within tile: 0..7
  wire [2:0] pix_in_tile_y = img_y_addr_d[2:0];  // Pixel Y within tile: 0..7
  wire in_dot_area = (pix_in_tile_x >= 3) && (pix_in_tile_x <= 4) &&
                     (pix_in_tile_y >= 3) && (pix_in_tile_y <= 4);
  
  // Dot pixel: render brown dot if tile has dot and pixel is in dot area
  wire dot_pixel = tile_has_dot && in_dot_area && in_img_area;
  
  // Maze ROM: stores 4-bit color indices for background
  wire [3:0] pix_data;
  image_rom_224x288_4bpp UIMG (
    .clk (pclk),
    .addr(img_addr),
    .data(pix_data)
  );

  // Pac-Man collision hitbox: 13x13 pixels
  localparam HIT_W  = 13;
  localparam HIT_H  = 13;

  localparam HIT_RX = 6;
  localparam HIT_RY = 6;

  // Pac-Man position and direction (0=right, 1=left, 2=up, 3=down)
  reg [9:0] pac_x, pac_y;
  reg [1:0] pac_dir;

  // Fractional speed accumulator: 125/99 pixels per frame (~75.76 px/s at 60Hz)
  reg [7:0] speed_acc;
  reg [7:0] tmp_acc;
  reg [1:0] step_px;

  // Convert screen coordinates to maze-local coordinates
  wire [9:0] pac_local_x = pac_x - IMG_X0;
  wire [9:0] pac_local_y = pac_y - IMG_Y0;

  wire pac_in_maze =
      (pac_x >= IMG_X0) && (pac_x < IMG_X0 + IMG_W) &&
      (pac_y >= IMG_Y0) && (pac_y < IMG_Y0 + IMG_H);

  // Calculate movement step: 0, 1, or 2 pixels per frame
  // Speed: 125/99 pixels per frame = ~1.2626 px/frame
  // This allows movement of 1 or 2 pixels per frame based on accumulator
  wire [7:0] tmp_acc_calc = speed_acc + 8'd125;
  wire [1:0] step_px_calc;
  wire [7:0] tmp_acc_after_first;
  wire [7:0] tmp_acc_after_second;
  
  // First step: check if accumulator >= 99 (1 pixel movement)
  assign tmp_acc_after_first = (tmp_acc_calc >= 8'd99) ? (tmp_acc_calc - 8'd99) : tmp_acc_calc;
  assign step_px_calc = (tmp_acc_calc >= 8'd99) ? 2'd1 : 2'd0;
  // Second step: check if remaining accumulator >= 99 (second pixel movement)
  assign tmp_acc_after_second = (tmp_acc_after_first >= 8'd99) ? (tmp_acc_after_first - 8'd99) : tmp_acc_after_first;
  // Total step: 0, 1, or 2 pixels
  wire [1:0] step_px_wire = step_px_calc + ((tmp_acc_after_first >= 8'd99) ? 2'd1 : 2'd0);

  // Calculate positions 1px and 2px ahead for collision detection
  // This prevents Pac-Man from skipping over 1-pixel-wide walls
  wire [9:0] pac_local_x_1px, pac_local_y_1px;
  wire [9:0] pac_local_x_2px, pac_local_y_2px;
  
  // Position 1 pixel ahead in movement direction
  assign pac_local_x_1px = (pac_dir == 2'd0) ? (pac_local_x + 10'd1) :  // right
                           (pac_dir == 2'd1) ? (pac_local_x - 10'd1) :  // left
                           pac_local_x;  // up/down: no change
  assign pac_local_y_1px = (pac_dir == 2'd2) ? (pac_local_y - 10'd1) :  // up
                           (pac_dir == 2'd3) ? (pac_local_y + 10'd1) :  // down
                           pac_local_y;  // left/right: no change
                           
  // Position 2 pixels ahead in movement direction
  assign pac_local_x_2px = (pac_dir == 2'd0) ? (pac_local_x + 10'd2) :  // right
                           (pac_dir == 2'd1) ? (pac_local_x - 10'd2) :  // left
                           pac_local_x;  // up/down: no change
  assign pac_local_y_2px = (pac_dir == 2'd2) ? (pac_local_y - 10'd2) :  // up
                           (pac_dir == 2'd3) ? (pac_local_y + 10'd2) :  // down
                           pac_local_y;  // left/right: no change

  // Calculate check positions at front edge of hitbox for collision detection
  // Check multiple points across hitbox to prevent slipping through gaps
  // For horizontal movement: check top and bottom edges
  // For vertical movement: check left and right edges
  wire [9:0] check_x_1px_top, check_y_1px_top;
  wire [9:0] check_x_1px_bot, check_y_1px_bot;
  wire [9:0] check_x_2px_top, check_y_2px_top;
  wire [9:0] check_x_2px_bot, check_y_2px_bot;
  
  // Check positions 1px ahead: front edge of hitbox
  // Horizontal movement: check right/left edge at top and bottom
  assign check_x_1px_top = (pac_dir == 2'd0) ? (pac_local_x_1px + HIT_RX) :  // right: check right edge
                           (pac_dir == 2'd1) ? ((pac_local_x_1px >= HIT_RX) ? (pac_local_x_1px - HIT_RX) : 10'd0) :  // left: check left edge
                           ((pac_local_x_1px >= HIT_RX) ? (pac_local_x_1px - HIT_RX) : 10'd0);  // up/down: check left edge
  assign check_y_1px_top = (pac_dir == 2'd2) ? ((pac_local_y_1px >= HIT_RY) ? (pac_local_y_1px - HIT_RY) : 10'd0) :  // up: check top edge
                           (pac_dir == 2'd3) ? (pac_local_y_1px + HIT_RY) :  // down: check bottom edge
                           ((pac_local_y_1px >= HIT_RY) ? (pac_local_y_1px - HIT_RY) : 10'd0);  // left/right: check top edge
                           
  assign check_x_1px_bot = (pac_dir == 2'd0) ? (pac_local_x_1px + HIT_RX) :  // right: check right edge
                           (pac_dir == 2'd1) ? ((pac_local_x_1px >= HIT_RX) ? (pac_local_x_1px - HIT_RX) : 10'd0) :  // left: check left edge
                           (pac_local_x_1px + HIT_RX);  // up/down: check right edge
  assign check_y_1px_bot = (pac_dir == 2'd2) ? ((pac_local_y_1px >= HIT_RY) ? (pac_local_y_1px - HIT_RY) : 10'd0) :  // up: check top edge
                           (pac_dir == 2'd3) ? (pac_local_y_1px + HIT_RY) :  // down: check bottom edge
                           (pac_local_y_1px + HIT_RY);  // left/right: check bottom edge
                           
  // Check positions 2px ahead: front edge of hitbox
  assign check_x_2px_top = (pac_dir == 2'd0) ? (pac_local_x_2px + HIT_RX) :  // right: check right edge
                           (pac_dir == 2'd1) ? ((pac_local_x_2px >= HIT_RX) ? (pac_local_x_2px - HIT_RX) : 10'd0) :  // left: check left edge
                           ((pac_local_x_2px >= HIT_RX) ? (pac_local_x_2px - HIT_RX) : 10'd0);  // up/down: check left edge
  assign check_y_2px_top = (pac_dir == 2'd2) ? ((pac_local_y_2px >= HIT_RY) ? (pac_local_y_2px - HIT_RY) : 10'd0) :  // up: check top edge
                           (pac_dir == 2'd3) ? (pac_local_y_2px + HIT_RY) :  // down: check bottom edge
                           ((pac_local_y_2px >= HIT_RY) ? (pac_local_y_2px - HIT_RY) : 10'd0);  // left/right: check top edge
                           
  assign check_x_2px_bot = (pac_dir == 2'd0) ? (pac_local_x_2px + HIT_RX) :  // right: check right edge
                           (pac_dir == 2'd1) ? ((pac_local_x_2px >= HIT_RX) ? (pac_local_x_2px - HIT_RX) : 10'd0) :  // left: check left edge
                           (pac_local_x_2px + HIT_RX);  // up/down: check right edge
  assign check_y_2px_bot = (pac_dir == 2'd2) ? ((pac_local_y_2px >= HIT_RY) ? (pac_local_y_2px - HIT_RY) : 10'd0) :  // up: check top edge
                           (pac_dir == 2'd3) ? (pac_local_y_2px + HIT_RY) :  // down: check bottom edge
                           (pac_local_y_2px + HIT_RY);  // left/right: check bottom edge

  // Clamp check positions to valid image bounds to prevent out-of-range ROM access
  wire [9:0] check_x_1px_top_clamped = (check_x_1px_top > IMG_W-1) ? IMG_W-1 : check_x_1px_top;
  wire [9:0] check_y_1px_top_clamped = (check_y_1px_top > IMG_H-1) ? IMG_H-1 : check_y_1px_top;
  wire [9:0] check_x_1px_bot_clamped = (check_x_1px_bot > IMG_W-1) ? IMG_W-1 : check_x_1px_bot;
  wire [9:0] check_y_1px_bot_clamped = (check_y_1px_bot > IMG_H-1) ? IMG_H-1 : check_y_1px_bot;
  wire [9:0] check_x_2px_top_clamped = (check_x_2px_top > IMG_W-1) ? IMG_W-1 : check_x_2px_top;
  wire [9:0] check_y_2px_top_clamped = (check_y_2px_top > IMG_H-1) ? IMG_H-1 : check_y_2px_top;
  wire [9:0] check_x_2px_bot_clamped = (check_x_2px_bot > IMG_W-1) ? IMG_W-1 : check_x_2px_bot;
  wire [9:0] check_y_2px_bot_clamped = (check_y_2px_bot > IMG_H-1) ? IMG_H-1 : check_y_2px_bot;

  // Calculate ROM addresses for pixel checks: y*224 + x
  wire [15:0] wall_addr_1px_top = ((check_y_1px_top_clamped << 8) - (check_y_1px_top_clamped << 5)) + check_x_1px_top_clamped;
  wire [15:0] wall_addr_1px_bot = ((check_y_1px_bot_clamped << 8) - (check_y_1px_bot_clamped << 5)) + check_x_1px_bot_clamped;
  wire [15:0] wall_addr_2px_top = ((check_y_2px_top_clamped << 8) - (check_y_2px_top_clamped << 5)) + check_x_2px_top_clamped;
  wire [15:0] wall_addr_2px_bot = ((check_y_2px_bot_clamped << 8) - (check_y_2px_bot_clamped << 5)) + check_x_2px_bot_clamped;

  // Read pixel values from image ROM (wall pixels = 0xC = 4'hC)
  // ROM has 1-cycle latency, but addresses update every cycle based on current position
  // We're checking positions ahead of current position, so slight delay is acceptable
  wire [3:0] wall_pix_1px_top, wall_pix_1px_bot;
  wire [3:0] wall_pix_2px_top, wall_pix_2px_bot;
  image_rom_224x288_4bpp UWALL_1PX_TOP (
    .clk (pclk),
    .addr(wall_addr_1px_top),
    .data(wall_pix_1px_top)
  );
  image_rom_224x288_4bpp UWALL_1PX_BOT (
    .clk (pclk),
    .addr(wall_addr_1px_bot),
    .data(wall_pix_1px_bot)
  );
  image_rom_224x288_4bpp UWALL_2PX_TOP (
    .clk (pclk),
    .addr(wall_addr_2px_top),
    .data(wall_pix_2px_top)
  );
  image_rom_224x288_4bpp UWALL_2PX_BOT (
    .clk (pclk),
    .addr(wall_addr_2px_bot),
    .data(wall_pix_2px_bot)
  );

  // Collision detection: check if wall pixels (0xC) are in path
  // Check both top and bottom/left and right edges to prevent slipping through gaps
  wire wall_at_1px = (wall_pix_1px_top == 4'hC) || (wall_pix_1px_bot == 4'hC);
  wire wall_at_2px = (wall_pix_2px_top == 4'hC) || (wall_pix_2px_bot == 4'hC);
  // Collision if moving 1px and wall at 1px, or moving 2px and wall at 2px
  wire wall_at_target = (step_px_wire >= 2'd1 && wall_at_1px) || 
                        (step_px_wire >= 2'd2 && wall_at_2px);

  // Pac-Man movement logic
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      // Starting position: tile (14, 28), facing left
      pac_x     <= IMG_X0 + (14 << 3) + 4;
      pac_y     <= IMG_Y0 + (28 << 3) + 4;
      pac_dir   <= 2'd1;
      speed_acc <= 8'd0;
    end else begin
      if (frame_tick && game_playing) begin
        speed_acc <= tmp_acc_after_second;

        // Move if path is clear and not stopped by dot eating
        if (step_px_wire != 2'd0 && pac_in_maze && !wall_at_target && !pac_stop_frame) begin
          case (pac_dir)
            2'd0: pac_x <= pac_x + step_px_wire;
            2'd1: pac_x <= pac_x - step_px_wire;
            2'd2: pac_y <= pac_y - step_px_wire;
            2'd3: pac_y <= pac_y + step_px_wire;
          endcase
			 
          // Tunnel teleport: wrap around screen edges at row 19
          // Left tunnel: tile (0, 19) moving left -> teleport to tile (27, 19)
          if ((pacman_tile_x == 6'd0) && (pacman_tile_y == 6'd19) && (pac_dir == 2'd1)) begin
            pac_x <= IMG_X0 + (27 << 3) + 4;  // Right side, center of tile
            pac_y <= IMG_Y0 + (19 << 3) + 4;
          end
          // Right tunnel: tile (27, 19) moving right -> teleport to tile (0, 19)
          else if ((pacman_tile_x == 6'd27) && (pacman_tile_y == 6'd19) && (pac_dir == 2'd0)) begin
            pac_x <= IMG_X0 + (0 << 3) + 4;   // Left side, center of tile
            pac_y <= IMG_Y0 + (19 << 3) + 4;
          end
			 
        end
      end

      // Direction change from switches
      if (game_playing) begin
        if (move_up)
          pac_dir <= 2'd2;
        else if (move_down)
          pac_dir <= 2'd3;
        else if (move_left)
          pac_dir <= 2'd1;
        else if (move_right)
          pac_dir <= 2'd0;
      end
    end
  end

  // Convert Pac-Man position to tile coordinates for dot detection
  wire [5:0] pacman_tile_x = pac_local_x[9:3];  // Divide by 8: tile X (0..27)
  wire [5:0] pacman_tile_y = pac_local_y[9:3];  // Divide by 8: tile Y (0..35)
  
  // Calculate Pac-Man's current tile index: tile_y*28 + tile_x
  wire [9:0] pacman_tile_idx = ((pacman_tile_y << 5) - (pacman_tile_y << 2)) + pacman_tile_x;
  
  // Dual-port RAM for dots: one port for display, one for Pac-Man detection
  dots_ram UDOTS (
    .clk(pclk),
    .rst_n(rst_n),
    .read_tile_index_1(tile_index_dot),
    .read_tile_index_2(pacman_tile_idx),
    .write_tile_index(dot_eaten_tile_idx),
    .write_enable(dot_eaten),
    .write_data(1'b0),
    .has_dot_1(tile_has_dot),
    .has_dot_2(pacman_tile_has_dot_ram)
  );
  
  wire pacman_tile_has_dot = pacman_tile_has_dot_ram;
  
  // Dot eating logic: detect when Pac-Man enters a new tile with a dot
  reg [9:0] last_pacman_tile_idx;
  reg dot_eaten;
  reg pac_stop_frame;
  
  reg [15:0] score;
  
  reg [9:0] dot_eaten_tile_idx;
  
  reg [1:0] dot_eaten_counter;
  
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      score <= 16'd0;
      last_pacman_tile_idx <= 10'd0;
      dot_eaten <= 1'b0;
      pac_stop_frame <= 1'b0;
      dot_eaten_tile_idx <= 10'd0;
      dot_eaten_counter <= 2'd0;
    end else begin
      if (game_playing) begin
        pac_stop_frame <= 1'b0;
        
        if (frame_tick) begin
          // Check if Pac-Man entered a new tile with a dot
          // No centering requirement: dots eaten immediately when entering tile
          if ((pacman_tile_idx != last_pacman_tile_idx) && pacman_tile_has_dot) begin
            dot_eaten <= 1'b1;  // Set write enable for RAM
            dot_eaten_tile_idx <= pacman_tile_idx;  // Remember which tile to clear
            dot_eaten_counter <= 2'd2;  // Keep write enable high for 2 cycles
            score <= score + 16'd10;  // Add 10 points per dot
            pac_stop_frame <= 1'b1;  // Stop Pac-Man for 1 frame when eating
            last_pacman_tile_idx <= pacman_tile_idx;  // Remember this tile
          end else if (pacman_tile_idx != last_pacman_tile_idx) begin
            // Update last tile index even if no dot (allows eating dots on return)
            last_pacman_tile_idx <= pacman_tile_idx;
          end
          
          // Keep write enable high for 2 cycles to ensure RAM write completes
          if (dot_eaten_counter > 2'd0) begin
            dot_eaten_counter <= dot_eaten_counter - 2'd1;
            dot_eaten <= 1'b1;
          end else begin
            dot_eaten <= 1'b0;
          end
        end else begin
          // Not frame_tick: keep write enable high if counter is active
          if (dot_eaten_counter > 2'd0) begin
            dot_eaten <= 1'b1;
          end else begin
            dot_eaten <= 1'b0;
          end
        end
      end else begin
        dot_eaten <= 1'b0;
        pac_stop_frame <= 1'b0;
      end
    end
  end

  // Blinky (Red Ghost) integration
  wire [5:0] blinky_tile_x, blinky_tile_y;

  localparam [5:0] BLINKY_START_TILE_X = 6'd13;
  localparam [5:0] BLINKY_START_TILE_Y = 6'd16;
  localparam [3:0] BLINKY_START_OFFSET_X = 4'd8;
  localparam [3:0] BLINKY_START_OFFSET_Y = 4'd4;

  wire blinky_at_start = (blinky_tile_x == BLINKY_START_TILE_X) && (blinky_tile_y == BLINKY_START_TILE_Y);

  // Convert tile position to screen coordinates
  // Use offset only at starting position, otherwise center of tile (offset = 4)
  wire [3:0] blinky_offset_x = blinky_at_start ? BLINKY_START_OFFSET_X : 4'd4;
  wire [3:0] blinky_offset_y = blinky_at_start ? BLINKY_START_OFFSET_Y : 4'd4;
  // Screen X = image X0 + tile_x*8 + offset
  wire [9:0] blinky_x = IMG_X0 + (blinky_tile_x << 3) + blinky_offset_x;
  wire [9:0] blinky_y = IMG_Y0 + (blinky_tile_y << 3) + blinky_offset_y;

  // Wall detection for Blinky: check adjacent tiles in all 4 directions
  wire [9:0] blinky_tile_idx = ((blinky_tile_y << 5) - (blinky_tile_y << 2)) + blinky_tile_x;
  
  wire blinky_wall_up, blinky_wall_down, blinky_wall_left, blinky_wall_right;
  wire blinky_wall_up_rom, blinky_wall_down_rom, blinky_wall_left_rom, blinky_wall_right_rom;
  
  // Calculate tile indices for adjacent tiles
  wire [9:0] blinky_tile_idx_up    = blinky_tile_idx - 10'd28;  // Up: subtract 28 (one row)
  wire [9:0] blinky_tile_idx_down  = blinky_tile_idx + 10'd28;  // Down: add 28 (one row)
  wire [9:0] blinky_tile_idx_left  = blinky_tile_idx - 10'd1;   // Left: subtract 1
  wire [9:0] blinky_tile_idx_right = blinky_tile_idx + 10'd1;   // Right: add 1

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

  // Treat screen boundaries as walls
  assign blinky_wall_up    = (blinky_tile_y == 0) ? 1'b1 : blinky_wall_up_rom;
  assign blinky_wall_down  = (blinky_tile_y == 35) ? 1'b1 : blinky_wall_down_rom;
  assign blinky_wall_left  = (blinky_tile_x == 0) ? 1'b1 : blinky_wall_left_rom;
  assign blinky_wall_right = (blinky_tile_x == 27) ? 1'b1 : blinky_wall_right_rom;

  // Ghost mode control (currently always chase)
  reg isChase, isScatter;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      isChase <= 1'b1;
      isScatter <= 1'b0;
    end else begin
      isChase <= 1'b1;
      isScatter <= 1'b0;
    end
  end

  // Ghost control signals
  wire ghost_reset = !rst_n || game_waiting;
  wire ghost_enable = game_playing;

  blinky UBLINKY (
    .clk(pclk),
    .reset(ghost_reset),
    .enable(ghost_enable),
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

  wire [5:0] inky_tile_x, inky_tile_y;

  localparam [5:0] INKY_START_TILE_X = 6'd11;
  localparam [5:0] INKY_START_TILE_Y = 6'd19;
  localparam [3:0] INKY_START_OFFSET_X = 4'd8;
  localparam [3:0] INKY_START_OFFSET_Y = 4'd4;

  wire inky_at_start = (inky_tile_x == INKY_START_TILE_X) && (inky_tile_y == INKY_START_TILE_Y);

  wire [3:0] inky_offset_x = inky_at_start ? INKY_START_OFFSET_X : 4'd4;
  wire [3:0] inky_offset_y = inky_at_start ? INKY_START_OFFSET_Y : 4'd4;
  wire [9:0] inky_x = IMG_X0 + (inky_tile_x << 3) + inky_offset_x;
  wire [9:0] inky_y = IMG_Y0 + (inky_tile_y << 3) + inky_offset_y;

  wire [9:0] inky_tile_idx = ((inky_tile_y << 5) - (inky_tile_y << 2)) + inky_tile_x;
  
  wire inky_wall_up, inky_wall_down, inky_wall_left, inky_wall_right;
  wire inky_wall_up_rom, inky_wall_down_rom, inky_wall_left_rom, inky_wall_right_rom;
  
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

  inky UINKY (
    .clk(pclk),
    .reset(ghost_reset),
    .enable(ghost_enable),
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
    .dir()
  );

  wire [5:0] pinky_tile_x, pinky_tile_y;

  localparam [5:0] PINKY_START_TILE_X = 6'd13;
  localparam [5:0] PINKY_START_TILE_Y = 6'd19;
  localparam [3:0] PINKY_START_OFFSET_X = 4'd8;
  localparam [3:0] PINKY_START_OFFSET_Y = 4'd4;

  wire pinky_at_start = (pinky_tile_x == PINKY_START_TILE_X) && (pinky_tile_y == PINKY_START_TILE_Y);

  wire [3:0] pinky_offset_x = pinky_at_start ? PINKY_START_OFFSET_X : 4'd4;
  wire [3:0] pinky_offset_y = pinky_at_start ? PINKY_START_OFFSET_Y : 4'd4;
  wire [9:0] pinky_x = IMG_X0 + (pinky_tile_x << 3) + pinky_offset_x;
  wire [9:0] pinky_y = IMG_Y0 + (pinky_tile_y << 3) + pinky_offset_y;

  wire [9:0] pinky_tile_idx = ((pinky_tile_y << 5) - (pinky_tile_y << 2)) + pinky_tile_x;
  
  wire pinky_wall_up, pinky_wall_down, pinky_wall_left, pinky_wall_right;
  wire pinky_wall_up_rom, pinky_wall_down_rom, pinky_wall_left_rom, pinky_wall_right_rom;
  
  wire [9:0] pinky_tile_idx_up    = pinky_tile_idx - 10'd28;
  wire [9:0] pinky_tile_idx_down  = pinky_tile_idx + 10'd28;
  wire [9:0] pinky_tile_idx_left  = pinky_tile_idx - 10'd1;
  wire [9:0] pinky_tile_idx_right = pinky_tile_idx + 10'd1;

  level_rom ULEVEL_PINKY_UP (
    .tile_index(pinky_tile_idx_up),
    .is_wall(pinky_wall_up_rom)
  );
  
  level_rom ULEVEL_PINKY_DOWN (
    .tile_index(pinky_tile_idx_down),
    .is_wall(pinky_wall_down_rom)
  );
  
  level_rom ULEVEL_PINKY_LEFT (
    .tile_index(pinky_tile_idx_left),
    .is_wall(pinky_wall_left_rom)
  );
  
  level_rom ULEVEL_PINKY_RIGHT (
    .tile_index(pinky_tile_idx_right),
    .is_wall(pinky_wall_right_rom)
  );

  assign pinky_wall_up    = (pinky_tile_y == 0) ? 1'b1 : pinky_wall_up_rom;
  assign pinky_wall_down  = (pinky_tile_y == 35) ? 1'b1 : pinky_wall_down_rom;
  assign pinky_wall_left  = (pinky_tile_x == 0) ? 1'b1 : pinky_wall_left_rom;
  assign pinky_wall_right = (pinky_tile_x == 27) ? 1'b1 : pinky_wall_right_rom;

  // Convert pac_dir to Pinky's format: 00=Up, 01=Down, 10=Left, 11=Right
  // Pac-Man uses: 0=right, 1=left, 2=up, 3=down
  wire [1:0] pac_dir_pinky_format = (pac_dir == 2'd2) ? 2'b00 :  // up
                                    (pac_dir == 2'd3) ? 2'b01 :  // down
                                    (pac_dir == 2'd1) ? 2'b10 :  // left
                                    2'b11;                       // right

  pinky UPINKY (
    .clk(pclk),
    .reset(ghost_reset),
    .enable(ghost_enable),
    .pacmanX(pacman_tile_x),
    .pacmanY(pacman_tile_y),
    .pacmanDir(pac_dir_pinky_format),
    .isChase(isChase),
    .isScatter(isScatter),
    .wallUp(pinky_wall_up),
    .wallDown(pinky_wall_down),
    .wallLeft(pinky_wall_left),
    .wallRight(pinky_wall_right),
    .pinkyX(pinky_tile_x),
    .pinkyY(pinky_tile_y)
  );

  wire [5:0] clyde_tile_x, clyde_tile_y;

  localparam [5:0] CLYDE_START_TILE_X = 6'd15;
  localparam [5:0] CLYDE_START_TILE_Y = 6'd19;
  localparam [3:0] CLYDE_START_OFFSET_X = 4'd8;
  localparam [3:0] CLYDE_START_OFFSET_Y = 4'd4;

  wire clyde_at_start = (clyde_tile_x == CLYDE_START_TILE_X) && (clyde_tile_y == CLYDE_START_TILE_Y);

  wire [3:0] clyde_offset_x = clyde_at_start ? CLYDE_START_OFFSET_X : 4'd4;
  wire [3:0] clyde_offset_y = clyde_at_start ? CLYDE_START_OFFSET_Y : 4'd4;
  wire [9:0] clyde_x = IMG_X0 + (clyde_tile_x << 3) + clyde_offset_x;
  wire [9:0] clyde_y = IMG_Y0 + (clyde_tile_y << 3) + clyde_offset_y;

  wire [9:0] clyde_tile_idx = ((clyde_tile_y << 5) - (clyde_tile_y << 2)) + clyde_tile_x;
  
  wire clyde_wall_up, clyde_wall_down, clyde_wall_left, clyde_wall_right;
  wire clyde_wall_up_rom, clyde_wall_down_rom, clyde_wall_left_rom, clyde_wall_right_rom;
  
  wire [9:0] clyde_tile_idx_up    = clyde_tile_idx - 10'd28;
  wire [9:0] clyde_tile_idx_down  = clyde_tile_idx + 10'd28;
  wire [9:0] clyde_tile_idx_left  = clyde_tile_idx - 10'd1;
  wire [9:0] clyde_tile_idx_right = clyde_tile_idx + 10'd1;

  level_rom ULEVEL_CLYDE_UP (
    .tile_index(clyde_tile_idx_up),
    .is_wall(clyde_wall_up_rom)
  );
  
  level_rom ULEVEL_CLYDE_DOWN (
    .tile_index(clyde_tile_idx_down),
    .is_wall(clyde_wall_down_rom)
  );
  
  level_rom ULEVEL_CLYDE_LEFT (
    .tile_index(clyde_tile_idx_left),
    .is_wall(clyde_wall_left_rom)
  );
  
  level_rom ULEVEL_CLYDE_RIGHT (
    .tile_index(clyde_tile_idx_right),
    .is_wall(clyde_wall_right_rom)
  );

  assign clyde_wall_up    = (clyde_tile_y == 0) ? 1'b1 : clyde_wall_up_rom;
  assign clyde_wall_down  = (clyde_tile_y == 35) ? 1'b1 : clyde_wall_down_rom;
  assign clyde_wall_left  = (clyde_tile_x == 0) ? 1'b1 : clyde_wall_left_rom;
  assign clyde_wall_right = (clyde_tile_x == 27) ? 1'b1 : clyde_wall_right_rom;

  clyde UCLYDE (
    .clk(pclk),
    .reset(ghost_reset),
    .enable(ghost_enable),
    .pacmanX(pacman_tile_x),
    .pacmanY(pacman_tile_y),
    .isChase(isChase),
    .isScatter(isScatter),
    .wallUp(clyde_wall_up),
    .wallDown(clyde_wall_down),
    .wallLeft(clyde_wall_left),
    .wallRight(clyde_wall_right),
    .clydeX(clyde_tile_x),
    .clydeY(clyde_tile_y)
  );

  // Collision detection: Pac-Man vs Ghosts (tile-based collision)
  // Check if Pac-Man and any ghost are in the same tile
  wire pacman_blinky_collision = (pacman_tile_x == blinky_tile_x) && 
                                  (pacman_tile_y == blinky_tile_y);
  
  wire pacman_inky_collision = (pacman_tile_x == inky_tile_x) && 
                                (pacman_tile_y == inky_tile_y);
  
  wire pacman_pinky_collision = (pacman_tile_x == pinky_tile_x) && 
                                 (pacman_tile_y == pinky_tile_y);
  
  wire pacman_clyde_collision = (pacman_tile_x == clyde_tile_x) && 
                                 (pacman_tile_y == clyde_tile_y);
  
  wire any_collision = pacman_blinky_collision || pacman_inky_collision || 
                       pacman_pinky_collision || pacman_clyde_collision;
  
  // Game state machine: handles start button and collisions
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      game_state <= STATE_WAITING;
      start_button_prev <= 1'b1;
    end else begin
      start_button_prev <= start_button;
      
      case (game_state)
        STATE_WAITING: begin
          // Wait for start button press
          if (start_button_pressed) begin
            game_state <= STATE_PLAYING;
          end
        end
        
        STATE_PLAYING: begin
          // Check for collision on frame tick
          if (any_collision && frame_tick) begin
            game_state <= STATE_DEAD;
          end
        end
        
        STATE_DEAD: begin
          // Stay in DEAD state until reset (reset button returns to STATE_WAITING)
        end
      endcase
    end
  end

  // Pac-Man sprite rendering: 13x13 sprite centered on pac_x, pac_y
  // Calculate top-left corner of sprite bounding box
  wire [9:0] pac_left = pac_x - PAC_R;
  wire [9:0] pac_top  = pac_y - PAC_R;

  // Calculate sprite-local coordinates at current pixel
  wire [9:0] spr_x_full = h_d - pac_left;
  wire [9:0] spr_y_full = v_d - pac_top;

  // Check if current pixel is inside sprite bounding box
  wire       in_pac_box = (spr_x_full < SPR_W) && (spr_y_full < SPR_H);

  // Clamp sprite coordinates to valid range (0-12) to prevent out-of-bounds ROM access
  wire [3:0] spr_x_raw = (spr_x_full >= SPR_W) ? 4'd12 : spr_x_full[3:0];
  wire [3:0] spr_y_raw = (spr_y_full >= SPR_H) ? 4'd12 : spr_y_full[3:0];

  // Transform sprite coordinates based on direction
  // Sprite ROM stores Pac-Man facing right (mouth open to the right)
  // Rotations: right=0°, left=180°, up=90°CW, down=90°CCW
  wire [3:0] spr_x, spr_y;
  
  assign spr_x = (pac_dir == 2'd0) ? spr_x_raw :                    // right: no change
                 (pac_dir == 2'd1) ? (4'd12 - spr_x_raw) :          // left: 180° (x' = 12-x)
                 (pac_dir == 2'd2) ? (4'd12 - spr_y_raw) :          // up: 90°CW (x' = 12-y)
                 spr_y_raw;                                         // down: 90°CCW (x' = y)
                 
  assign spr_y = (pac_dir == 2'd0) ? spr_y_raw :                    // right: no change
                 (pac_dir == 2'd1) ? (4'd12 - spr_y_raw) :          // left: 180° (y' = 12-y)
                 (pac_dir == 2'd2) ? spr_x_raw :                    // up: 90°CW (y' = x)
                 (4'd12 - spr_x_raw);                               // down: 90°CCW (y' = 12-x)

  // Calculate ROM address: y*13 + x = y*8 + y*4 + y + x
  wire [7:0] pac_addr = ((spr_y << 3) + (spr_y << 2) + spr_y + spr_x);

  wire [3:0] pac_pix_data;
  pacman_rom_16x16_4bpp UPAC (
    .addr(pac_addr),
    .data(pac_pix_data)
  );

  // Pac-Man pixel is "active" when inside box and sprite index != 0 (0 = transparent)
  // Flash Pac-Man 3 times when dead, then hide completely
  wire pac_pix = in_pac_box && (pac_pix_data != 4'h0) && 
                 (!game_dead || (game_dead && !death_animation_done && pacman_flash_visible));

  wire [9:0] blinky_left = blinky_x - GHOST_R;
  wire [9:0] blinky_top  = blinky_y - GHOST_R;

  wire [9:0] blinky_spr_x_full = h_d - blinky_left;
  wire [9:0] blinky_spr_y_full = v_d - blinky_top;

  wire       in_blinky_box = (blinky_spr_x_full < GHOST_W) && (blinky_spr_y_full < GHOST_H);

  wire [3:0] blinky_spr_x = blinky_spr_x_full[3:0];
  wire [3:0] blinky_spr_y = blinky_spr_y_full[3:0];

  wire [7:0] blinky_addr = (blinky_spr_y << 4) | blinky_spr_x;

  wire [3:0] blinky_pix_data;
  blinky_rom_16x16_4bpp UBLINKY_ROM (
    .addr(blinky_addr),
    .data(blinky_pix_data)
  );

  // Blinky pixel: active when inside sprite box and not transparent
  wire blinky_pix = in_blinky_box && (blinky_pix_data != 4'h0);

  // Inky sprite rendering: 16x16 sprite centered on inky_x, inky_y
  wire [9:0] inky_left = inky_x - GHOST_R;
  wire [9:0] inky_top  = inky_y - GHOST_R;

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

  wire inky_pix = in_inky_box && (inky_pix_data != 4'h0);

  // Pinky sprite rendering: 16x16 sprite centered on pinky_x, pinky_y
  wire [9:0] pinky_left = pinky_x - GHOST_R;
  wire [9:0] pinky_top  = pinky_y - GHOST_R;

  wire [9:0] pinky_spr_x_full = h_d - pinky_left;
  wire [9:0] pinky_spr_y_full = v_d - pinky_top;

  wire       in_pinky_box = (pinky_spr_x_full < GHOST_W) && (pinky_spr_y_full < GHOST_H);

  wire [3:0] pinky_spr_x = pinky_spr_x_full[3:0];  // 0..15
  wire [3:0] pinky_spr_y = pinky_spr_y_full[3:0];  // 0..15

  wire [7:0] pinky_addr = (pinky_spr_y << 4) | pinky_spr_x;  // y*16 + x

  wire [3:0] pinky_pix_data;
  pinky_rom_16x16_4bpp UPINKY_ROM (
    .addr(pinky_addr),
    .data(pinky_pix_data)
  );

  wire pinky_pix = in_pinky_box && (pinky_pix_data != 4'h0);

  // Clyde sprite rendering: 16x16 sprite centered on clyde_x, clyde_y
  wire [9:0] clyde_left = clyde_x - GHOST_R;
  wire [9:0] clyde_top  = clyde_y - GHOST_R;

  wire [9:0] clyde_spr_x_full = h_d - clyde_left;
  wire [9:0] clyde_spr_y_full = v_d - clyde_top;

  wire       in_clyde_box = (clyde_spr_x_full < GHOST_W) && (clyde_spr_y_full < GHOST_H);

  wire [3:0] clyde_spr_x = clyde_spr_x_full[3:0];  // 0..15
  wire [3:0] clyde_spr_y = clyde_spr_y_full[3:0];  // 0..15

  wire [7:0] clyde_addr = (clyde_spr_y << 4) | clyde_spr_x;  // y*16 + x

  wire [3:0] clyde_pix_data;
  clyde_rom_16x16_4bpp UCLYDE_ROM (
    .addr(clyde_addr),
    .data(clyde_pix_data)
  );

  wire clyde_pix = in_clyde_box && (clyde_pix_data != 4'h0);

  // Score display: 5 digits, 8x8 pixels each
  localparam SCORE_X = 10'd300;
  localparam SCORE_Y = 10'd10;
  localparam DIGIT_W = 8;
  localparam DIGIT_H = 8;
  localparam NUM_DIGITS = 5;
  
  wire in_score_area = (h_d >= SCORE_X) && (h_d < SCORE_X + (NUM_DIGITS * DIGIT_W)) &&
                       (v_d >= SCORE_Y) && (v_d < SCORE_Y + DIGIT_H);
  
  // Binary to BCD conversion: double-dabble algorithm
  // Converts 16-bit binary to 4-digit BCD (thousands, hundreds, tens, units)
  function [15:0] bin_to_bcd;
    input [15:0] bin;
    integer i;
    reg [19:0] bcd;
    begin
      bcd = 0;
      // Process each bit from MSB to LSB
      for (i = 15; i >= 0; i = i - 1) begin
        // Add 3 to any BCD digit >= 5 before shifting
        if (bcd[3:0] >= 5) bcd[3:0] = bcd[3:0] + 3;
        if (bcd[7:4] >= 5) bcd[7:4] = bcd[7:4] + 3;
        if (bcd[11:8] >= 5) bcd[11:8] = bcd[11:8] + 3;
        if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
        // Shift left and insert next binary bit
        bcd = {bcd[18:0], bin[i]};
      end
      bin_to_bcd = bcd[15:0];
    end
  endfunction
  
  // Convert binary score to BCD for display
  wire [15:0] score_bcd = bin_to_bcd(score);
  wire [3:0] score_units = score_bcd[3:0];
  wire [3:0] score_tens = score_bcd[7:4];
  wire [3:0] score_hundreds = score_bcd[11:8];
  wire [3:0] score_thousands = score_bcd[15:12];
  
  // Calculate which digit we're rendering (0-4, left to right)
  wire [2:0] digit_index = ((h_d - SCORE_X) >> 3);  // Divide by 8 (DIGIT_W)
  wire [3:0] current_digit = (digit_index == 3'd0) ? score_thousands :
                            (digit_index == 3'd1) ? score_hundreds :
                            (digit_index == 3'd2) ? score_tens :
                            (digit_index == 3'd3) ? score_units :
                            4'd0;  // 5th digit always 0
  
  // Pixel position within digit (clamp to valid range)
  wire [2:0] digit_x = (h_d - SCORE_X) - ((digit_index << 3));  // Modulo 8, range 0-7
  wire [2:0] digit_y = (v_d - SCORE_Y);  // Range 0-7, already clamped by in_score_area check
  
  // 8x8 digit font: returns 8-bit row pattern for given digit and row
  // Each bit represents one pixel (bit 7 = leftmost pixel)
  function [7:0] digit_font;
    input [3:0] digit;
    input [2:0] row;
    begin
      case (digit)
        4'd0: digit_font = (row == 0) ? 8'b01111110 :
                          (row == 1) ? 8'b11111111 :
                          (row == 2) ? 8'b11000011 :
                          (row == 3) ? 8'b11000011 :
                          (row == 4) ? 8'b11000011 :
                          (row == 5) ? 8'b11000011 :
                          (row == 6) ? 8'b11111111 :
                          8'b01111110;
        4'd1: digit_font = (row == 0) ? 8'b00011000 :
                          (row == 1) ? 8'b00111000 :
                          (row == 2) ? 8'b00011000 :
                          (row == 3) ? 8'b00011000 :
                          (row == 4) ? 8'b00011000 :
                          (row == 5) ? 8'b00011000 :
                          (row == 6) ? 8'b00011000 :
                          8'b01111110;
        4'd2: digit_font = (row == 0) ? 8'b01111110 :
                          (row == 1) ? 8'b11111111 :
                          (row == 2) ? 8'b00000111 :
                          (row == 3) ? 8'b01111110 :
                          (row == 4) ? 8'b11110000 :
                          (row == 5) ? 8'b11000000 :
                          (row == 6) ? 8'b11111111 :
                          8'b11111111;
        4'd3: digit_font = (row == 0) ? 8'b11111110 :
                          (row == 1) ? 8'b11111111 :
                          (row == 2) ? 8'b00000111 :
                          (row == 3) ? 8'b00111110 :
                          (row == 4) ? 8'b00000111 :
                          (row == 5) ? 8'b11000111 :
                          (row == 6) ? 8'b11111111 :
                          8'b01111110;
        4'd4: digit_font = (row == 0) ? 8'b11000110 :
                          (row == 1) ? 8'b11000110 :
                          (row == 2) ? 8'b11000110 :
                          (row == 3) ? 8'b11111111 :
                          (row == 4) ? 8'b11111111 :
                          (row == 5) ? 8'b00000110 :
                          (row == 6) ? 8'b00000110 :
                          8'b00000110;
        4'd5: digit_font = (row == 0) ? 8'b11111111 :
                          (row == 1) ? 8'b11111111 :
                          (row == 2) ? 8'b11000000 :
                          (row == 3) ? 8'b11111110 :
                          (row == 4) ? 8'b01111111 :
                          (row == 5) ? 8'b00000111 :
                          (row == 6) ? 8'b11111111 :
                          8'b11111110;
        4'd6: digit_font = (row == 0) ? 8'b01111110 :
                          (row == 1) ? 8'b11111111 :
                          (row == 2) ? 8'b11000000 :
                          (row == 3) ? 8'b11111110 :
                          (row == 4) ? 8'b11111111 :
                          (row == 5) ? 8'b11000011 :
                          (row == 6) ? 8'b11111111 :
                          8'b01111110;
        4'd7: digit_font = (row == 0) ? 8'b11111111 :
                          (row == 1) ? 8'b11111111 :
                          (row == 2) ? 8'b00000110 :
                          (row == 3) ? 8'b00001100 :
                          (row == 4) ? 8'b00011000 :
                          (row == 5) ? 8'b00110000 :
                          (row == 6) ? 8'b01100000 :
                          8'b11000000;
        4'd8: digit_font = (row == 0) ? 8'b01111110 :
                          (row == 1) ? 8'b11111111 :
                          (row == 2) ? 8'b11000011 :
                          (row == 3) ? 8'b01111110 :
                          (row == 4) ? 8'b11000011 :
                          (row == 5) ? 8'b11000011 :
                          (row == 6) ? 8'b11111111 :
                          8'b01111110;
        4'd9: digit_font = (row == 0) ? 8'b01111110 :
                          (row == 1) ? 8'b11111111 :
                          (row == 2) ? 8'b11000011 :
                          (row == 3) ? 8'b11111111 :
                          (row == 4) ? 8'b01111111 :
                          (row == 5) ? 8'b00000111 :
                          (row == 6) ? 8'b11111111 :
                          8'b01111110;
        default: digit_font = 8'b00000000;
      endcase
    end
  endfunction
  
  // Get pixel from font: bit 7 is leftmost pixel
  wire [7:0] digit_font_row = digit_font(current_digit, digit_y);
  wire [2:0] digit_bit_index = 7 - digit_x;  // Reverse bit order (leftmost = bit 7)
  
  // Score pixel: active if in score area and font bit is set
  wire score_pixel = in_score_area && (digit_x < 8) && (digit_y < 8) && (digit_bit_index < 8) && digit_font_row[digit_bit_index];

  // Unified palette: maps 4-bit color indices to RGB values
  function [11:0] palette_lookup;
    input [3:0] color_index;
    begin
      case (color_index)
        4'h0: palette_lookup = {4'h0, 4'h0, 4'h0};  // Black
        4'h1: palette_lookup = {4'h8, 4'h0, 4'h0};  // Dark Red
        4'h2: palette_lookup = {4'h0, 4'h8, 4'h0};  // Dark Green
        4'h3: palette_lookup = {4'hF, 4'hA, 4'h0};  // Orange (Clyde)
        4'h4: palette_lookup = {4'h0, 4'h0, 4'h8};  // Dark Blue
        4'h5: palette_lookup = {4'h8, 4'h0, 4'h8};  // Dark Magenta
        4'h6: palette_lookup = {4'h9, 4'h4, 4'h1};  // Brown (dots)
        4'h7: palette_lookup = {4'hF, 4'h0, 4'h0};  // Red (Blinky)
        4'h8: palette_lookup = {4'h8, 4'h8, 4'h8};  // Gray
        4'h9: palette_lookup = {4'hF, 4'h8, 4'hF};  // Pink (Pinky)
        4'hA: palette_lookup = {4'h0, 4'hF, 4'h0};  // Green
        4'hB: palette_lookup = {4'hF, 4'hF, 4'h0};  // Yellow (Pac-Man)
        4'hC: palette_lookup = {4'h0, 4'h0, 4'hF};  // Blue (walls)
        4'hD: palette_lookup = {4'hF, 4'h0, 4'hF};  // Magenta
        4'hE: palette_lookup = {4'h0, 4'hF, 4'hF};  // Cyan (Inky)
        4'hF: palette_lookup = {4'hF, 4'hF, 4'hF};  // White
        default: palette_lookup = {4'h0, 4'h0, 4'h0};
      endcase
    end
  endfunction

  // Pixel priority: Score > Pac-Man > Ghosts > Dots > Maze
  wire [3:0] final_color_index;
  wire [11:0] palette_rgb;
  
  assign final_color_index = score_pixel ? 4'hF :
                            pac_pix ? pac_pix_data :
                            blinky_pix ? blinky_pix_data :
                            inky_pix ? inky_pix_data :
                            pinky_pix ? pinky_pix_data :
                            clyde_pix ? clyde_pix_data :
                            dot_pixel ? 4'h6 :
                            in_img_area ? pix_data :
                            4'h0;
  
  assign palette_rgb = palette_lookup(final_color_index);

  // RGB output: convert palette RGB to VGA output
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      r <= 4'h0;
      g <= 4'h0;
      b <= 4'h0;
    end else begin
      if (h_vis && v_vis) begin
        // Visible area: output RGB from palette
        r <= palette_rgb[11:8];
        g <= palette_rgb[7:4];
        b <= palette_rgb[3:0];
      end else begin
        // Blanking area: output black
        r <= 4'h0; g <= 4'h0; b <= 4'h0;
      end
    end
  end
endmodule

// Maze background ROM: 224x288 pixels, 4-bit color indices
module image_rom_224x288_4bpp (
    input  wire        clk,
    input  wire [15:0] addr,
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

// Pac-Man sprite ROM: 13x13 pixels
module pacman_rom_16x16_4bpp (
    input  wire [7:0] addr,
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

// Blinky sprite ROM: 16x16 pixels
module blinky_rom_16x16_4bpp (
    input  wire [7:0] addr,
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

// Inky sprite ROM: 16x16 pixels
module inky_rom_16x16_4bpp (
    input  wire [7:0] addr,
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

// Pinky sprite ROM: 16x16 pixels
module pinky_rom_16x16_4bpp (
    input  wire [7:0] addr,
    output reg  [3:0] data
);
    reg [3:0] mem [0:256-1];

    initial begin
        $readmemh("Pinky.hex", mem);
    end

    always @* begin
        data = mem[addr];
    end
endmodule

// Clyde sprite ROM: 16x16 pixels
module clyde_rom_16x16_4bpp (
    input  wire [7:0] addr,
    output reg  [3:0] data
);
    reg [3:0] mem [0:256-1];

    initial begin
        $readmemh("Clyde.hex", mem);
    end

    always @* begin
        data = mem[addr];
    end
endmodule

// Level ROM: wall map for 28x36 tile grid
module level_rom (
    input  wire [9:0] tile_index,
    output wire       is_wall
);
    reg bits [0:1007];

    integer i;
    initial begin
        for (i = 0; i < 1008; i = i + 1)
            bits[i] = 1'b0;
        $readmemb("level_map.bin", bits);
    end

    assign is_wall = bits[tile_index];
endmodule

// Dots RAM: dual-port memory for dot positions (can be cleared when eaten)
module dots_ram (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  read_tile_index_1,
    input  wire [9:0]  read_tile_index_2,
    input  wire [9:0]  write_tile_index,
    input  wire        write_enable,
    input  wire        write_data,
    output reg         has_dot_1,
    output reg         has_dot_2
);
    reg bits [0:1007];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize from file on reset
            for (i = 0; i < 1008; i = i + 1)
                bits[i] = 1'b0;
            $readmemb("dots_map.bin", bits);
        end else begin
            // Write operation: clear dot when eaten
            if (write_enable) begin
                bits[write_tile_index] <= write_data;
            end
        end
    end
    
    // Dual-port read: handle read-during-write for immediate updates
    always @* begin
        // Port 1: display read
        if (write_enable && (read_tile_index_1 == write_tile_index)) begin
            has_dot_1 = write_data;
        end else begin
            has_dot_1 = bits[read_tile_index_1];
        end
        
        // Port 2: Pac-Man detection read
        if (write_enable && (read_tile_index_2 == write_tile_index)) begin
            has_dot_2 = write_data;
        end else begin
            has_dot_2 = bits[read_tile_index_2];
        end
    end
endmodule