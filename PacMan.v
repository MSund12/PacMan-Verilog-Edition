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
    .areset(!rst_n),      // Connect reset (active-high)
    .inclk0(CLOCK_50),
    .c0    (pclk),
    .locked(pll_locked)
  );

  // Switch-based control (direct connection to switches)
  wire move_up_50mhz = SW[3];
  wire move_down_50mhz = SW[2];
  wire move_left_50mhz = SW[1];
  wire move_right_50mhz = SW[0];

  // Clock domain crossing: synchronize movement signals and start game from CLOCK_50 to pclk
  // Using 2-stage synchronizer for safe crossing
  wire rst_n_pll_sync = rst_n & pll_locked;
  reg [3:0] move_sync_stage1, move_sync_stage2;
  wire move_up_sync, move_down_sync, move_left_sync, move_right_sync;
  
  always @(posedge pclk or negedge rst_n_pll_sync) begin
    if (!rst_n_pll_sync) begin
      move_sync_stage1 <= 4'b0000;
      move_sync_stage2 <= 4'b0000;
    end else begin
      move_sync_stage1 <= {move_up_50mhz, move_down_50mhz, move_left_50mhz, move_right_50mhz};
      move_sync_stage2 <= move_sync_stage1;
    end
  end
  
  assign move_up_sync = move_sync_stage2[3];
  assign move_down_sync = move_sync_stage2[2];
  assign move_left_sync = move_sync_stage2[1];
  assign move_right_sync = move_sync_stage2[0];

  // Synchronize start_game signal (SW[9]) from CLOCK_50 to pclk domain
  reg start_game_sync_stage1, start_game_sync_stage2;
  wire start_game_sync;
  
  always @(posedge pclk or negedge rst_n_pll_sync) begin
    if (!rst_n_pll_sync) begin
      start_game_sync_stage1 <= 1'b0;
      start_game_sync_stage2 <= 1'b0;
    end else begin
      start_game_sync_stage1 <= SW[9];
      start_game_sync_stage2 <= start_game_sync_stage1;
    end
  end
  
  assign start_game_sync = start_game_sync_stage2;

  // Generate pulse for debug LED (one-cycle pulse on start button press)
  reg start_game_sync_prev;
  wire start_game_pulse;
  always @(posedge pclk or negedge rst_n_pll_sync) begin
    if (!rst_n_pll_sync) begin
      start_game_sync_prev <= 1'b0;
    end else begin
      start_game_sync_prev <= start_game_sync;
    end
  end
  assign start_game_pulse = start_game_sync && !start_game_sync_prev;

  wire [9:0] h;
  wire [9:0] v;
  wire       hs, vs;
  wire [3:0] r,g,b;

  vga_core_640x480 UCORE(
    .pclk(pclk),
    .rst_n(rst_n & pll_locked),

    // Movement controls from UART or switches (synchronized to pclk domain)
    .move_up   (move_up_sync),
    .move_down (move_down_sync),
    .move_left (move_left_sync),
    .move_right(move_right_sync),
    .start_game(start_game_sync),

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
  assign LEDR[0] = 1'b0;  // VGA timing signals disabled
  assign LEDR[1] = 1'b0;
  assign LEDR[2] = start_game_sync;  // Show synchronized start button status
  assign LEDR[3] = 1'b0;
  assign LEDR[4] = 1'b0;
  assign LEDR[5] = 1'b0;
  assign LEDR[6] = 1'b0;
  assign LEDR[7] = SW[9];  // Direct SW[9] status for debugging
  assign LEDR[8] = start_game_pulse;  // Show start pulse
  assign LEDR[9] = 1'b0;

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
  input  wire        start_game,

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
  localparam IMG_X0 = (H_VIS-IMG_W)/2;  // (640-224)/2 = 208
  localparam IMG_Y0 = (V_VIS-IMG_H)/2;  // (480-288)/2 = 96

  // Tile grid: 28 x 36 tiles of 8x8 pixels
  localparam TILE_W   = 8;
  localparam TILE_H   = 8;
  localparam TILES_X  = IMG_W / TILE_W;   // 224/8 = 28
  localparam TILES_Y  = IMG_H / TILE_H;   // 288/8 = 36

  // Pac-Man sprite parameters
  localparam PAC_R = 8;        // 16x16 sprite radius
  localparam SPR_W = 16;
  localparam SPR_H = 16;

  // -------------------------
  // Helper Functions
  // -------------------------
  // Calculate y * 224 for image ROM addressing (224 = 256 - 32 = 2^8 - 2^5)
  function [15:0] calc_img_addr_y;
    input [9:0] y;
    calc_img_addr_y = (y << 8) - (y << 5);  // y * 224
  endfunction

  // Calculate y * 28 for tile index calculation (28 = 32 - 4 = 2^5 - 2^2)
  function [9:0] calc_tile_index_y;
    input [5:0] y;
    calc_tile_index_y = (y << 5) - (y << 2);  // y * 28
  endfunction

  // Check if tile coordinates match a power pellet location
  // Power pellets are at: (1,6), (26,6), (1,26), (26,26)
  function is_power_pellet_tile;
    input [4:0] tile_x;
    input [5:0] tile_y;
    is_power_pellet_tile = ((tile_x == 5'd1 || tile_x == 5'd26) && 
                            (tile_y == 6'd6 || tile_y == 6'd26));
  endfunction

  // Sprite rendering helper functions
  // Calculate sprite box bounds (top-left corner)
  function [9:0] calc_sprite_left;
    input [9:0] sprite_x;
    input [9:0] sprite_radius;
    calc_sprite_left = sprite_x - sprite_radius;
  endfunction

  function [9:0] calc_sprite_top;
    input [9:0] sprite_y;
    input [9:0] sprite_radius;
    calc_sprite_top = sprite_y - sprite_radius;
  endfunction

  // Calculate sprite-local coordinates and check if in bounds
  function [3:0] calc_sprite_x;
    input [9:0] h_coord;
    input [9:0] sprite_left;
    // Return lower 4 bits of the difference (Verilog automatically truncates)
    calc_sprite_x = h_coord - sprite_left;
  endfunction

  function [3:0] calc_sprite_y;
    input [9:0] v_coord;
    input [9:0] sprite_top;
    // Return lower 4 bits of the difference (Verilog automatically truncates)
    calc_sprite_y = v_coord - sprite_top;
  endfunction

  // Check if pixel is within sprite box
  function is_in_sprite_box;
    input [9:0] h_coord, v_coord;
    input [9:0] sprite_left, sprite_top;
    input [9:0] sprite_w, sprite_h;
    is_in_sprite_box = (h_coord >= sprite_left) && (v_coord >= sprite_top) &&
                       ((h_coord - sprite_left) < sprite_w) &&
                       ((v_coord - sprite_top) < sprite_h);
  endfunction

  // Calculate sprite ROM address from sprite coordinates
  function [7:0] calc_sprite_addr;
    input [3:0] spr_x, spr_y;
    calc_sprite_addr = (spr_y << 4) | spr_x;  // y*16 + x
  endfunction

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

  wire [15:0] addr_y   = calc_img_addr_y(img_y_addr); // y*224
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

  // Maze ROM: 4-bit pixels, 1-cycle latency
  wire [3:0] pix_data;
  image_rom_224x288_4bpp UIMG (
    .clk (pclk),
    .addr(img_addr),
    .data(pix_data)
  );
  
  // Tile coordinates for current pixel (for dot checking during rendering)
  wire [9:0] img_x_addr_d = h_d - IMG_X0;  // 0..223
  wire [9:0] img_y_addr_d = v_d - IMG_Y0;  // 0..287
  wire [4:0] render_tile_x = img_x_addr_d[9:3];  // 0..27
  wire [5:0] render_tile_y = img_y_addr_d[9:3];  // 0..35
  wire [9:0] render_tile_index = calc_tile_index_y(render_tile_y) + render_tile_x;
  
  // Check if tile has a wall (for dot rendering)
  wire render_tile_wall;
  level_rom ULEVEL_RENDER (
    .tile_index(render_tile_index),
    .is_wall(render_tile_wall)
  );
  
  // Dot map provides render_has_dot output for rendering
  wire render_tile_has_dot;
  
  // Power pellet rendering wire (will reference pellets_collected declared later)
  wire is_render_pellet_tile = is_power_pellet_tile(render_tile_x, render_tile_y);

    // -------------------------
  // Pac-Man position and tile-based collision
  // -------------------------
  // Pac-Man collision hitbox (14 wide × 15 tall)
  localparam HIT_W  = 14;
  localparam HIT_H  = 15;

  // 14 wide → ±7 pixels from center
  localparam HIT_RX = 7;

  // 15 tall → -7 (top) to +8 (bottom)
  localparam HIT_RY_UP   = 7;
  localparam HIT_RY_DOWN = 8;


  reg [9:0] pac_x, pac_y;     // center position (screen coords)
  reg [1:0] pac_dir;          // 0=right,1=left,2=up,3=down

  // fractional speed accumulator for 125/99 pixels per frame
  // (≈ 75.7576 px/s at 60 Hz)
  reg [7:0] speed_acc;        // remainder modulo 99
  
  // Direction change blocking: prevent movement into walls after direction changes
  // Block movement for 2 cycles after direction change to allow wall detection pipeline to catch up
  reg [1:0] direction_change_block;
  reg [1:0] pac_dir_prev;

  // -------------------------
  // Game State Management
  // -------------------------
  // Game states
  localparam [2:0] STATE_ATTRACT = 3'd0;
  localparam [2:0] STATE_READY = 3'd1;
  localparam [2:0] STATE_PLAYING = 3'd2;
  localparam [2:0] STATE_DYING = 3'd3;
  localparam [2:0] STATE_GAME_OVER = 3'd4;
  localparam [2:0] STATE_LEVEL_COMPLETE = 3'd5;
  
  // Game state variables
  reg [2:0] game_state;
  reg [4:0] current_level;
  reg [15:0] dying_timer;
  
  // Start game trigger: edge detect start_game input and hold until consumed
  reg start_game_trigger;
  reg start_game_prev;
  
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      game_state <= STATE_ATTRACT;
      current_level <= 5'd1;
      dying_timer <= 16'd0;
      start_game_trigger <= 1'b0;
      start_game_prev <= 1'b0;
    end else begin
      start_game_prev <= start_game;
      
      // Detect rising edge of start_game and set trigger
      if (start_game && !start_game_prev) begin
        start_game_trigger <= 1'b1;
      end
      
      case (game_state)
        STATE_ATTRACT: begin
          // Wait for start button (level signal that stays high until consumed)
          if (start_game_trigger) begin
            game_state <= STATE_READY;
            start_game_trigger <= 1'b0;  // Clear trigger when consumed
          end else begin
            game_state <= STATE_ATTRACT;  // Stay in ATTRACT
          end
        end
        
        STATE_READY: begin
          // Brief ready state, then start playing
          game_state <= STATE_PLAYING;
        end
        
        STATE_PLAYING: begin
          // Check for level completion (highest priority)
          if (level_complete) begin
            game_state <= STATE_LEVEL_COMPLETE;
          end else if (lose_life) begin
            // Check for life loss
            game_state <= STATE_DYING;
            dying_timer <= 16'd0;
          end else if (game_over) begin
            // Check for game over
            game_state <= STATE_GAME_OVER;
          end else begin
            game_state <= STATE_PLAYING;  // Stay in PLAYING
          end
        end
        
        STATE_DYING: begin
          // Dying animation (60 frames = 1 second at 60 FPS)
          if (dying_timer < 16'd60) begin
            dying_timer <= dying_timer + 16'd1;
            game_state <= STATE_DYING;  // Stay in DYING
          end else begin
            // Check if game over
            if (game_over) begin
              game_state <= STATE_GAME_OVER;
            end else begin
              // Reset positions and continue
              game_state <= STATE_READY;
              dying_timer <= 16'd0;
            end
          end
        end
        
        STATE_LEVEL_COMPLETE: begin
          // Level complete - advance to next level
          current_level <= current_level + 5'd1;
          game_state <= STATE_READY;
          // Reset will be handled by level_reset signal
        end
        
        STATE_GAME_OVER: begin
          // Wait for restart (start_game trigger resets everything)
          if (start_game_trigger) begin
            game_state <= STATE_ATTRACT;
            current_level <= 5'd1;
            start_game_trigger <= 1'b0;  // Clear trigger when consumed
          end else begin
            game_state <= STATE_GAME_OVER;  // Stay in GAME_OVER
          end
        end
        
        default: begin
          game_state <= STATE_ATTRACT;
        end
      endcase
    end
  end
  
  // Update game_started flag based on state (for compatibility with existing code)
  assign game_started = (game_state == STATE_PLAYING);

  // center relative to maze origin (unsigned; only used when inside maze)
  wire [9:0] pac_local_x = pac_x - IMG_X0;
  wire [9:0] pac_local_y = pac_y - IMG_Y0;

  wire pac_in_maze =
      (pac_x >= IMG_X0) && (pac_x < IMG_X0 + IMG_W) &&
      (pac_y >= IMG_Y0) && (pac_y < IMG_Y0 + IMG_H);

  // Calculate step_px for this frame (combinational, based on current speed_acc)
  // Scale increment by pacman_speed percentage: scaled_increment = (125 * pacman_speed) / 100
  // Accumulator can overflow at most twice per frame (when scaled_increment >= 99)
  wire [15:0] scaled_increment = (125 * pacman_speed) / 100;  // 125 * percentage / 100
  wire [7:0] tmp_acc_calc = speed_acc + scaled_increment[7:0];  // Use lower 8 bits (scaled_increment should fit)
  
  // Handle first overflow: subtract 99 if >= 99, count 1 step
  wire [7:0] tmp_acc_after_first = (tmp_acc_calc >= 8'd99) ? (tmp_acc_calc - 8'd99) : tmp_acc_calc;
  wire [1:0] step_px_calc = (tmp_acc_calc >= 8'd99) ? 2'd1 : 2'd0;
  
  // Handle second overflow: subtract 99 again if still >= 99, count another step
  wire [7:0] tmp_acc_after_second = (tmp_acc_after_first >= 8'd99) ? (tmp_acc_after_first - 8'd99) : tmp_acc_after_first;
  wire [1:0] step_px_wire = step_px_calc + ((tmp_acc_after_first >= 8'd99) ? 2'd1 : 2'd0);

  // -------------------------
  // Pixel-level wall detection
  // Check multiple points along the hitbox edge in movement direction
  // Wall pixels have value 4'hC (12 decimal)
  // Check 1 pixel ahead of the current edge to prevent entering walls
  // -------------------------
  // Calculate check points along the hitbox edge, checking 1 pixel ahead in movement direction
  // For horizontal movement: check top, middle, bottom of hitbox edge
  // For vertical movement: check left, middle, right of hitbox edge
  
  // Check point coordinates (3 points per direction)
  wire [9:0] check_x_1, check_y_1;  // Point 1 (top/left)
  wire [9:0] check_x_2, check_y_2;  // Point 2 (middle)
  wire [9:0] check_x_3, check_y_3;  // Point 3 (bottom/right)
  
  // Right movement: check right edge + step_px_wire + 1 pixel ahead at top, middle, bottom
  wire [9:0] right_edge_x = pac_local_x + HIT_RX + step_px_wire + 10'd1;  // step_px_wire + 1 pixel ahead
  wire [9:0] right_check_y_top = (pac_local_y >= HIT_RY_UP) ? (pac_local_y - HIT_RY_UP) : 10'd0;
  wire [9:0] right_check_y_mid = pac_local_y;
  wire [9:0] right_check_y_bot = pac_local_y + HIT_RY_DOWN;
  
  // Left movement: check left edge - step_px_wire - 1 pixel ahead at top, middle, bottom
  wire [9:0] left_edge_x = (pac_local_x >= HIT_RX + step_px_wire + 10'd1) ? (pac_local_x - HIT_RX - step_px_wire - 10'd1) : 10'd0;
  
  // Up movement: check top edge - step_px_wire - 1 pixel ahead at left, middle, right
  wire [9:0] top_edge_y = (pac_local_y >= HIT_RY_UP + step_px_wire + 10'd1) ? (pac_local_y - HIT_RY_UP - step_px_wire - 10'd1) : 10'd0;
  wire [9:0] top_check_x_left = (pac_local_x >= HIT_RX) ? (pac_local_x - HIT_RX) : 10'd0;
  wire [9:0] top_check_x_mid = pac_local_x;
  wire [9:0] top_check_x_right = pac_local_x + HIT_RX;
  
  // Down movement: check bottom edge + step_px_wire + 1 pixel ahead at left, middle, right
  wire [9:0] down_edge_y = pac_local_y + HIT_RY_DOWN + step_px_wire + 10'd1;
  
  // Select check points based on movement direction
  assign check_x_1 = (pac_dir == 2'd0) ? right_edge_x :           // right: right edge
                     (pac_dir == 2'd1) ? left_edge_x :            // left: left edge
                     (pac_dir == 2'd2) ? top_check_x_left :       // up: left of top edge
                     top_check_x_left;                            // down: left of bottom edge
  assign check_y_1 = (pac_dir == 2'd0) ? right_check_y_top :     // right: top of right edge
                     (pac_dir == 2'd1) ? right_check_y_top :      // left: top of left edge
                     (pac_dir == 2'd2) ? top_edge_y :             // up: top edge
                     down_edge_y;                                 // down: bottom edge
  
  assign check_x_2 = (pac_dir == 2'd0) ? right_edge_x :          // right: right edge
                     (pac_dir == 2'd1) ? left_edge_x :            // left: left edge
                     (pac_dir == 2'd2) ? top_check_x_mid :        // up: middle of top edge
                     top_check_x_mid;                             // down: middle of bottom edge
  assign check_y_2 = (pac_dir == 2'd0) ? right_check_y_mid :     // right: middle of right edge
                     (pac_dir == 2'd1) ? right_check_y_mid :      // left: middle of left edge
                     (pac_dir == 2'd2) ? top_edge_y :             // up: top edge
                     down_edge_y;                                 // down: bottom edge
  
  assign check_x_3 = (pac_dir == 2'd0) ? right_edge_x :          // right: right edge
                     (pac_dir == 2'd1) ? left_edge_x :            // left: left edge
                     (pac_dir == 2'd2) ? top_check_x_right :      // up: right of top edge
                     top_check_x_right;                           // down: right of bottom edge
  assign check_y_3 = (pac_dir == 2'd0) ? right_check_y_bot :     // right: bottom of right edge
                     (pac_dir == 2'd1) ? right_check_y_bot :      // left: bottom of left edge
                     (pac_dir == 2'd2) ? top_edge_y :             // up: top edge
                     down_edge_y;                                 // down: bottom edge
  
  // Check if coordinates are out of bounds (treat out-of-bounds as no wall)
  wire check_x_1_oob = (check_x_1 >= IMG_W);
  wire check_y_1_oob = (check_y_1 >= IMG_H);
  wire check_x_2_oob = (check_x_2 >= IMG_W);
  wire check_y_2_oob = (check_y_2 >= IMG_H);
  wire check_x_3_oob = (check_x_3 >= IMG_W);
  wire check_y_3_oob = (check_y_3 >= IMG_H);
  
  // Clamp coordinates to valid image bounds for ROM addressing
  // (out-of-bounds checks will be ignored in wall detection logic)
  wire [9:0] check_x_1_clamped = (check_x_1 > IMG_W-1) ? IMG_W-1 : check_x_1;
  wire [9:0] check_y_1_clamped = (check_y_1 > IMG_H-1) ? IMG_H-1 : check_y_1;
  wire [9:0] check_x_2_clamped = (check_x_2 > IMG_W-1) ? IMG_W-1 : check_x_2;
  wire [9:0] check_y_2_clamped = (check_y_2 > IMG_H-1) ? IMG_H-1 : check_y_2;
  wire [9:0] check_x_3_clamped = (check_x_3 > IMG_W-1) ? IMG_W-1 : check_x_3;
  wire [9:0] check_y_3_clamped = (check_y_3 > IMG_H-1) ? IMG_H-1 : check_y_3;
  
  // Calculate ROM addresses: addr = (y * 224) + x
  wire [15:0] addr_y_1 = calc_img_addr_y(check_y_1_clamped);  // y*224
  wire [15:0] addr_y_2 = calc_img_addr_y(check_y_2_clamped);  // y*224
  wire [15:0] addr_y_3 = calc_img_addr_y(check_y_3_clamped);  // y*224
  wire [15:0] wall_check_addr_1 = addr_y_1 + check_x_1_clamped;
  wire [15:0] wall_check_addr_2 = addr_y_2 + check_x_2_clamped;
  wire [15:0] wall_check_addr_3 = addr_y_3 + check_x_3_clamped;
  
  // Register addresses, direction, and out-of-bounds flags together to keep them aligned with ROM latency
  reg [15:0] wall_check_addr_1_d, wall_check_addr_2_d, wall_check_addr_3_d;
  reg [1:0] pac_dir_d;
  reg check_x_1_oob_d, check_y_1_oob_d, check_x_2_oob_d, check_y_2_oob_d, check_x_3_oob_d, check_y_3_oob_d;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      wall_check_addr_1_d <= 16'd0;
      wall_check_addr_2_d <= 16'd0;
      wall_check_addr_3_d <= 16'd0;
      pac_dir_d <= 2'd1;  // Match initial pac_dir (left)
      check_x_1_oob_d <= 1'b0;
      check_y_1_oob_d <= 1'b0;
      check_x_2_oob_d <= 1'b0;
      check_y_2_oob_d <= 1'b0;
      check_x_3_oob_d <= 1'b0;
      check_y_3_oob_d <= 1'b0;
    end else begin
      wall_check_addr_1_d <= wall_check_addr_1;
      wall_check_addr_2_d <= wall_check_addr_2;
      wall_check_addr_3_d <= wall_check_addr_3;
      pac_dir_d <= pac_dir;
      check_x_1_oob_d <= check_x_1_oob;
      check_y_1_oob_d <= check_y_1_oob;
      check_x_2_oob_d <= check_x_2_oob;
      check_y_2_oob_d <= check_y_2_oob;
      check_x_3_oob_d <= check_x_3_oob;
      check_y_3_oob_d <= check_y_3_oob;
    end
  end
  
  // Access maze ROM to check for wall pixels (value 4'hC)
  // Use registered addresses that correspond to registered direction
  wire [3:0] wall_pix_1, wall_pix_2, wall_pix_3;
  image_rom_224x288_4bpp UWALL_CHECK_1 (
    .clk(pclk),
    .addr(wall_check_addr_1_d),
    .data(wall_pix_1)
  );
  image_rom_224x288_4bpp UWALL_CHECK_2 (
    .clk(pclk),
    .addr(wall_check_addr_2_d),
    .data(wall_pix_2)
  );
  image_rom_224x288_4bpp UWALL_CHECK_3 (
    .clk(pclk),
    .addr(wall_check_addr_3_d),
    .data(wall_pix_3)
  );
  
  // Register ROM outputs and out-of-bounds flags (now 2 cycles total latency: address reg + ROM)
  reg [3:0] wall_pix_1_d, wall_pix_2_d, wall_pix_3_d;
  reg [1:0] pac_dir_d2;  // Register direction again to match ROM output latency
  reg check_x_1_oob_d2, check_y_1_oob_d2, check_x_2_oob_d2, check_y_2_oob_d2, check_x_3_oob_d2, check_y_3_oob_d2;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      wall_pix_1_d <= 4'h0;
      wall_pix_2_d <= 4'h0;
      wall_pix_3_d <= 4'h0;
      pac_dir_d2 <= 2'd1;  // Match initial pac_dir (left)
      check_x_1_oob_d2 <= 1'b0;
      check_y_1_oob_d2 <= 1'b0;
      check_x_2_oob_d2 <= 1'b0;
      check_y_2_oob_d2 <= 1'b0;
      check_x_3_oob_d2 <= 1'b0;
      check_y_3_oob_d2 <= 1'b0;
    end else begin
      wall_pix_1_d <= wall_pix_1;
      wall_pix_2_d <= wall_pix_2;
      wall_pix_3_d <= wall_pix_3;
      pac_dir_d2 <= pac_dir_d;  // Track direction that matches these wall checks
      check_x_1_oob_d2 <= check_x_1_oob_d;
      check_y_1_oob_d2 <= check_y_1_oob_d;
      check_x_2_oob_d2 <= check_x_2_oob_d;
      check_y_2_oob_d2 <= check_y_2_oob_d;
      check_x_3_oob_d2 <= check_x_3_oob_d;
      check_y_3_oob_d2 <= check_y_3_oob_d;
    end
  end
  
  // Check if any checked pixel is a wall (4'hC = 12 decimal)
  // Only consider pixels that are within bounds (out-of-bounds treated as no wall)
  wire wall_pixel_found = ((wall_pix_1_d == 4'hC) && !check_x_1_oob_d2 && !check_y_1_oob_d2) ||
                          ((wall_pix_2_d == 4'hC) && !check_x_2_oob_d2 && !check_y_2_oob_d2) ||
                          ((wall_pix_3_d == 4'hC) && !check_x_3_oob_d2 && !check_y_3_oob_d2);
  
  // Block movement if leading edge hits wall AND direction matches
  // Only use wall detection if the current direction matches the direction used for the wall check
  // This prevents using stale wall checks after direction changes
  wire wall_detected = wall_pixel_found && (pac_dir == pac_dir_d2);
  
  // Track direction changes and block movement for 2 cycles to allow wall detection pipeline to catch up
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      direction_change_block <= 2'd0;
      pac_dir_prev <= 2'd1;  // Match initial pac_dir
    end else begin
      pac_dir_prev <= pac_dir;
      if (pac_dir != pac_dir_prev && game_started) begin
        // Direction changed - block movement for 2 cycles
        direction_change_block <= 2'd2;
      end else if (direction_change_block > 0) begin
        // Count down the blocking period
        direction_change_block <= direction_change_block - 1;
      end
    end
  end

  // -------------------------
  // Dot Collection System
  // -------------------------
  // Pac-Man's current tile (center position)
  wire [4:0] pac_center_tile_x = pac_local_x[9:3];  // 0..27
  wire [5:0] pac_center_tile_y = pac_local_y[9:3];  // 0..35
  wire [9:0] pac_center_tile_index = calc_tile_index_y(pac_center_tile_y) + pac_center_tile_x;
  
  wire pac_center_wall;
  level_rom ULEVEL_PAC_CENTER (
    .tile_index(pac_center_tile_index),
    .is_wall(pac_center_wall)
  );
  
  // Dot map: tracks which tiles have dots
  wire dot_has_dot;
  wire [7:0] dots_remaining;
  reg level_reset;
  reg dot_collected;
  
  dot_map UDOT_MAP (
    .clk(pclk),
    .rst_n(rst_n),
    .level_reset(level_reset),
    .tile_x(pac_center_tile_x),
    .tile_y(pac_center_tile_y),
    .clear_dot(dot_collected),
    .is_wall_tile(pac_center_wall),
    .has_dot(dot_has_dot),
    .render_tile_x(render_tile_x),
    .render_tile_y(render_tile_y),
    .render_is_wall(render_tile_wall),
    .render_has_dot(render_tile_has_dot),
    .dots_remaining(dots_remaining)
  );
  
  // -------------------------
  // Power Pellets (Energizers)
  // -------------------------
  // Power pellet locations: (1,6), (26,6), (1,26), (26,26)
  localparam [4:0] PELLET_TILE_X_1 = 5'd1;
  localparam [4:0] PELLET_TILE_X_2 = 5'd26;
  localparam [5:0] PELLET_TILE_Y_1 = 6'd6;
  localparam [5:0] PELLET_TILE_Y_2 = 6'd26;
  
  // Track which power pellets have been collected (4 pellets)
  reg [3:0] pellets_collected;  // One bit per pellet
  
  // Check if current tile is a power pellet location
  wire is_pellet_tile = is_power_pellet_tile(pac_center_tile_x, pac_center_tile_y);
  
  // Check which specific pellet (for collection tracking)
  // Power pellets are at: (1,6), (26,6), (1,26), (26,26)
  wire is_pellet_tile_1 = (pac_center_tile_x == PELLET_TILE_X_1) && (pac_center_tile_y == PELLET_TILE_Y_1);
  wire is_pellet_tile_2 = (pac_center_tile_x == PELLET_TILE_X_2) && (pac_center_tile_y == PELLET_TILE_Y_1);
  wire is_pellet_tile_3 = (pac_center_tile_x == PELLET_TILE_X_1) && (pac_center_tile_y == PELLET_TILE_Y_2);
  wire is_pellet_tile_4 = (pac_center_tile_x == PELLET_TILE_X_2) && (pac_center_tile_y == PELLET_TILE_Y_2);
  wire pellet_1_active = is_pellet_tile_1 && !pellets_collected[0];
  wire pellet_2_active = is_pellet_tile_2 && !pellets_collected[1];
  wire pellet_3_active = is_pellet_tile_3 && !pellets_collected[2];
  wire pellet_4_active = is_pellet_tile_4 && !pellets_collected[3];
  wire pellet_active = pellet_1_active || pellet_2_active || pellet_3_active || pellet_4_active;
  
  // Power pellet collection detection
  reg pellet_collected;
  reg pellet_collected_prev;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      pellets_collected <= 4'b0000;
      pellet_collected <= 1'b0;
      pellet_collected_prev <= 1'b0;
    end else begin
      pellet_collected_prev <= pellet_active && game_started && pac_in_maze && !pac_center_wall;
      
      // Generate one-cycle pulse when entering a pellet tile
      if (pellet_active && !pellet_collected_prev && game_started && pac_in_maze && !pac_center_wall) begin
        pellet_collected <= 1'b1;
        // Mark which pellet was collected
        if (is_pellet_tile_1) pellets_collected[0] <= 1'b1;
        if (is_pellet_tile_2) pellets_collected[1] <= 1'b1;
        if (is_pellet_tile_3) pellets_collected[2] <= 1'b1;
        if (is_pellet_tile_4) pellets_collected[3] <= 1'b1;
      end else begin
        pellet_collected <= 1'b0;
      end
      
      // Reset pellets on level reset
      if (level_reset) begin
        pellets_collected <= 4'b0000;
      end
    end
  end
  
  // Fright mode will be triggered by pellet_collected (to be implemented in Phase 2.3)
  
  // Power pellet rendering: check if pellet is collected (declared after pellets_collected)
  wire is_render_pellet_1 = (render_tile_x == PELLET_TILE_X_1) && (render_tile_y == PELLET_TILE_Y_1);
  wire is_render_pellet_2 = (render_tile_x == PELLET_TILE_X_2) && (render_tile_y == PELLET_TILE_Y_1);
  wire is_render_pellet_3 = (render_tile_x == PELLET_TILE_X_1) && (render_tile_y == PELLET_TILE_Y_2);
  wire is_render_pellet_4 = (render_tile_x == PELLET_TILE_X_2) && (render_tile_y == PELLET_TILE_Y_2);
  wire render_pellet_collected = (is_render_pellet_1 && pellets_collected[0]) ||
                                 (is_render_pellet_2 && pellets_collected[1]) ||
                                 (is_render_pellet_3 && pellets_collected[2]) ||
                                 (is_render_pellet_4 && pellets_collected[3]);
  
  // -------------------------
  // Scoring System
  // -------------------------
  wire [15:0] score;
  wire [2:0] lives;
  wire [15:0] high_score;
  wire game_over;
  // -------------------------
  // Ghost Collision Detection
  // -------------------------
  // Check collision between Pac-Man and Blinky (tile-based)
  // Collision occurs when Pac-Man and ghost are in the same tile
  wire blinky_collision = (pac_center_tile_x == blinky_tile_x) && 
                          (pac_center_tile_y == blinky_tile_y) &&
                          game_started && pac_in_maze;
  
  // Fright mode status (to be implemented in Phase 2.3)
  wire is_fright_mode = 1'b0;  // Will be set when power pellet is active
  
  // Collision handling
  reg lose_life_reg;
  reg ghost_eaten_reg;
  reg [1:0] ghost_eaten_count_reg;
  
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      lose_life_reg <= 1'b0;
      ghost_eaten_reg <= 1'b0;
      ghost_eaten_count_reg <= 2'd0;
    end else begin
      lose_life_reg <= 1'b0;
      ghost_eaten_reg <= 1'b0;
      
      if (blinky_collision) begin
        if (is_fright_mode) begin
          // Ghost eaten in fright mode
          ghost_eaten_reg <= 1'b1;
          ghost_eaten_count_reg <= 2'd0;  // Blinky is ghost 0
          // TODO: Send Blinky back to house (Phase 2.4)
        end else begin
          // Pac-Man caught - lose life
          lose_life_reg <= 1'b1;
        end
      end
    end
  end
  
  wire lose_life = lose_life_reg;
  wire level_complete = (dots_remaining == 8'd0);  // All dots collected
  wire ghost_eaten = ghost_eaten_reg;
  wire [1:0] ghost_eaten_count = ghost_eaten_count_reg;
  
  score_manager USCORE (
    .clk(pclk),
    .rst_n(rst_n),
    .game_started(game_started),
    .dot_collected(dot_collected),
    .pellet_collected(pellet_collected),
    .ghost_eaten(ghost_eaten),
    .ghost_eaten_count(ghost_eaten_count),
    .lose_life(lose_life),
    .level_complete(level_complete),
    .score(score),
    .lives(lives),
    .high_score(high_score),
    .game_over(game_over)
  );
  
  // Detect dot collection: when Pac-Man's center enters a tile with a dot
  reg dot_has_dot_prev;
  reg [4:0] last_collected_tile_x;
  reg [5:0] last_collected_tile_y;
  reg [9:0] level_reset_counter;
  
  // Combinational logic for dot collection detection
  wire new_tile = (pac_center_tile_x != last_collected_tile_x) || (pac_center_tile_y != last_collected_tile_y);
  wire entering_dot_tile = dot_has_dot && !dot_has_dot_prev && game_started && pac_in_maze && !pac_center_wall;
  
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      dot_collected <= 1'b0;
      dot_has_dot_prev <= 1'b0;
      last_collected_tile_x <= 5'd0;
      last_collected_tile_y <= 6'd0;
      level_reset <= 1'b0;
      level_reset_counter <= 10'd0;
    end else begin
      dot_has_dot_prev <= dot_has_dot;
      
      // Generate one-cycle pulse when entering a tile with a dot
      // Also check that we haven't already collected from this tile
      
      if (entering_dot_tile && new_tile) begin
        dot_collected <= 1'b1;
        last_collected_tile_x <= pac_center_tile_x;
        last_collected_tile_y <= pac_center_tile_y;
      end else begin
        dot_collected <= 1'b0;
      end
      
      // Level reset: trigger when game starts or level advances
      // Hold reset for enough cycles to complete dot map reset (1008 cycles)
      if (start_game && !game_started) begin
        level_reset <= 1'b1;
        level_reset_counter <= 10'd0;
        last_collected_tile_x <= 5'd0;
        last_collected_tile_y <= 6'd0;
      end else if (level_reset && level_reset_counter < 10'd1100) begin
        // Keep reset active for enough cycles
        level_reset_counter <= level_reset_counter + 10'd1;
      end else begin
        level_reset <= 1'b0;
        level_reset_counter <= 10'd0;
      end
    end
  end

  // Level-based speed parameters
  wire [7:0] pacman_speed, ghost_speed;
  level_params ULEVEL_PARAMS (
    .level(current_level),
    .pacman_speed(pacman_speed),
    .pacman_dots_speed(),  // unused for now
    .ghost_speed(ghost_speed),
    .ghost_tunnel_speed(),  // unused for now
    .elroy1_speed(),  // unused for now
    .elroy2_speed(),  // unused for now
    .elroy1_dots_left(),  // unused for now
    .elroy2_dots_left(),  // unused for now
    .fright_pacman_speed(),  // unused for now
    .fright_pacman_dots_speed(),  // unused for now
    .fright_ghost_speed(),  // unused for now
    .fright_time(),  // unused for now
    .fright_flashes()  // unused for now
  );

  // Track if player has pressed a direction key (to keep pacman still at start)
  reg player_has_moved;
  
  // Pipeline initialization delay: wait for collision detection pipeline to initialize
  // Pipeline has 2-3 cycles latency, so wait 4 frame ticks to be safe
  reg [2:0] pipeline_init_counter;
  wire pipeline_ready = (pipeline_init_counter >= 3'd4);
  
  // Movement at ~75.7576 px/s using 125/99 pixels per frame
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      // Pac-Man starting tile: (14, 28), facing left
      // Tile 14 = 14*8 = 112 pixels, Tile 28 = 28*8 = 224 pixels
      pac_x     <= IMG_X0 + (14*8);        // = 208 + 112 = 320
      pac_y     <= IMG_Y0 + (28*8) + 4;    // = 96 + 224 + 4 = 324
      pac_dir   <= 2'd1;                   // left
      speed_acc <= 8'd0;
      player_has_moved <= 1'b0;
      pipeline_init_counter <= 3'd0;
      direction_change_block <= 2'd0;
      pac_dir_prev <= 2'd1;  // Match initial pac_dir
    end else begin
      // Reset player_has_moved when game state changes to ATTRACT or READY
      if (game_state == STATE_ATTRACT || game_state == STATE_READY) begin
        player_has_moved <= 1'b0;
        pipeline_init_counter <= 3'd0;
      end
      
      // Initialize collision detection pipeline when game starts
      if (game_started && !pipeline_ready) begin
        if (frame_tick) begin
          pipeline_init_counter <= pipeline_init_counter + 3'd1;
        end
      end else if (!game_started) begin
        pipeline_init_counter <= 3'd0;
      end
      
      // Check if player pressed a direction key
      if (game_started && (move_up || move_down || move_left || move_right)) begin
        player_has_moved <= 1'b1;
      end
      
      if (frame_tick && game_started && player_has_moved && pipeline_ready) begin
        // Use the pre-calculated step_px_wire for movement
        speed_acc <= tmp_acc_after_second;

        // move step_px_wire pixels this frame if path is clear
        // Block movement for 2 cycles after direction change to allow wall detection pipeline to catch up
        if (step_px_wire != 2'd0 && pac_in_maze && !wall_detected && direction_change_block == 2'd0) begin
          case (pac_dir)
            2'd0: pac_x <= pac_x + step_px_wire;  // right
            2'd1: pac_x <= pac_x - step_px_wire;  // left
            2'd2: pac_y <= pac_y - step_px_wire;  // up
            2'd3: pac_y <= pac_y + step_px_wire;  // down
          endcase
        end
      end else if (frame_tick && game_started) begin
        // When game starts but player hasn't moved yet or pipeline not ready, reset speed accumulator
        speed_acc <= 8'd0;
      end
      
      // Direction changes synchronized to frame_tick (only when game started)
      // CRITICAL: Must be synchronized to frame_tick to match collision detection pipeline
      if (frame_tick && game_started) begin
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
  end

  // -------------------------
  // Blinky (Red Ghost) integration
  // -------------------------
  // Convert pacman center position to tile coordinates (6-bit) for blinky
  wire [5:0] pacman_tile_x = pac_local_x[9:3];  // 0..27, but blinky uses 6-bit
  wire [5:0] pacman_tile_y = pac_local_y[9:3];  // 0..35, but blinky uses 6-bit

  // Blinky position in tile coordinates (from blinky module)
  wire [5:0] blinky_tile_x, blinky_tile_y;

  // Convert blinky tile position to screen coordinates (center of tile)
  wire [9:0] blinky_x = IMG_X0 + (blinky_tile_x << 3) + 4;  // tile_x*8 + 4 (center)
  wire [9:0] blinky_y = IMG_Y0 + (blinky_tile_y << 3) + 4;  // tile_y*8 + 4 (center)

  // Wall detection for blinky's current position (check all 4 directions)
  wire [9:0] blinky_tile_idx = calc_tile_index_y(blinky_tile_y) + blinky_tile_x;
  
  wire blinky_wall_up, blinky_wall_down, blinky_wall_left, blinky_wall_right;
  wire blinky_wall_up_rom, blinky_wall_down_rom, blinky_wall_left_rom, blinky_wall_right_rom;
  
  // Check walls in adjacent tiles (or treat boundaries as walls)
  // Calculate adjacent tile indices
  wire [9:0] blinky_tile_idx_up    = (blinky_tile_y > 0) ? (blinky_tile_idx - 10'd28) : 10'd1008;
  wire [9:0] blinky_tile_idx_down  = (blinky_tile_y < 35) ? (blinky_tile_idx + 10'd28) : 10'd1008;
  wire [9:0] blinky_tile_idx_left  = (blinky_tile_x > 0) ? (blinky_tile_idx - 10'd1) : 10'd1008;
  wire [9:0] blinky_tile_idx_right = (blinky_tile_x < 27) ? (blinky_tile_idx + 10'd1) : 10'd1008;

  // Check if each direction is at boundary (use 1008 as sentinel for invalid tiles)
  wire blinky_at_boundary_up    = (blinky_tile_y == 0);
  wire blinky_at_boundary_down  = (blinky_tile_y == 35);
  wire blinky_at_boundary_left  = (blinky_tile_x == 0);
  wire blinky_at_boundary_right = (blinky_tile_x == 27);

  // Only access ROM for valid (non-boundary) tiles
  // Use valid tile index when not at boundary, otherwise use 0 (will be overridden anyway)
  wire [9:0] blinky_tile_idx_up_safe    = blinky_at_boundary_up    ? 10'd0 : blinky_tile_idx_up;
  wire [9:0] blinky_tile_idx_down_safe  = blinky_at_boundary_down  ? 10'd0 : blinky_tile_idx_down;
  wire [9:0] blinky_tile_idx_left_safe  = blinky_at_boundary_left  ? 10'd0 : blinky_tile_idx_left;
  wire [9:0] blinky_tile_idx_right_safe = blinky_at_boundary_right ? 10'd0 : blinky_tile_idx_right;
  
  // Note: ROM access with index 0 when at boundary is harmless since boundary check overrides it
  // This avoids needing conditional ROM instantiation which would complicate the design

  level_rom ULEVEL_BLINKY_UP (
    .tile_index(blinky_tile_idx_up_safe),
    .is_wall(blinky_wall_up_rom)
  );
  
  level_rom ULEVEL_BLINKY_DOWN (
    .tile_index(blinky_tile_idx_down_safe),
    .is_wall(blinky_wall_down_rom)
  );
  
  level_rom ULEVEL_BLINKY_LEFT (
    .tile_index(blinky_tile_idx_left_safe),
    .is_wall(blinky_wall_left_rom)
  );
  
  level_rom ULEVEL_BLINKY_RIGHT (
    .tile_index(blinky_tile_idx_right_safe),
    .is_wall(blinky_wall_right_rom)
  );

  // Treat boundaries as walls (boundaries override ROM output)
  assign blinky_wall_up    = blinky_at_boundary_up    ? 1'b1 : blinky_wall_up_rom;
  assign blinky_wall_down  = blinky_at_boundary_down  ? 1'b1 : blinky_wall_down_rom;
  assign blinky_wall_left  = blinky_at_boundary_left  ? 1'b1 : blinky_wall_left_rom;
  assign blinky_wall_right = blinky_at_boundary_right ? 1'b1 : blinky_wall_right_rom;

  // Chase/scatter mode control (default to chase mode)
  reg isChase, isScatter;
  wire rst_n_pll = rst_n & pll_locked;
  always @(posedge pclk or negedge rst_n_pll) begin
    if (!rst_n_pll) begin
      isChase <= 1'b1;
      isScatter <= 1'b0;
    end else begin
      // For now, always chase. Can be extended later with timing logic
      isChase <= 1'b1;
      isScatter <= 1'b0;
    end
  end

  // Gate frame_tick for Blinky: only move when game has started
  wire blinky_frame_tick = frame_tick && game_started;

  // Instantiate blinky module
  blinky UBLINKY (
    .clk(pclk),
    .rst_n(rst_n & pll_locked),  // active-low reset, wait for PLL lock
    .frame_tick(blinky_frame_tick),  // Synchronize movement to frame timing (gated)
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
  // Pac-Man sprite (16x16) using Pacman.hex
  // -------------------------
  // top-left of sprite box
  wire [9:0] pac_left = calc_sprite_left(pac_x, PAC_R);
  wire [9:0] pac_top  = calc_sprite_top(pac_y, PAC_R);

  // sprite-local coordinates at this pixel
  wire [3:0] spr_x = calc_sprite_x(h_d, pac_left);
  wire [3:0] spr_y = calc_sprite_y(v_d, pac_top);

  wire       in_pac_box = is_in_sprite_box(h_d, v_d, pac_left, pac_top, SPR_W, SPR_H);

  // Rotate/flip sprite based on direction
  // Right (0): normal, Left (1): horizontal flip, Up (2): 90° CW, Down (3): 90° CCW
  wire [3:0] spr_x_rotated, spr_y_rotated;
  assign spr_x_rotated = (pac_dir == 2'd0) ? spr_x :                    // right: normal
                         (pac_dir == 2'd1) ? (4'd15 - spr_x) :          // left: flip H
                         (pac_dir == 2'd2) ? (4'd15 - spr_y) :          // up: rotate CW (swapped)
                         spr_y;                                         // down: rotate CCW (swapped)
  assign spr_y_rotated = (pac_dir == 2'd0) ? spr_y :                    // right: normal
                         (pac_dir == 2'd1) ? spr_y :                    // left: flip H
                         (pac_dir == 2'd2) ? spr_x :                    // up: rotate CW (swapped)
                         (4'd15 - spr_x);                               // down: rotate CCW (swapped)

  wire [7:0] pac_addr = calc_sprite_addr(spr_x_rotated, spr_y_rotated);  // y*16 + x (rotated)

  wire [3:0] pac_pix_data;
  pacman_rom_16x16_4bpp UPAC (
    .clk(pclk),
    .addr(pac_addr),
    .data(pac_pix_data)
  );

  // Delay sprite box check by one cycle to match ROM output timing
  reg in_pac_box_d;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n)
      in_pac_box_d <= 1'b0;
    else
      in_pac_box_d <= in_pac_box;
  end

  // Pac-Man pixel is "active" when inside box and sprite index != 0 (0 = transparent)
  wire pac_pix = in_pac_box_d && (pac_pix_data != 4'h0);

  // -------------------------
  // Blinky sprite (16x16) using Blinky.hex
  // -------------------------
  // top-left of sprite box
  wire [9:0] blinky_left = calc_sprite_left(blinky_x, PAC_R);
  wire [9:0] blinky_top  = calc_sprite_top(blinky_y, PAC_R);

  // sprite-local coordinates at this pixel
  wire [3:0] blinky_spr_x = calc_sprite_x(h_d, blinky_left);
  wire [3:0] blinky_spr_y = calc_sprite_y(v_d, blinky_top);

  wire       in_blinky_box = is_in_sprite_box(h_d, v_d, blinky_left, blinky_top, SPR_W, SPR_H);

  wire [7:0] blinky_addr = calc_sprite_addr(blinky_spr_x, blinky_spr_y);  // y*16 + x

  wire [3:0] blinky_pix_data;
  blinky_rom_16x16_4bpp UBLINKY_ROM (
    .clk(pclk),
    .addr(blinky_addr),
    .data(blinky_pix_data)
  );

  // Delay sprite box check by one cycle to match ROM output timing
  reg in_blinky_box_d;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n)
      in_blinky_box_d <= 1'b0;
    else
      in_blinky_box_d <= in_blinky_box;
  end

  // Blinky pixel is "active" when inside box and sprite index != 0 (0 = transparent)
  wire blinky_pix = in_blinky_box_d && (blinky_pix_data != 4'h0);

  // -------------------------
  // RGB output with sprite overlay
  // -------------------------
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      r <= 4'h0;
      g <= 4'h0;
      b <= 4'h0;
    end else begin
      if (h_vis && v_vis) begin
        if (pac_pix) begin
          // Pac-Man sprite from palette: 0=transparent, 7=yellow
          case (pac_pix_data)
            4'h7: begin
              r <= 4'hF; g <= 4'hF; b <= 4'h0;   // yellow body
            end
            default: begin
              // any other non-zero index: treat as white
              r <= 4'hF; g <= 4'hF; b <= 4'hF;
            end
          endcase
        end else if (blinky_pix) begin
          // Blinky sprite from palette: 0=transparent, 7=red
          case (blinky_pix_data)
            4'h7: begin
              r <= 4'hF; g <= 4'h0; b <= 4'h0;   // red body
            end
            default: begin
              // any other non-zero index: treat as white
              r <= 4'hF; g <= 4'hF; b <= 4'hF;
            end
          endcase
        end else if (in_img_area) begin
          // Maze from ROM
          case (pix_data)
            4'h0: begin
              r <= 4'h0; g <= 4'h0; b <= 4'h0;      // background
            end
            4'hC: begin
              r <= 4'h0; g <= 4'h0; b <= 4'hF;      // blue walls
            end
            4'hF: begin
              // White dots/power pellets: check if this is a pellet location
              if (is_render_pellet_tile && !render_pellet_collected && !render_tile_wall) begin
                // Power pellet: larger white circle (render as 2x2 dot for now)
                // TODO: Use dedicated power pellet sprite
                r <= 4'hF; g <= 4'hF; b <= 4'hF;   // white power pellet
              end else if (render_tile_has_dot && !render_tile_wall && !is_render_pellet_tile) begin
                r <= 4'hF; g <= 4'hF; b <= 4'hF;   // white dot
              end else begin
                r <= 4'h0; g <= 4'h0; b <= 4'h0;   // background (dot/pellet collected)
              end
            end
            4'h7: begin
              r <= 4'hF; g <= 4'h0; b <= 4'hF;      // magenta accents
            end
            default: begin
              r <= 4'h0; g <= 4'h0; b <= 4'h0;
            end
          endcase
        end else begin
          r <= 4'h0; g <= 4'h0; b <= 4'h0;
        end
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
    localparam DEPTH = 64512;
    reg [3:0] mem [0:DEPTH-1];

    initial begin
        $readmemh("WithoutDots.hex", mem);
    end

    always @(posedge clk) begin
        // Bounds checking: clamp address to valid range
        if (addr < DEPTH)
            data <= mem[addr];
        else
            data <= 4'h0;  // Return transparent/background if out of bounds
    end
endmodule


// Pac-Man sprite: 16x16, 4-bit pixels (0=transparent, 7=yellow) from Pacman.hex
module pacman_rom_16x16_4bpp (
    input  wire        clk,
    input  wire [7:0] addr,   // 0 .. 255
    output reg  [3:0] data
);
    localparam DEPTH = 256;
    reg [3:0] mem [0:DEPTH-1];

    initial begin
        $readmemh("Pacman.hex", mem);
    end

    always @(posedge clk) begin
        // Bounds checking: addr is 8-bit, so automatically in range 0-255
        // But check anyway for safety
        if (addr < DEPTH)
            data <= mem[addr];
        else
            data <= 4'h0;  // Return transparent if out of bounds
    end
endmodule


// Blinky sprite: 16x16, 4-bit pixels (0=transparent, 7=red) from Blinky.hex
module blinky_rom_16x16_4bpp (
    input  wire        clk,
    input  wire [7:0] addr,   // 0 .. 255
    output reg  [3:0] data
);
    localparam DEPTH = 256;
    reg [3:0] mem [0:DEPTH-1];

    initial begin
        $readmemh("Blinky.hex", mem);
    end

    always @(posedge clk) begin
        // Bounds checking: addr is 8-bit, so automatically in range 0-255
        // But check anyway for safety
        if (addr < DEPTH)
            data <= mem[addr];
        else
            data <= 4'h0;  // Return transparent if out of bounds
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

    assign is_wall = (tile_index < 10'd1008) ? bits[tile_index] : 1'b0;
endmodule