// Blinky (Red Ghost): chases Pac-Man directly
module blinky(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    input  wire [5:0]  pacmanX,
    input  wire [5:0]  pacmanY,

    input  wire        isChase,
    input  wire        isScatter,

    input  wire        wallUp,
    input  wire        wallDown,
    input  wire        wallLeft,
    input  wire        wallRight,

    output reg [5:0]   blinkyX,
    output reg [5:0]   blinkyY
);

// Scatter corner: top-right
localparam [5:0] CORNER_X = 27;
localparam [5:0] CORNER_Y = 0;

// Starting position
localparam [5:0] BLINKY_START_TILE_X = 6'd13;
localparam [5:0] BLINKY_START_TILE_Y = 6'd16;

reg [5:0] targetX;
reg [5:0] targetY;

// 5-second delay before starting
localparam FIVE_SEC_TICKS = 25_000_000 * 5;
reg [27:0] startDelay = 0;
reg        delayDone  = 0;

// 60Hz movement tick generator
localparam MOVE_DIV = 416_666;
reg [19:0] moveCount = 0;
reg        moveTick  = 0;

// Generate 60Hz movement tick (25MHz / 416666 ≈ 60Hz)
always @(posedge clk) begin
    if (moveCount >= MOVE_DIV) begin
        moveCount <= 0;
        moveTick  <= 1;
    end else begin
        moveCount <= moveCount + 1;
        moveTick  <= 0;
    end
end

// Target selection: chase Pac-Man or scatter to corner
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

// Fractional speed accumulator: ~0.15 tiles per frame
reg [15:0] blinkyAcc;
wire [15:0] blinkyAccNext = blinkyAcc + 16'd150;
wire blinkyStep = (blinkyAccNext >= 16'd1000);
wire [15:0] blinkyAccAfter = blinkyStep ? (blinkyAccNext - 16'd1000) : blinkyAccNext;

// Direction: 0=up, 1=down, 2=left, 3=right
reg [1:0] dir;

reg [2:0] startOffsetX;
reg [2:0] startOffsetY;

// Movement legality checks
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
        dir          <= 1;  // Start facing down
    end else begin
        // 5-second delay before starting movement
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else
                delayDone <= 1;
        end

        // Movement tick (only when enabled and delay is done)
        else if (moveTick && enable) begin
            blinkyAcc <= blinkyAccAfter;

            // Move one tile when accumulator overflows
            if (blinkyStep) begin
                // Pathfinding: try desired direction, then continue forward, then any non-reverse
                reg [1:0] desiredDir;
                reg [1:0] reverseDir;
                reg       moved;

                // Calculate reverse direction (ghosts can't reverse)
                case (dir)
                    0: reverseDir = 1;
                    1: reverseDir = 0;
                    2: reverseDir = 3;
                    3: reverseDir = 2;
                endcase

                // Calculate desired direction toward target
                if (targetX > blinkyX)       desiredDir = 3;
                else if (targetX < blinkyX)  desiredDir = 2;
                else if (targetY > blinkyY)  desiredDir = 1;
                else if (targetY < blinkyY)  desiredDir = 0;
                else                         desiredDir = dir;

                moved = 0;

                // Try desired direction if not reverse
                if (!moved && desiredDir != reverseDir) begin
                    case (desiredDir)
                        0: if (canUp)    begin blinkyY <= blinkyY - 1; dir <= 0; moved = 1; end
                        1: if (canDown)  begin blinkyY <= blinkyY + 1; dir <= 1; moved = 1; end
                        2: if (canLeft)  begin blinkyX <= blinkyX - 1; dir <= 2; moved = 1; end
                        3: if (canRight) begin blinkyX <= blinkyX + 1; dir <= 3; moved = 1; end
                    endcase
                end

                // Continue forward if desired direction blocked
                if (!moved) begin
                    case (dir)
                        0: if (canUp)    begin blinkyY <= blinkyY - 1; moved = 1; end
                        1: if (canDown)  begin blinkyY <= blinkyY + 1; moved = 1; end
                        2: if (canLeft)  begin blinkyX <= blinkyX - 1; moved = 1; end
                        3: if (canRight) begin blinkyX <= blinkyX + 1; moved = 1; end
                    endcase
                end

                // Try any legal non-reverse direction
                if (!moved) begin
                    if (canUp    && reverseDir != 0) begin blinkyY <= blinkyY - 1; dir <= 0; moved = 1; end
                    else if (canDown  && reverseDir != 1) begin blinkyY <= blinkyY + 1; dir <= 1; moved = 1; end
                    else if (canLeft  && reverseDir != 2) begin blinkyX <= blinkyX - 1; dir <= 2; moved = 1; end
                    else if (canRight && reverseDir != 3) begin blinkyX <= blinkyX + 1; dir <= 3; moved = 1; end
                end

                // Tunnel teleport: wrap around screen edges
                if (blinkyY == 6'd19) begin
                    if (blinkyX == 6'd0  && dir == 2) begin
                        blinkyX <= 6'd27;
                    end
                    else if (blinkyX == 6'd27 && dir == 3) begin
                        blinkyX <= 6'd0;
                    end
                end

                startOffsetX <= 0;
                startOffsetY <= 0;

            end
        end
    end
end

endmodule
