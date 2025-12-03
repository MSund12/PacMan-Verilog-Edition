// Pinky (Pink Ghost): targets 4 tiles ahead of Pac-Man
module pinky(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    input  wire [5:0]  pacmanX,
    input  wire [5:0]  pacmanY,
    input  wire [1:0]  pacmanDir,

    input  wire        isChase,
    input  wire        isScatter,

    input  wire        wallUp,
    input  wire        wallDown,
    input  wire        wallLeft,
    input  wire        wallRight,

    output reg [5:0]   pinkyX,
    output reg [5:0]   pinkyY
);

// Scatter corner: top-right
localparam [5:0] CORNER_X = 27;
localparam [5:0] CORNER_Y = 0;

// Starting position
localparam [5:0] PINKY_START_TILE_X = 6'd13;
localparam [5:0] PINKY_START_TILE_Y = 6'd19;

// Exit tile from ghost house
localparam [5:0] ESCAPE_X = 6'd13;
localparam [5:0] ESCAPE_Y = 6'd16;

reg escapeDone = 0;
reg escapedShifted = 0;

// 9-second delay before starting
localparam FIVE_SEC_TICKS = 25_000_000 * 9;
reg [27:0] startDelay = 0;
reg        delayDone  = 0;

// 60Hz movement tick generator
localparam MOVE_DIV = 416_666;
reg [19:0] moveCount = 0;
reg        moveTick = 0;

// Generate 60Hz movement tick (25MHz / 416666 ≈ 60Hz)
always @(posedge clk) begin
    if (moveCount >= MOVE_DIV) begin
        moveCount <= 0;
        moveTick <= 1;
    end else begin
        moveCount <= moveCount + 1;
        moveTick <= 0;
    end
end

