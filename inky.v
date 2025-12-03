// Inky (Cyan Ghost): targets position 2 tiles ahead of Pac-Man, doubled from Blinky
module inky(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    input  wire [5:0]  pacX,
    input  wire [5:0]  pacY,
    input  wire [1:0]  pacDir,

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

// Starting position
localparam [5:0] INKY_START_TILE_X = 6'd11;
localparam [5:0] INKY_START_TILE_Y = 6'd19;

// Exit tile from ghost house
localparam [5:0] ESCAPE_X = 6'd13;
localparam [5:0] ESCAPE_Y = 6'd16;

reg escapeDone = 0;

// Flag to prevent immediate downward movement after escape
reg escapedShifted = 0;

// 13-second delay before starting
localparam integer STARTUP_DELAY = 25_000_000 * 13;
reg [28:0] startupCounter = 0;
wire startupDone = (startupCounter >= STARTUP_DELAY);

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

// Fractional speed: 5% slower than Blinky
reg [15:0] inkyAcc;
wire [15:0] inkyAccNext = inkyAcc + 16'd142;
wire inkyStep = (inkyAccNext >= 16'd1000);
wire [15:0] inkyAccAfter = inkyStep ? (inkyAccNext - 16'd1000) : inkyAccNext;

// No-reverse rule: ghosts can't turn around
wire forbidUp    = (dir == 2'b10);
wire forbidDown  = (dir == 2'b00);
wire forbidLeft  = (dir == 2'b01);
wire forbidRight = (dir == 2'b11);

// Target calculation: 2 tiles ahead of Pac-Man, doubled from Blinky's position
reg signed [6:0] offsetX, offsetY;
reg signed [7:0] vecX, vecY;
reg signed [7:0] targetX, targetY;

always @(*) begin
    if (!escapeDone) begin
        targetX = ESCAPE_X;
        targetY = ESCAPE_Y;
    end
    else begin
        // Calculate offset: 2 tiles ahead of Pac-Man
        offsetX = pacX;
        offsetY = pacY;

        case (pacDir)
            2'b00: offsetY = pacY - 2;
            2'b10: offsetY = pacY + 2;
            2'b01: offsetX = pacX + 2;
            2'b11: offsetX = pacX - 2;
        endcase

        // Vector from Blinky to offset point
        vecX = offsetX - blinkyX;
        vecY = offsetY - blinkyY;

        // Double the vector: target = offset + vector
        targetX = offsetX + vecX;
        targetY = offsetY + vecY;

        // Clamp to valid tile coordinates
        if (targetX < 0)  targetX = 0;
        if (targetY < 0)  targetY = 0;
        if (targetX > 27) targetX = 27;
        if (targetY > 35) targetY = 35;
    end
end

// Distance calculation: Manhattan distance to target from each possible next position
reg [7:0] distUp, distDown, distLeft, distRight;

always @(*) begin
    // Initialize distances to maximum (255 = invalid/unreachable)
    distUp    = 255;
    distDown  = 255;
    distLeft  = 255;
    distRight = 255;

    // Calculate distance if moving up is legal and not forbidden
    if (canMoveUp && !forbidUp)
        distUp =
            (inkyX       > targetX ? inkyX       - targetX : targetX - inkyX) +
            ((inkyY - 1) > targetY ? (inkyY - 1) - targetY : targetY - (inkyY - 1));

    // Calculate distance if moving down is legal and not forbidden
    // Prevent immediate downward movement after escape (must shift left/right first)
    if (canMoveDown && !forbidDown) begin
        if (!escapeDone) begin
            // Still escaping: don't allow down
        end else if (!escapedShifted) begin
            // Just escaped: don't allow down until shifted left/right
        end else begin
            // Escaped and shifted: allow down movement
            distDown =
                (inkyX       > targetX ? inkyX       - targetX : targetX - inkyX) +
                ((inkyY + 1) > targetY ? (inkyY + 1) - targetY : targetY - (inkyY + 1));
        end
    end

    // Calculate distance if moving left is legal and not forbidden
    if (canMoveLeft && !forbidLeft)
        distLeft =
            ((inkyX - 1) > targetX ? (inkyX - 1) - targetX : targetX - (inkyX - 1)) +
            (inkyY       > targetY ? inkyY       - targetY : targetY - inkyY);

    // Calculate distance if moving right is legal and not forbidden
    if (canMoveRight && !forbidRight)
        distRight =
            ((inkyX + 1) > targetX ? (inkyX + 1) - targetX : targetX - (inkyX + 1)) +
            (inkyY       > targetY ? inkyY       - targetY : targetY - inkyY);
end

always @(posedge clk) begin
    if (reset) begin
        inkyX <= INKY_START_TILE_X;
        inkyY <= INKY_START_TILE_Y;
        dir   <= 2'b01;
        inkyAcc <= 0;
        startupCounter <= 0;
        escapeDone <= 0;
        escapedShifted <= 0;
    end else begin

        if (!startupDone)
            startupCounter <= startupCounter + 1;

        if (!escapeDone && inkyX == ESCAPE_X && inkyY == ESCAPE_Y)
            escapeDone <= 1;

        // Movement tick (only when startup delay is done and enabled)
        if (startupDone && moveTick && enable) begin
            inkyAcc <= inkyAccAfter;

            // Move one tile when accumulator overflows
            if (inkyStep) begin
                reg [1:0] nextDir;

                // Choose direction with minimum distance to target
                // Break ties: up > down > left > right
                if (distUp <= distDown &&
                    distUp <= distLeft &&
                    distUp <= distRight)
                    nextDir = 2'b00;  // Up

                else if (distDown <= distUp &&
                         distDown <= distLeft &&
                         distDown <= distRight)
                    nextDir = 2'b10;  // Down

                else if (distLeft <= distUp &&
                         distLeft <= distDown &&
                         distLeft <= distRight)
                    nextDir = 2'b11;  // Left

                else
                    nextDir = 2'b01;  // Right

                // Detect lateral shift after escape (left or right movement)
                if (escapeDone && !escapedShifted) begin
                    if (nextDir == 2'b11 || nextDir == 2'b01)
                        escapedShifted <= 1;  // Allow down movement now
                end

                dir <= nextDir;

                // Move in chosen direction
                case (nextDir)
                    2'b00: if (canMoveUp)    inkyY <= inkyY - 1;
                    2'b10: if (canMoveDown)  inkyY <= inkyY + 1;
                    2'b01: if (canMoveRight) inkyX <= inkyX + 1;
                    2'b11: if (canMoveLeft)  inkyX <= inkyX - 1;
                endcase

                // Tunnel teleport: wrap around screen edges at row 19
                if ((inkyX == 6'd0) && (inkyY == 6'd19) && (dir == 2'b11)) begin
                    inkyX <= 6'd27;  // Left tunnel -> right side
                    inkyY <= 6'd19;
                end
                else if ((inkyX == 6'd27) && (inkyY == 6'd19) && (dir == 2'b01)) begin
                    inkyX <= 6'd0;   // Right tunnel -> left side
                    inkyY <= 6'd19;
                end

            end
        end
    end
end

endmodule
