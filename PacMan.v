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
  wire rst_n = KEY0;                // KEY0 is active-low, OK
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

  // Frame counter (unchanged)
  reg [15:0] frame_cnt;
  reg vs_d;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      vs_d      <= 1'b0;
      frame_cnt <= 16'h0000;
    end else begin
      vs_d <= vs;
      if (vs_d && !vs) frame_cnt <= frame_cnt + 1'b1; // increment per frame
    end
  end

  sevenseg HEXL(.x(frame_cnt[3:0]),  .seg(HEX0));
  sevenseg HEXH(.x(frame_cnt[7:4]),  .seg(HEX1));
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

  // H/V counters (stage 0)
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

  // Sync and "raw" visible using current counters (stage 0)
  wire h_vis_raw = (h < H_VIS);
  wire v_vis_raw = (v < V_VIS);

  assign hs = ~((h >= H_VIS+H_FP) && (h < H_VIS+H_FP+H_SYNC));
  assign vs = ~((v >= V_VIS+V_FP) && (v < V_VIS+V_FP+V_SYNC));

  // ROM address based on current counters (stage 0)
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

  // ROM: 4-bit pixels, 1-cycle latency
  wire [3:0] pix_data;

  image_rom_224x288_4bpp UIMG (
    .clk (pclk),
    .addr(img_addr),
    .data(pix_data)
  );

  // 4-bit palette: map index -> RGB (stage 2: pix_data aligned with h_d/v_d)
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      r <= 4'h0;
      g <= 4'h0;
      b <= 4'h0;
    end else begin
      if (h_vis && v_vis) begin
        if (in_img_area) begin
          case (pix_data)
            4'h0: begin
              // background
              r <= 4'h0; g <= 4'h0; b <= 4'h0;      // black
            end
            4'hC: begin
              // main maze walls
              r <= 4'h0; g <= 4'h0; b <= 4'hF;      // bright blue
            end
            4'hF: begin
              // highlights / dots
              r <= 4'hF; g <= 4'hF; b <= 4'hF;      // white
            end
            4'h7: begin
              // rare colour
              r <= 4'hF; g <= 4'h0; b <= 4'h0;      // red
            end
            default: begin
              // anything else -> background
              r <= 4'h0; g <= 4'h0; b <= 4'h0;
            end
          endcase
        end else begin
          // outside image but still in visible area
          r <= 4'h0; g <= 4'h0; b <= 4'h0;
        end
      end else begin
        // blanking
        r <= 4'h0; g <= 4'h0; b <= 4'h0;
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



module sevenseg(input [3:0] x, output reg [6:0] seg);
  always @* begin
    case (x)
      4'h0: seg=7'b1000000;
      4'h1: seg=7'b1111001;
      4'h2: seg=7'b0100100;
      4'h3: seg=7'b0110000;
      4'h4: seg=7'b0011001;
      4'h5: seg=7'b0010010;
      4'h6: seg=7'b0000010;
      4'h7: seg=7'b1111000;
      4'h8: seg=7'b0000000;
      4'h9: seg=7'b0010000;
      4'hA: seg=7'b0001000;
      4'hB: seg=7'b0000011;
      4'hC: seg=7'b1000110;
      4'hD: seg=7'b0100001;
      4'hE: seg=7'b0000110;
      default: seg=7'b0001110;
    endcase
  end
endmodule