// Fractional speed: 5% slower than Blinky
reg [15:0] pinkyAcc;
wire [15:0] accNext = pinkyAcc + 16'd142;
wire doStep = (accNext >= 16'd1000);
wire [15:0] accAfter = doStep ? (accNext - 16'd1000) : accNext;

reg [5:0] targetX;
reg [5:0] targetY;

// Target selection: 4 tiles ahead of Pac-Man in chase mode
always @(*) begin
    if (!escapeDone) begin
        targetX = ESCAPE_X;
        targetY = ESCAPE_Y;
    end
    else if (isChase) begin
        // Target 4 tiles ahead of Pac-Man based on direction
        case (pacmanDir)
            2'b00: begin
                targetX = pacmanX;
                targetY = (pacmanY >= 4) ? pacmanY - 4 : 0;
            end
            2'b01: begin
                targetX = pacmanX;
                targetY = (pacmanY + 4 <= 35) ? pacmanY + 4 : 35;
            end
            2'b10: begin
                targetX = (pacmanX >= 4) ? pacmanX - 4 : 0;
                targetY = pacmanY;
            end
            2'b11: begin
                targetX = (pacmanX + 4 <= 27) ? pacmanX + 4 : 27;
                targetY = pacmanY;
            end
            default: begin
                targetX = pacmanX;
                targetY = pacmanY;
            end
        endcase
    end
    else if (isScatter) begin
        targetX = CORNER_X;
        targetY = CORNER_Y;
    end
    else begin
        targetX = pacmanX;
        targetY = pacmanY;
    end
end

wire canUp    = !wallUp;
wire canDown  = !wallDown;
wire canLeft  = !wallLeft;
wire canRight = !wallRight;

reg [1:0] currDir;
reg [1:0] desiredDir;
reg [1:0] reverseDir;
reg       moved;
reg       downAllowed;

localparam UP=2'b00, DOWN=2'b01, LEFT=2'b10, RIGHT=2'b11;

wire ghost_left_tunnel  = (pinkyX == 6'd0)  && (pinkyY == 6'd19);
wire ghost_right_tunnel = (pinkyX == 6'd27) && (pinkyY == 6'd19);

wire [1:0] ghost_dir = currDir;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        pinkyX <= PINKY_START_TILE_X;
        pinkyY <= PINKY_START_TILE_Y;
        currDir <= 2'b00;
        startDelay <= 0;
        delayDone <= 0;
        escapeDone <= 0;
        escapedShifted <= 0;
        pinkyAcc <= 0;
    end else begin

        // 9-second startup delay before starting movement
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else
                delayDone <= 1;
        end

        // Check if escape tile reached (tile 13, 16)
        if (!escapeDone && pinkyX == ESCAPE_X && pinkyY == ESCAPE_Y)
            escapeDone <= 1;

        // Down movement allowed: must escape first, then shift left/right, or if desired direction is not down
        downAllowed <= escapeDone && (escapedShifted || desiredDir != 2'b01);

        // Movement tick (only when enabled and delay is done)
        if (delayDone && moveTick && enable) begin
            pinkyAcc <= accAfter;

            // Move one tile when accumulator overflows
            if (doStep) begin
                moved = 0;

                // Calculate reverse direction (ghosts can't reverse)
                case (currDir)
                    2'b00: reverseDir = 2'b01;  // Up -> Down
                    2'b01: reverseDir = 2'b00;  // Down -> Up
                    2'b10: reverseDir = 2'b11;  // Left -> Right
                    2'b11: reverseDir = 2'b10;  // Right -> Left
                endcase

                // Calculate desired direction toward target
                if (targetX > pinkyX)       desiredDir = 2'b11;  // Right
                else if (targetX < pinkyX)  desiredDir = 2'b10;  // Left
                else if (targetY > pinkyY)  desiredDir = 2'b01;  // Down
                else if (targetY < pinkyY)  desiredDir = 2'b00;  // Up
                else                        desiredDir = currDir;  // Stay same if at target

                // 1. Try desired direction if not reverse
                if (!moved && desiredDir != reverseDir) begin
                    case (desiredDir)
                        2'b00: if (canUp)
                                    begin pinkyY <= pinkyY - 1; currDir <= 2'b00; moved = 1; end
                        2'b01: if (canDown && downAllowed)
                                    begin pinkyY <= pinkyY + 1; currDir <= 2'b01; moved = 1; end
                        2'b10: if (canLeft)
                                    begin pinkyX <= pinkyX - 1; currDir <= 2'b10; moved = 1; end
                        2'b11: if (canRight)
                                    begin pinkyX <= pinkyX + 1; currDir <= 2'b11; moved = 1; end
                    endcase
                end

                // Detect lateral shift after escape (left or right movement)
                if (escapeDone && !escapedShifted &&
                    (currDir == 2'b10 || currDir == 2'b11))
                    escapedShifted <= 1;  // Allow down movement now

                // 2. Continue straight if desired direction blocked
                if (!moved) begin
                    case (currDir)
                        2'b00: if (canUp) begin pinkyY <= pinkyY - 1; moved = 1; end
                        2'b01: if (canDown && downAllowed)
                                       begin pinkyY <= pinkyY + 1; moved = 1; end
                        2'b10: if (canLeft)  begin pinkyX <= pinkyX - 1; moved = 1; end
                        2'b11: if (canRight) begin pinkyX <= pinkyX + 1; moved = 1; end
                    endcase
                end

                // 3. Try any legal non-reverse direction
                if (!moved) begin
                    if (canUp    && reverseDir != 2'b00)
                        begin pinkyY <= pinkyY - 1; currDir <= 2'b00; moved = 1; end
                    else if (canDown && downAllowed && reverseDir != 2'b01)
                        begin pinkyY <= pinkyY + 1; currDir <= 2'b01; moved = 1; end
                    else if (canLeft  && reverseDir != 2'b10)
                        begin pinkyX <= pinkyX - 1; currDir <= 2'b10; moved = 1; end
                    else if (canRight && reverseDir != 2'b11)
                        begin pinkyX <= pinkyX + 1; currDir <= 2'b11; moved = 1; end
                end

                // Tunnel teleport: wrap around screen edges at row 19
                if (ghost_left_tunnel && ghost_dir == LEFT) begin
                    pinkyX <= 6'd27;  // Left tunnel -> right side
                    pinkyY <= 6'd19;
                end
                else if (ghost_right_tunnel && ghost_dir == RIGHT) begin
                    pinkyX <= 6'd0;   // Right tunnel -> left side
                    pinkyY <= 6'd19;
                end

            end
        end
    end
end

endmodule
