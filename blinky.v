module blinky(
    input  wire        clk,
    input  wire        rst_n,       // active-low reset
    input  wire        frame_tick,  // Move once per frame

    input  wire [5:0]  pacmanX,   // pacman tile X (0..27)
    input  wire [5:0]  pacmanY,   // pacman tile Y (0..35)

    input  wire        isChase,
    input  wire        isScatter,

    // Now tile-based wall indicators, already provided by Pac-Man code
    input  wire        wallUp,
    input  wire        wallDown,
    input  wire        wallLeft,
    input  wire        wallRight,

    output reg [5:0]   blinkyX,   // tile X (0..27)
    output reg [5:0]   blinkyY    // tile Y (0..35)
);

/* 
Blinky (Red Ghost)
Chase mode: target Pac-Man
Scatter mode: target top-right corner
*/

// -------------------------------------------------------
// Blinky’s scatter corner
// -------------------------------------------------------
localparam [5:0] CORNER_X = 27;
localparam [5:0] CORNER_Y = 0;

// -------------------------------------------------------
// Pixel-based starting position
// Arcade spawn: center of tile + vertical adjustment
localparam IMG_X0 = 208;
localparam IMG_Y0 = 96;
localparam TILE_W = 8;
localparam TILE_H = 8;

// Add 9 pixels downward to Y
localparam BLINKY_START_X_PIX = IMG_X0 + 13*TILE_W + 4 + 3;  // X=13 center
localparam BLINKY_START_Y_PIX = IMG_Y0 + 14*TILE_H + 4 + 19;  // Y=14 center + 9 pixels down

// Convert pixel to tile for initial position
localparam [5:0] BLINKY_START_TILE_X = (BLINKY_START_X_PIX - IMG_X0) / TILE_W;
localparam [5:0] BLINKY_START_TILE_Y = (BLINKY_START_Y_PIX - IMG_Y0) / TILE_H;

// Pixel offset inside tile
localparam [2:0] BLINKY_OFFSET_X = (BLINKY_START_X_PIX - IMG_X0) % TILE_W;
localparam [2:0] BLINKY_OFFSET_Y = (BLINKY_START_Y_PIX - IMG_Y0) % TILE_H;


// -------------------------------------------------------
// Target position
// -------------------------------------------------------
reg [5:0] targetX;
reg [5:0] targetY;

// -------------------------------------------------------
// 5-second start delay (25 MHz clock)
// -------------------------------------------------------
localparam FIVE_SEC_TICKS = 25_000_000 * 5;
reg [27:0] startDelay = 0;
reg        delayDone  = 0;

// -------------------------------------------------------
// 60 Hz movement tick generator
// 25,000,000 / 60 ≈ 416,666 cycles
// -------------------------------------------------------
localparam MOVE_DIV = 416_666;
reg [19:0] moveCount = 0;
reg        moveTick  = 0;

always @(posedge clk) begin
    if (moveCount >= MOVE_DIV) begin
        moveCount <= 0;
        moveTick  <= 1;
    end else begin
        moveCount <= moveCount + 1;
        moveTick  <= 0;
    end
end

// -------------------------------------------------------
// Target selection logic
// -------------------------------------------------------
always @(*) begin
    if (isChase) begin
        targetX = pacmanX;
        targetY = pacmanY;
    end else if (isScatter) begin
        targetX = CORNER_X;
        targetY = CORNER_Y;
    end else begin
        targetX = pacmanX;
        targetY = pacmanY;
    end
end

// -------------------------------------------------------
// Blinky fractional speed accumulator (~0.15 tiles/frame, 95% Pac-Man)
// -------------------------------------------------------
reg [15:0] blinkyAcc;
wire [15:0] blinkyAccNext = blinkyAcc + 16'd150;
wire blinkyStep = (blinkyAccNext >= 16'd1000);
wire [15:0] blinkyAccAfter = blinkyStep ? (blinkyAccNext - 16'd1000) : blinkyAccNext;

// -------------------------------------------------------
// Blinky Tile-Based Movement (60 Hz)
// -------------------------------------------------------
reg [2:0] startOffsetX;
reg [2:0] startOffsetY;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        blinkyX      <= BLINKY_START_TILE_X;
        blinkyY      <= BLINKY_START_TILE_Y;
        startOffsetX <= BLINKY_OFFSET_X;
        startOffsetY <= BLINKY_OFFSET_Y;
        startDelay   <= 0;
        delayDone    <= 0;
        blinkyAcc    <= 0;
    end else begin
        // 5-second spawn delay
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else
                delayDone <= 1;
        end
        // Move at 60 Hz after delay
        else if (moveTick) begin
            blinkyAcc <= blinkyAccAfter;

            if (blinkyStep) begin
                // Horizontal priority
                if (targetX > blinkyX && !wallRight)
                    blinkyX <= blinkyX + 1;
                else if (targetX < blinkyX && !wallLeft)
                    blinkyX <= blinkyX - 1;
                // Vertical priority if horizontal blocked
                else if (targetY > blinkyY && !wallDown)
                    blinkyY <= blinkyY + 1;
                else if (targetY < blinkyY && !wallUp)
                    blinkyY <= blinkyY - 1;

                // Clear start pixel offset after first move
                startOffsetX <= 0;
                startOffsetY <= 0;
            end
        end
    end
end

endmodule
