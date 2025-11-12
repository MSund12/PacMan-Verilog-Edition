module top_de10lite_test(
  input  wire CLOCK_50,
  input  wire KEY0,                   // active-low reset on many Terasic boards
  output wire [9:0] LEDR,
  output wire [6:0] HEX0, HEX1
);
  wire rst_n = KEY0;
  wire pclk, pll_locked;

  pll_50_to_25 UPLL(.inclk0(CLOCK_50), .c0(pclk), .locked(pll_locked));

  wire [9:0] h;
  wire [9:0] v;
  wire hs, vs;
  wire [3:0] r,g,b;

  vga_core_640x480 UCORE(
    .pclk(pclk),
    .rst_n(rst_n & pll_locked),
    .h(h),
    .v(v),
    .hs(hs),
    .vs(vs),
    .r(r), .g(g), .b(b)
  );

  reg px_div2;
  always @(posedge pclk or negedge rst_n)
    if (!rst_n) px_div2 <= 1'b0; else px_div2 <= ~px_div2;

  assign LEDR[0] = hs;
  assign LEDR[1] = vs;
  assign LEDR[2] = px_div2;
  assign LEDR[3] = h[5];
  assign LEDR[4] = h[8];
  assign LEDR[5] = v[5];
  assign LEDR[6] = v[8];
  assign LEDR[9:7] = 3'b000;

  reg [15:0] frame_cnt;
  reg vs_d;
  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      vs_d <= 1'b0;
      frame_cnt <= 16'h0000;
    end else begin
      vs_d <= vs;
      if (vs_d && !vs) frame_cnt <= frame_cnt + 1'b1; // count falling edge of VS
    end
  end

  sevenseg HEXL(.x(frame_cnt[3:0]),   .seg(HEX0));
  sevenseg HEXH(.x(frame_cnt[7:4]),   .seg(HEX1));
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
  localparam H_VIS=640, H_FP=16, H_SYNC=96, H_BP=48, H_TOT=800;
  localparam V_VIS=480, V_FP=10, V_SYNC=2,  V_BP=33, V_TOT=525;

  wire h_vis = (h < H_VIS);
  wire v_vis = (v < V_VIS);

  assign hs = ~((h >= H_VIS+H_FP) && (h < H_VIS+H_FP+H_SYNC));
  assign vs = ~((v >= V_VIS+V_FP) && (v < V_VIS+V_FP+V_SYNC));

  always @(posedge pclk or negedge rst_n) begin
    if (!rst_n) begin
      h <= 10'd0; v <= 10'd0;
    end else begin
      if (h == H_TOT-1) begin
        h <= 10'd0;
        v <= (v == V_TOT-1) ? 10'd0 : v + 10'd1;
      end else begin
        h <= h + 10'd1;
      end
    end
  end

  always @(posedge pclk) begin
    if (h_vis && v_vis) begin
      case (h[9:7])
        3'b000: begin r<=4'hF; g<=4'h0; b<=4'h0; end
        3'b001: begin r<=4'h0; g<=4'hF; b<=4'h0; end
        3'b010: begin r<=4'h0; g<=4'h0; b<=4'hF; end
        3'b011: begin r<=4'hF; g<=4'hF; b<=4'h0; end
        3'b100: begin r<=4'hF; g<=4'h0; b<=4'hF; end
        3'b101: begin r<=4'h0; g<=4'hF; b<=4'hF; end
        3'b110: begin r<=4'hF; g<=4'hF; b<=4'hF; end
        default:begin r<=4'h0; g<=4'h0; b<=4'h0; end
      endcase
    end else begin
      r<=4'h0; g<=4'h0; b<=4'h0;
    end
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
