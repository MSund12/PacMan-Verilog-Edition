module clyde(
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

    output reg [5:0]   clydeX,    // tile X (0..27)
    output reg [5:0]   clydeY     // tile Y (0..35)
);

/*
Clyde (Orange Ghost)

Chase mode:
    - Compute Euclidean distance to Pac-Man
    - If distance >= 8 tiles → target Pac-Man (like Blinky)
    - If distance < 8 tiles → target scatter corner

Scatter mode:
    - Bottom-left corner

This is identical logic to Pac-Man Dossier.
*/

// -------------------------------------------------------
// Clyde’s scatter corner (bottom-left)
// -------------------------------------------------------
localparam [5:0] CORNER_X = 0;
localparam [5:0] CORNER_Y = 35;

// -------------------------------------------------------
// Arcade starting pixel position (same structure as Blinky)
// -------------------------------------------------------
localparam IMG_X0 = 208;
localparam IMG_Y0 = 96;
localparam TILE_W = 8;
localparam TILE_H = 8;

// Clyde starts lower in the ghost house (Y=17)
localparam CLYDE_START_X_PIX = IMG_X0 + 13*TILE_W + 4 + 3;   // X=13 center
localparam CLYDE_START_Y_PIX = IMG_Y0 + 17*TILE_H + 4 + 9;   // Y=17 center + 9px

localparam [5:0] CLYDE_START_TILE_X = (CLYDE_START_X_PIX - IMG_X0) / TILE_W;
localparam [5:0] CLYDE_START_TILE_Y = (CLYDE_START_Y_PIX - IMG_Y0) / TILE_H;

localparam [2:0] CLYDE_OFFSET_X = (CLYDE_START_X_PIX - IMG_X0) % TILE_W;
localparam [2:0] CLYDE_OFFSET_Y = (CLYDE_START_Y_PIX - IMG_Y0) % TILE_H;

// -------------------------------------------------------
// Target tile
// -------------------------------------------------------
reg [5:0] targetX;
reg [5:0] targetY;

// -------------------------------------------------------
// 5-second delay (25 MHz clock)
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
// Compute Euclidean distance for Clyde
// Use squared distance to avoid sqrt()
// dist² = dx² + dy²
// Compare with 8 tiles → 8² = 64
// -------------------------------------------------------
wire signed [7:0] dx = pacmanX - clydeX;
wire signed [7:0] dy = pacmanY - clydeY;

wire [15:0] distSq = dx*dx + dy*dy;
wire closeToPacman = (distSq < 16'd64);  // < 8 tiles

// -------------------------------------------------------
// Clyde targeting logic
// -------------------------------------------------------
always @(*) begin
    if (isScatter) begin
        targetX = CORNER_X;
        targetY = CORNER_Y;
    end 
    else if (isChase) begin
        if (closeToPacman) begin
            // Target scatter corner if pacman < 8 tiles away
            targetX = CORNER_X;
            targetY = CORNER_Y;
        end else begin
            // Normal chase (like Blinky)
            targetX = pacmanX;
            targetY = pacmanY;
        end
    end 
    else begin
        // Default to chase behavior
        if (closeToPacman) begin
            targetX = CORNER_X;
            targetY = CORNER_Y;
        end else begin
            targetX = pacmanX;
            targetY = pacmanY;
        end
    end
end

// -------------------------------------------------------
// Clyde speed accumulator (same as Blinky)
// -------------------------------------------------------
reg [15:0] clydeAcc;
wire [15:0] clydeAccNext = clydeAcc + 16'd150;
wire clydeStep = (clydeAccNext >= 16'd1000);
wire [15:0] clydeAccAfter = clydeStep ? (clydeAccNext - 16'd1000) : clydeAccNext;

// -------------------------------------------------------
// Clyde tile-based movement
// -------------------------------------------------------
reg [2:0] startOffsetX;
reg [2:0] startOffsetY;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        clydeX      <= CLYDE_START_TILE_X;
        clydeY      <= CLYDE_START_TILE_Y;
        startOffsetX <= CLYDE_OFFSET_X;
        startOffsetY <= CLYDE_OFFSET_Y;

        startDelay   <= 0;
        delayDone    <= 0;
        clydeAcc     <= 0;
    end else begin
        // 5-second spawn lock
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else
                delayDone <= 1;
        end
        else if (moveTick) begin
            clydeAcc <= clydeAccAfter;

            if (clydeStep) begin
                // Horizontal-first pathing (same as Blinky)
                if (targetX > clydeX && !wallRight)
                    clydeX <= clydeX + 1;
                else if (targetX < clydeX && !wallLeft)
                    clydeX <= clydeX - 1;
                else if (targetY > clydeY && !wallDown)
                    clydeY <= clydeY + 1;
                else if (targetY < clydeY && !wallUp)
                    clydeY <= clydeY - 1;

                // Clear pixel offsets after leaving spawn
                startOffsetX <= 0;
                startOffsetY <= 0;
            end
        end
    end
end

endmodule
