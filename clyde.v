module clyde(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,   // Enable movement (active high)

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
// Clyde’s circle center
// =======================================================
localparam [5:0] CIRCLE_CENTER_X = 14;
localparam [5:0] CIRCLE_CENTER_Y = 30;

wire signed [7:0] cdx = pacmanX - CIRCLE_CENTER_X;
wire signed [7:0] cdy = pacmanY - CIRCLE_CENTER_Y;
wire [15:0] distCircSq = cdx*cdx + cdy*cdy;
wire pacNearCircle = (distCircSq < 16'd64); // within 8 tiles

// =======================================================
// Clyde starting
// =======================================================
localparam [5:0] CLYDE_START_TILE_X = 6'd15;
localparam [5:0] CLYDE_START_TILE_Y = 6'd19;

// Exit tile
localparam [5:0] EXIT_X = 6'd13;
localparam [5:0] EXIT_Y = 6'd16;

// =======================================================
// Target registers
// =======================================================
reg [5:0] targetX;
reg [5:0] targetY;

// =======================================================
// Clyde releases 4 seconds after Inky (17 seconds total: 13 + 4)
// =======================================================
localparam FIVE_SEC_TICKS = 25_000_000 * 17;  // 17 seconds delay
reg [28:0] startDelay = 0;  // Increased to 29 bits to hold 425,000,000
reg        delayDone  = 0;

// =======================================================
// 60Hz move tick
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
// Distance to Pac-Man
// =======================================================
wire signed [7:0] dx = pacmanX - clydeX;
wire signed [7:0] dy = pacmanY - clydeY;
wire [15:0] distSq = dx*dx + dy*dy;
wire closeToPacman = (distSq < 16'd64);

// =======================================================
// Target selection
// =======================================================
always @(*) begin
    if (pacNearCircle) begin
        targetX = pacmanX;
        targetY = pacmanY;
    end else if (isScatter) begin
        targetX = CORNER_X;
        targetY = CORNER_Y;
    end else begin
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
// Speed accumulator (5% slower than Blinky: 150 * 0.95 = 142.5, rounded to 142)
// =======================================================
reg [15:0] clydeAcc;
wire [15:0] clydeAccNext  = clydeAcc + 16'd142;
wire        clydeStep     = (clydeAccNext >= 16'd1000);
wire [15:0] clydeAccAfter = clydeStep ? (clydeAccNext - 16'd1000) : clydeAccNext;

// =======================================================
// Escape state machine
// =======================================================
// 0 = wait 5 sec
// 1 = move LEFT to EXIT_X
// 2 = move UP to EXIT_Y
// 3 = normal AI
reg [1:0] escapeState = 0;

reg [1:0] dir;
reg [1:0] desiredDir;
reg [1:0] reverseDir;
reg       canUp, canDown, canLeft, canRight;
reg       moved;

// =======================================================
// Tunnel wires — MOVED OUTSIDE ALWAYS BLOCK
// =======================================================
wire leftTunnel  = (clydeX == 6'd0)  && (clydeY == 6'd19);
wire rightTunnel = (clydeX == 6'd27) && (clydeY == 6'd19);

// =======================================================
// MAIN BLOCK
// =======================================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        clydeX      <= CLYDE_START_TILE_X;
        clydeY      <= CLYDE_START_TILE_Y;
        startDelay  <= 0;
        delayDone   <= 0;
        clydeAcc    <= 0;
        escapeState <= 0;
        dir         <= 0;
    end else begin

        // -------------------------------
        // 5 second wait
        // -------------------------------
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else begin
                delayDone   <= 1;
                escapeState <= 1;
            end
        end

        else if (moveTick && enable) begin
            clydeAcc <= clydeAccAfter;

            if (clydeStep) begin
                case (escapeState)

                // -----------------------------------------------
                // STATE 1 — Move LEFT to exit X tile
                // -----------------------------------------------
                1: begin
                    if (clydeX > EXIT_X) begin
                        if (!wallLeft) begin
                            clydeX <= clydeX - 1;
                            dir <= 2;
                        end
                    end else begin
                        escapeState <= 2;
                    end
                end

                // -----------------------------------------------
                // STATE 2 — Move UP to exit Y tile
                // -----------------------------------------------
                2: begin
                    if (clydeY > EXIT_Y) begin
                        if (!wallUp) begin
                            clydeY <= clydeY - 1;
                            dir <= 0;
                        end
                    end else begin
                        escapeState <= 3;
                    end
                end

                // -----------------------------------------------
                // STATE 3 — Normal Clyde AI
                // -----------------------------------------------
                3: begin

                    // Desired direction based on target
                    if (targetX > clydeX)
                        desiredDir = 3;
                    else if (targetX < clydeX)
                        desiredDir = 2;
                    else if (targetY > clydeY)
                        desiredDir = 1;
                    else
                        desiredDir = 0;

                    // Reverse direction
                    case (dir)
                        0: reverseDir = 1;
                        1: reverseDir = 0;
                        2: reverseDir = 3;
                        3: reverseDir = 2;
                    endcase

                    // Wall checks
                    canUp    = !wallUp;
                    canDown  = !wallDown;
                    canLeft  = !wallLeft;
                    canRight = !wallRight;

                    moved = 0;

                    // Try desired direction
                    if (!moved && desiredDir != reverseDir) begin
                        case (desiredDir)
                            0: if (canUp)    begin clydeY <= clydeY - 1; dir <= 0; moved = 1; end
                            1: if (canDown)  begin clydeY <= clydeY + 1; dir <= 1; moved = 1; end
                            2: if (canLeft)  begin clydeX <= clydeX - 1; dir <= 2; moved = 1; end
                            3: if (canRight) begin clydeX <= clydeX + 1; dir <= 3; moved = 1; end
                        endcase
                    end

                    // Continue straight if desired failed
                    if (!moved) begin
                        case (dir)
                            0: if (canUp)    begin clydeY <= clydeY - 1; moved = 1; end
                            1: if (canDown)  begin clydeY <= clydeY + 1; moved = 1; end
                            2: if (canLeft)  begin clydeX <= clydeX - 1; moved = 1; end
                            3: if (canRight) begin clydeX <= clydeX + 1; moved = 1; end
                        endcase
                    end

                    // Try any non-reverse direction
                    if (!moved) begin
                        if (canUp    && reverseDir != 0) begin clydeY <= clydeY - 1; dir <= 0; moved = 1; end
                        else if (canDown  && reverseDir != 1) begin clydeY <= clydeY + 1; dir <= 1; moved = 1; end
                        else if (canLeft  && reverseDir != 2) begin clydeX <= clydeX - 1; dir <= 2; moved = 1; end
                        else if (canRight && reverseDir != 3) begin clydeX <= clydeX + 1; dir <= 3; moved = 1; end
                    end
                end
                endcase

                // -----------------------------------------------
                // Tunnel teleport (AFTER MOVEMENT)
                // -----------------------------------------------
                if (leftTunnel && dir == 2) begin
                    clydeX <= 6'd27;
                    clydeY <= 6'd19;
                end
                else if (rightTunnel && dir == 3) begin
                    clydeX <= 6'd0;
                    clydeY <= 6'd19;
                end

            end
        end
    end
end

endmodule
