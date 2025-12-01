module inky(
    input  wire        clk,
    input  wire        reset,

    input  wire [5:0]  pacX,
    input  wire [5:0]  pacY,
    input  wire [1:0]  pacDir,      // 00=UP,01=RIGHT,10=DOWN,11=LEFT

    input  wire [5:0]  blinkyX,
    input  wire [5:0]  blinkyY,

    input  wire        canMoveUp,
    input  wire        canMoveRight,
    input  wire        canMoveDown,
    input  wire        canMoveLeft,

    output reg [5:0]   inkyX,
    output reg [5:0]   inkyY,
    output reg [1:0]   dir
);

// =======================================================
// Starting tile position (tile-based, like Blinky)
// =======================================================
// Inky starting tile: tile X=15, tile Y=17
localparam [5:0] INKY_START_TILE_X = 6'd11;
localparam [5:0] INKY_START_TILE_Y = 6'd19;

// =====================================================================
// Declarations (must be OUTSIDE always blocks)
// =====================================================================

reg signed [6:0] offsetX;
reg signed [6:0] offsetY;

reg signed [7:0] vecX;
reg signed [7:0] vecY;

reg signed [7:0] targetX;
reg signed [7:0] targetY;

// distance wires
reg [7:0] distUp;
reg [7:0] distDown;
reg [7:0] distLeft;
reg [7:0] distRight;

// forbid reverse logic
wire forbidUp    = (dir == 2'b10);
wire forbidDown  = (dir == 2'b00);
wire forbidLeft  = (dir == 2'b01);
wire forbidRight = (dir == 2'b11);


// =====================================================================
// 1. Offset 2 tiles ahead of Pac-Man
// =====================================================================
always @(*) begin
    offsetX = pacX;
    offsetY = pacY;

    case(pacDir)
        2'b00: offsetY = pacY - 2;   // UP
        2'b10: offsetY = pacY + 2;   // DOWN
        2'b01: offsetX = pacX + 2;   // RIGHT
        2'b11: offsetX = pacX - 2;   // LEFT
    endcase
end


// =====================================================================
// 2. Compute vector from Blinky → offset and double it
// =====================================================================
always @(*) begin
    vecX = offsetX - blinkyX;
    vecY = offsetY - blinkyY;

    targetX = offsetX + vecX;
    targetY = offsetY + vecY;

    // clamp to map
    if (targetX < 0)  targetX = 0;
    if (targetY < 0)  targetY = 0;
    if (targetX > 27) targetX = 27;
    if (targetY > 35) targetY = 35;
end


// =====================================================================
// 3. Compute distances for all possible movement directions
// =====================================================================
always @(*) begin
    // default to max (blocked)
    distUp    = 8'd255;
    distDown  = 8'd255;
    distLeft  = 8'd255;
    distRight = 8'd255;

    // Up
    if (canMoveUp && !forbidUp) begin
        distUp =
            (inkyX       > targetX ? inkyX       - targetX : targetX - inkyX) +
            ((inkyY - 1) > targetY ? (inkyY - 1) - targetY : targetY - (inkyY - 1));
    end

    // Down
    if (canMoveDown && !forbidDown) begin
        distDown =
            (inkyX       > targetX ? inkyX       - targetX : targetX - inkyX) +
            ((inkyY + 1) > targetY ? (inkyY + 1) - targetY : targetY - (inkyY + 1));
    end

    // Left
    if (canMoveLeft && !forbidLeft) begin
        distLeft =
            ((inkyX - 1) > targetX ? (inkyX - 1) - targetX : targetX - (inkyX - 1)) +
            (inkyY       > targetY ? inkyY       - targetY : targetY - inkyY);
    end

    // Right
    if (canMoveRight && !forbidRight) begin
        distRight =
            ((inkyX + 1) > targetX ? (inkyX + 1) - targetX : targetX - (inkyX + 1)) +
            (inkyY       > targetY ? inkyY       - targetY : targetY - inkyY);
    end
end


// =====================================================================
// 4. Movement state update
// =====================================================================
always @(posedge clk) begin
    if (reset) begin
        inkyX <= INKY_START_TILE_X;
        inkyY <= INKY_START_TILE_Y;
        dir   <= 2'b01;  // start RIGHT
    end else begin
        // Movement disabled - Inky stays at starting position
        // choose best direction
        // if (distUp <= distDown && distUp <= distLeft && distUp <= distRight && distUp != 255)
        //     dir <= 2'b00;
        // else if (distDown <= distUp && distDown <= distLeft && distDown <= distRight && distDown != 255)
        //     dir <= 2'b10;
        // else if (distLeft <= distUp && distLeft <= distDown && distLeft <= distRight && distLeft != 255)
        //     dir <= 2'b11;
        // else if (distRight != 255)
        //     dir <= 2'b01;

        // perform movement
        // case(dir)
        //     2'b00: if (canMoveUp)    inkyY <= inkyY - 1;
        //     2'b10: if (canMoveDown)  inkyY <= inkyY + 1;
        //     2'b01: if (canMoveRight) inkyX <= inkyX + 1;
        //     2'b11: if (canMoveLeft)  inkyX <= inkyX - 1;
        // endcase
    end
end

endmodule
