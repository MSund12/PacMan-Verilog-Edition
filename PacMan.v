module PacMan(
  input  wire CLOCK_50,
  input  wire KEY0,
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
  reg [9:0] pac_x, pac_y;     // center position (screen coords)
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

  // current tile (8x8) from center point
  wire [4:0] pac_tile_x = pac_local_x[9:3];  // 0..27
  wire [5:0] pac_tile_y = pac_local_y[9:3];  // 0..35

  // next tile in current direction
  reg [4:0] target_tile_x;
  reg [5:0] target_tile_y;
  always @* begin
    target_tile_x = pac_tile_x;
    target_tile_y = pac_tile_y;
    case (pac_dir)
      2'd0: if (pac_tile_x < TILES_X-1) target_tile_x = pac_tile_x + 1; // right
      2'd1: if (pac_tile_x > 0)        target_tile_x = pac_tile_x - 1; // left
      2'd2: if (pac_tile_y > 0)        target_tile_y = pac_tile_y - 1; // up
      2'd3: if (pac_tile_y < TILES_Y-1) target_tile_y = pac_tile_y + 1; // down
    endcase
  end

  // linear tile index = tile_y*28 + tile_x (28 = 32 - 4)
  wire [9:0] idx_y             = (target_tile_y << 5) - (target_tile_y << 2);
  wire [9:0] target_tile_index = idx_y + target_tile_x;

  wire wall_at_target;
  level_rom ULEVEL (
    .tile_index(target_tile_index),
    .is_wall   (wall_at_target)
  );

  // Movement at ~75.7576 px/s using 125/99 pixels per frame
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      // Pac-Man starting tile: (13, 26), facing left
      pac_x    <= IMG_X0 + (14*8);     // = 316
      pac_y    <= IMG_Y0 + (28*8) + 4;     // = 308
      pac_dir  <= 2'd1;                    // left
      speed_acc <= 8'd0;
    end else begin
      if (frame_tick) begin
        // fractional step accumulator: speed = 125/99 px per frame
        tmp_acc = speed_acc + 8'd125;
        step_px = 2'd0;

        // subtract denominator (99) up to twice per frame
        if (tmp_acc >= 8'd99) begin
          tmp_acc = tmp_acc - 8'd99;
          step_px = step_px + 2'd1;
        end
        if (tmp_acc >= 8'd99) begin
          tmp_acc = tmp_acc - 8'd99;
          step_px = step_px + 2'd1;
        end

        speed_acc <= tmp_acc;

        // move step_px pixels this frame if path is clear
        if (step_px != 2'd0 && pac_in_maze && !wall_at_target) begin
          case (pac_dir)
            2'd0: pac_x <= pac_x + step_px;  // right
            2'd1: pac_x <= pac_x - step_px;  // left
            2'd2: pac_y <= pac_y - step_px;  // up
            2'd3: pac_y <= pac_y + step_px;  // down
          endcase
        end
      end

      // TODO: update pac_dir from buttons/switches here.
    end
  end

  // -------------------------
  // Pac-Man sprite (16x16) using Pacman.hex
  // -------------------------
  // top-left of sprite box
  wire [9:0] pac_left = pac_x - PAC_R;
  wire [9:0] pac_top  = pac_y - PAC_R;

  // sprite-local coordinates at this pixel
  wire [9:0] spr_x_full = h_d - pac_left;
  wire [9:0] spr_y_full = v_d - pac_top;

  wire       in_pac_box = (spr_x_full < SPR_W) && (spr_y_full < SPR_H);

  wire [3:0] spr_x = spr_x_full[3:0];  // 0..15
  wire [3:0] spr_y = spr_y_full[3:0];  // 0..15

  wire [7:0] pac_addr = (spr_y << 4) | spr_x;  // y*16 + x

  wire [3:0] pac_pix_data;
  pacman_rom_16x16_4bpp UPAC (
    .addr(pac_addr),
    .data(pac_pix_data)
  );

  // Pac-Man pixel is "active" when inside box and sprite index != 0 (0 = transparent)
  wire pac_pix = in_pac_box && (pac_pix_data != 4'h0);

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
              r <= 4'hF; g <= 4'hF; b <= 4'hF;      // white dots
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
    reg [3:0] mem [0:64512-1];

    initial begin
        $readmemh("WithoutDots.hex", mem);
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end
endmodule


// Pac-Man sprite: 16x16, 4-bit pixels (0=transparent, 7=yellow) from Pacman.hex
module pacman_rom_16x16_4bpp (
    input  wire [7:0] addr,   // 0 .. 255
    output reg  [3:0] data
);
    reg [3:0] mem [0:256-1];

    initial begin
        $readmemh("Pacman.hex", mem);
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

