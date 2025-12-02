module blinky(
    input  wire        clk,
    input  wire        reset,

    input  wire [5:0]  pacmanX,   // pacman tile X (0..27)
    input  wire [5:0]  pacmanY,   // pacman tile Y (0..35)

    input  wire        isChase,
    input  wire        isScatter,

    // Tile-based wall indicators
    input  wire        wallUp,
    input  wire        wallDown,
    input  wire        wallLeft,
    input  wire        wallRight,

    output reg [5:0]   blinkyX,   // tile X (0..27)
    output reg [5:0]   blinkyY    // tile Y (0..35)
);

// -------------------------------------------------------
// Scatter corner
// -------------------------------------------------------
localparam [5:0] CORNER_X = 27;
localparam [5:0] CORNER_Y = 0;

// -------------------------------------------------------
// Start tile
// -------------------------------------------------------
localparam [5:0] BLINKY_START_TILE_X = 6'd13;
localparam [5:0] BLINKY_START_TILE_Y = 6'd16;

// -------------------------------------------------------
// Target position
// -------------------------------------------------------
reg [5:0] targetX;
reg [5:0] targetY;

// -------------------------------------------------------
// 5-second start delay
// -------------------------------------------------------
localparam FIVE_SEC_TICKS = 25_000_000 * 5;
reg [27:0] startDelay = 0;
reg        delayDone  = 0;

// -------------------------------------------------------
// 60 Hz movement tick
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
// Target selection
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
// Fractional speed (~0.15 tiles/frame)
// -------------------------------------------------------
reg [15:0] blinkyAcc;
wire [15:0] blinkyAccNext = blinkyAcc + 16'd150;
wire blinkyStep = (blinkyAccNext >= 16'd1000);
wire [15:0] blinkyAccAfter = blinkyStep ? (blinkyAccNext - 16'd1000) : blinkyAccNext;

// -------------------------------------------------------
// Direction registers
// 0=up, 1=down, 2=left, 3=right
// -------------------------------------------------------
reg [1:0] dir;

reg [2:0] startOffsetX;
reg [2:0] startOffsetY;

// Legal movement flags
wire canUp    = !wallUp;
wire canDown  = !wallDown;
wire canLeft  = !wallLeft;
wire canRight = !wallRight;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        blinkyX      <= BLINKY_START_TILE_X;
        blinkyY      <= BLINKY_START_TILE_Y;
        startDelay   <= 0;
        delayDone    <= 0;
        blinkyAcc    <= 0;
        dir          <= 1;  // start facing down
    end else begin

        // 5-second delay
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else
                delayDone <= 1;
        end

        // Movement tick
        else if (moveTick) begin
            blinkyAcc <= blinkyAccAfter;

            if (blinkyStep) begin

                // ---------------------------------------------------
                // Clyde-style directional logic
                // ---------------------------------------------------

                reg [1:0] desiredDir;
                reg [1:0] reverseDir;
                reg       moved;

                // Compute reverse direction
                case (dir)
                    0: reverseDir = 1;
                    1: reverseDir = 0;
                    2: reverseDir = 3;
                    3: reverseDir = 2;
                endcase

                // Desired direction based on target
                if (targetX > blinkyX)       desiredDir = 3; // right
                else if (targetX < blinkyX)  desiredDir = 2; // left
                else if (targetY > blinkyY)  desiredDir = 1; // down
                else if (targetY < blinkyY)  desiredDir = 0; // up
                else                         desiredDir = dir;

                moved = 0;

                // 1. Try desired direction (not reverse)
                if (!moved && desiredDir != reverseDir) begin
                    case (desiredDir)
                        0: if (canUp)    begin blinkyY <= blinkyY - 1; dir <= 0; moved = 1; end
                        1: if (canDown)  begin blinkyY <= blinkyY + 1; dir <= 1; moved = 1; end
                        2: if (canLeft)  begin blinkyX <= blinkyX - 1; dir <= 2; moved = 1; end
                        3: if (canRight) begin blinkyX <= blinkyX + 1; dir <= 3; moved = 1; end
                    endcase
                end

                // 2. Keep moving forward
                if (!moved) begin
                    case (dir)
                        0: if (canUp)    begin blinkyY <= blinkyY - 1; moved = 1; end
                        1: if (canDown)  begin blinkyY <= blinkyY + 1; moved = 1; end
                        2: if (canLeft)  begin blinkyX <= blinkyX - 1; moved = 1; end
                        3: if (canRight) begin blinkyX <= blinkyX + 1; moved = 1; end
                    endcase
                end

                // 3. Try any legal non-reverse direction
                if (!moved) begin
                    if (canUp    && reverseDir != 0) begin blinkyY <= blinkyY - 1; dir <= 0; moved = 1; end
                    else if (canDown  && reverseDir != 1) begin blinkyY <= blinkyY + 1; dir <= 1; moved = 1; end
                    else if (canLeft  && reverseDir != 2) begin blinkyX <= blinkyX - 1; dir <= 2; moved = 1; end
                    else if (canRight && reverseDir != 3) begin blinkyX <= blinkyX + 1; dir <= 3; moved = 1; end
                end

                // ---------------------------------------------------
                // 🔵 TUNNEL TELEPORT LOGIC (ADDED HERE)
                // ---------------------------------------------------
                if (blinkyY == 6'd19) begin
                    if (blinkyX == 6'd0  && dir == 2) begin
                        // entering left tunnel going left → exit right side
                        blinkyX <= 6'd27;
                    end
                    else if (blinkyX == 6'd27 && dir == 3) begin
                        // entering right tunnel going right → exit left side
                        blinkyX <= 6'd0;
                    end
                end
                // ---------------------------------------------------

                startOffsetX <= 0;
                startOffsetY <= 0;

            end // blinkyStep
        end // moveTick
    end // not reset
end // always

endmodule
