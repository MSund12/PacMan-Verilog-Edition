// Clyde (Orange Ghost): chases Pac-Man but retreats when close
module clyde(
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

    output reg [5:0]   clydeX,
    output reg [5:0]   clydeY
);

// Scatter corner: bottom-left
localparam [5:0] CORNER_X = 1;
localparam [5:0] CORNER_Y = 35;

// Circle center for proximity check
localparam [5:0] CIRCLE_CENTER_X = 14;
localparam [5:0] CIRCLE_CENTER_Y = 30;

// Check if Pac-Man is near circle center
wire signed [7:0] cdx = pacmanX - CIRCLE_CENTER_X;
wire signed [7:0] cdy = pacmanY - CIRCLE_CENTER_Y;
wire [15:0] distCircSq = cdx*cdx + cdy*cdy;
wire pacNearCircle = (distCircSq < 16'd64);

// Starting position
localparam [5:0] CLYDE_START_TILE_X = 6'd15;
localparam [5:0] CLYDE_START_TILE_Y = 6'd19;

// Exit tile from ghost house
localparam [5:0] EXIT_X = 6'd13;
localparam [5:0] EXIT_Y = 6'd16;

reg [5:0] targetX;
reg [5:0] targetY;

localparam FIVE_SEC_TICKS = 25_000_000 * 17;
reg [28:0] startDelay = 0;
reg        delayDone  = 0;

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

// Distance to Pac-Man for retreat logic
wire signed [7:0] dx = pacmanX - clydeX;
wire signed [7:0] dy = pacmanY - clydeY;
wire [15:0] distSq = dx*dx + dy*dy;
wire closeToPacman = (distSq < 16'd64);

// Target selection: chase if far, retreat to corner if close
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

// Fractional speed: 5% slower than Blinky
reg [15:0] clydeAcc;
wire [15:0] clydeAccNext  = clydeAcc + 16'd142;
wire        clydeStep     = (clydeAccNext >= 16'd1000);
wire [15:0] clydeAccAfter = clydeStep ? (clydeAccNext - 16'd1000) : clydeAccNext;

// Escape state machine: 0=wait, 1=move left, 2=move up, 3=normal AI
reg [1:0] escapeState = 0;

reg [1:0] dir;
reg [1:0] desiredDir;
reg [1:0] reverseDir;
reg       canUp, canDown, canLeft, canRight;
reg       moved;

wire leftTunnel  = (clydeX == 6'd0)  && (clydeY == 6'd19);
wire rightTunnel = (clydeX == 6'd27) && (clydeY == 6'd19);

always @(posedge clk or posedge reset) begin
    if (reset) begin
        clydeX      <= CLYDE_START_TILE_X;
        clydeY      <= CLYDE_START_TILE_Y;
        startDelay  <= 0;
        delayDone   <= 0;
        clydeAcc    <= 0;
        escapeState <= 0;  // Start in wait state
        dir         <= 0;
    end else begin
        // 17-second delay before starting (releases after Inky)
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else begin
                delayDone   <= 1;
                escapeState <= 1;  // Move to escape state
            end
        end

        // Movement tick (only when enabled and delay is done)
        else if (moveTick && enable) begin
            clydeAcc <= clydeAccAfter;

            // Move one tile when accumulator overflows
            if (clydeStep) begin
                case (escapeState)

                // STATE 1: Move LEFT to exit X tile (tile 13)
                1: begin
                    if (clydeX > EXIT_X) begin
                        if (!wallLeft) begin
                            clydeX <= clydeX - 1;
                            dir <= 2;  // Left
                        end
                    end else begin
                        escapeState <= 2;  // Move to next escape state
                    end
                end

                // STATE 2: Move UP to exit Y tile (tile 16)
                2: begin
                    if (clydeY > EXIT_Y) begin
                        if (!wallUp) begin
                            clydeY <= clydeY - 1;
                            dir <= 0;  // Up
                        end
                    end else begin
                        escapeState <= 3;  // Move to normal AI state
                    end
                end

                // STATE 3: Normal Clyde AI (chase/retreat behavior)
                3: begin
                    // Calculate desired direction toward target
                    if (targetX > clydeX)
                        desiredDir = 3;  // Right
                    else if (targetX < clydeX)
                        desiredDir = 2;  // Left
                    else if (targetY > clydeY)
                        desiredDir = 1;  // Down
                    else
                        desiredDir = 0;  // Up

                    // Calculate reverse direction (ghosts can't reverse)
                    case (dir)
                        0: reverseDir = 1;  // Up -> Down
                        1: reverseDir = 0;  // Down -> Up
                        2: reverseDir = 3;  // Left -> Right
                        3: reverseDir = 2;  // Right -> Left
                    endcase

                    // Check which directions are legal (no walls)
                    canUp    = !wallUp;
                    canDown  = !wallDown;
                    canLeft  = !wallLeft;
                    canRight = !wallRight;

                    moved = 0;

                    // 1. Try desired direction if not reverse
                    if (!moved && desiredDir != reverseDir) begin
                        case (desiredDir)
                            0: if (canUp)    begin clydeY <= clydeY - 1; dir <= 0; moved = 1; end
                            1: if (canDown)  begin clydeY <= clydeY + 1; dir <= 1; moved = 1; end
                            2: if (canLeft)  begin clydeX <= clydeX - 1; dir <= 2; moved = 1; end
                            3: if (canRight) begin clydeX <= clydeX + 1; dir <= 3; moved = 1; end
                        endcase
                    end

                    // 2. Continue straight if desired direction blocked
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
                end
                endcase

                // Tunnel teleport: wrap around screen edges at row 19
                if (leftTunnel && dir == 2) begin
                    clydeX <= 6'd27;  // Left tunnel -> right side
                    clydeY <= 6'd19;
                end
                else if (rightTunnel && dir == 3) begin
                    clydeX <= 6'd0;   // Right tunnel -> left side
                    clydeY <= 6'd19;
                end

            end
        end
    end
end

endmodule
