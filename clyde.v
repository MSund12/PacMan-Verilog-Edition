module clyde(
    input  wire        clk,
    input  wire        reset,

    input  wire [5:0]  pacmanX,
    input  wire [5:0]  pacmanY,

    input  wire        isChase,
    input  wire        isScatter,

    input  wire        wallUp,
    input  wire        wallDown,
    input  wire        wallLeft,
    input  wire        wallRight,

    output reg [5:0]   clydeX,
    output reg [5:0]   clydeY
);

// =======================================================
// Scatter corner
// =======================================================
localparam [5:0] CORNER_X = 1;
localparam [5:0] CORNER_Y = 35;

// =======================================================
// Clyde’s circular patrol center (YOU MAY EDIT THIS)
// =======================================================
localparam [5:0] CIRCLE_CENTER_X = 14;
localparam [5:0] CIRCLE_CENTER_Y = 30;

// Pacman distance to patrol center
wire signed [7:0] cdx = pacmanX - CIRCLE_CENTER_X;
wire signed [7:0] cdy = pacmanY - CIRCLE_CENTER_Y;
wire [15:0] distCircSq = cdx*cdx + cdy*cdy;
wire pacNearCircle = (distCircSq < 16'd64);   // < 8 tiles

// =======================================================
// Spawn pixel → tile conversion
// =======================================================
localparam IMG_X0 = 208;
localparam IMG_Y0 = 96;
localparam TILE_W = 8;
localparam TILE_H = 8;

localparam CLYDE_START_X_PIX = IMG_X0 + 13*TILE_W + 4 + 3;
localparam CLYDE_START_Y_PIX = IMG_Y0 + 17*TILE_H + 4 + 9;

localparam [5:0] CLYDE_START_TILE_X = (CLYDE_START_X_PIX - IMG_X0) / TILE_W;
localparam [5:0] CLYDE_START_TILE_Y = (CLYDE_START_Y_PIX - IMG_Y0) / TILE_H;

localparam [2:0] CLYDE_OFFSET_X = (CLYDE_START_X_PIX - IMG_X0) % TILE_W;
localparam [2:0] CLYDE_OFFSET_Y = (CLYDE_START_Y_PIX - IMG_Y0) % TILE_H;

// =======================================================
// Target registers
// =======================================================
reg [5:0] targetX;
reg [5:0] targetY;

// =======================================================
// 5-second delay
// =======================================================
localparam FIVE_SEC_TICKS = 25_000_000 * 5;
reg [27:0] startDelay = 0;
reg        delayDone  = 0;

// =======================================================
// 60 Hz move tick
// =======================================================
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

// =======================================================
// Distance to pacman
// =======================================================
wire signed [7:0] dx = pacmanX - clydeX;
wire signed [7:0] dy = pacmanY - clydeY;

wire [15:0] distSq = dx*dx + dy*dy;
wire closeToPacman = (distSq < 16'd64);

// =======================================================
// Updated Target Selection
// =======================================================
always @(*) begin

    // NEW RULE:
    // If Pac-Man is near Clyde’s circle → override everything and chase Pac-Man
    if (pacNearCircle) begin
        targetX = pacmanX;
        targetY = pacmanY;
    end

    // Scatter mode
    else if (isScatter) begin
        targetX = CORNER_X;
        targetY = CORNER_Y;
    end

    // Chase mode
    else begin
        if (closeToPacman) begin
            targetX = CORNER_X;
            targetY = CORNER_Y;
        end else begin
            targetX = pacmanX;
            targetY = pacmanY;
        end
    end
end

// =======================================================
// Speed accumulator
// =======================================================
reg [15:0] clydeAcc;
wire [15:0] clydeAccNext  = clydeAcc + 16'd150;
wire        clydeStep     = (clydeAccNext >= 16'd1000);
wire [15:0] clydeAccAfter = clydeStep ? (clydeAccNext - 16'd1000) : clydeAccNext;

// =======================================================
// Movement state
// =======================================================
reg [1:0] escapeState = 0;
reg [1:0] dir;

reg [1:0] desiredDir;
reg [1:0] reverseDir;

reg canUp, canDown, canLeft, canRight;
reg moved;

reg [2:0] startOffsetX;
reg [2:0] startOffsetY;

// =======================================================
// MAIN
// =======================================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        clydeX      <= CLYDE_START_TILE_X;
        clydeY      <= CLYDE_START_TILE_Y;
        startOffsetX <= CLYDE_OFFSET_X;
        startOffsetY <= CLYDE_OFFSET_Y;

        startDelay   <= 0;
        delayDone    <= 0;
        clydeAcc     <= 0;

        escapeState  <= 0;
        dir          <= 0;
    end 
    else begin

        // 5-second wait
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else begin
                delayDone   <= 1;
                escapeState <= 1;
            end
        end
        
        else if (moveTick) begin
            clydeAcc <= clydeAccAfter;

            if (clydeStep) begin
                case (escapeState)

                // ====================================================
                // STEP 1 — Move straight upward out of ghost house
                // ====================================================
                1: begin
                    if (!wallUp)
                        clydeY <= clydeY - 1;
                    else
                        escapeState <= 2;

                    startOffsetX <= 0;
                    startOffsetY <= 0;
                end

                // ====================================================
                // STEP 2 — NORMAL AI (with circle-target override)
                // ====================================================
                2: begin

                    // Determine desired direction
                    if (targetX > clydeX)
                        desiredDir = 3;
                    else if (targetX < clydeX)
                        desiredDir = 2;
                    else if (targetY > clydeY)
                        desiredDir = 1;
                    else
                        desiredDir = 0;

                    case (dir)
                        0: reverseDir = 1;
                        1: reverseDir = 0;
                        2: reverseDir = 3;
                        3: reverseDir = 2;
                    endcase

                    canUp    = !wallUp;
                    canDown  = !wallDown;
                    canLeft  = !wallLeft;
                    canRight = !wallRight;

                    moved = 0;

                    // 1. Try desired direction
                    if (!moved && desiredDir != reverseDir) begin
                        case (desiredDir)
                            0: if (canUp)    begin clydeY <= clydeY - 1; dir <= 0; moved = 1; end
                            1: if (canDown)  begin clydeY <= clydeY + 1; dir <= 1; moved = 1; end
                            2: if (canLeft)  begin clydeX <= clydeX - 1; dir <= 2; moved = 1; end
                            3: if (canRight) begin clydeX <= clydeX + 1; dir <= 3; moved = 1; end
                        endcase
                    end

                    // 2. Keep moving forward
                    if (!moved) begin
                        case (dir)
                            0: if (canUp)    begin clydeY <= clydeY - 1; moved = 1; end
                            1: if (canDown)  begin clydeY <= clydeY + 1; moved = 1; end
                            2: if (canLeft)  begin clydeX <= clydeX - 1; moved = 1; end
                            3: if (canRight) begin clydeX <= clydeX + 1; moved = 1; end
                        endcase
                    end

                    // 3. Try any legal non-reverse direction
                    if (!moved) begin
                        if (canUp    && reverseDir != 0) begin clydeY <= clydeY - 1; dir <= 0; moved = 1; end
                        else if (canDown  && reverseDir != 1) begin clydeY <= clydeY + 1; dir <= 1; moved = 1; end
                        else if (canLeft  && reverseDir != 2) begin clydeX <= clydeX - 1; dir <= 2; moved = 1; end
                        else if (canRight && reverseDir != 3) begin clydeX <= clydeX + 1; dir <= 3; moved = 1; end
                    end

                    startOffsetX <= 0;
                    startOffsetY <= 0;
                end

                endcase
            end
        end
    end
end

endmodule