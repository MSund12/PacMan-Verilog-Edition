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
// Starting tile
// =======================================================
localparam [5:0] INKY_START_TILE_X = 6'd11;
localparam [5:0] INKY_START_TILE_Y = 6'd19;

// =======================================================
// Escape target tile (path out of ghost box)
// =======================================================
localparam [5:0] ESCAPE_X = 6'd13;
localparam [5:0] ESCAPE_Y = 6'd16;

reg escapeDone = 0;

// NEW FLAG — allows down movement after shifting L/R once after escape
reg escapedShifted = 0;

// =======================================================
// Inky releases 4 seconds after Pinky
// =======================================================
localparam integer STARTUP_DELAY = 25_000_000 * 4;  // 4 seconds delay
reg [26:0] startupCounter = 0;
wire startupDone = (startupCounter >= STARTUP_DELAY);

// =======================================================
// Movement tick generator (60 Hz)
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

// Fractional speed (5% slower than Blinky: 150 * 0.95 = 142.5, rounded to 142)
reg [15:0] inkyAcc;
wire [15:0] inkyAccNext = inkyAcc + 16'd142;
wire inkyStep = (inkyAccNext >= 16'd1000);
wire [15:0] inkyAccAfter = inkyStep ? (inkyAccNext - 16'd1000) : inkyAccNext;

// =======================================================
// No-reverse rules
// =======================================================
wire forbidUp    = (dir == 2'b10);
wire forbidDown  = (dir == 2'b00);
wire forbidLeft  = (dir == 2'b01);
wire forbidRight = (dir == 2'b11);

// =======================================================
// Target selection
// =======================================================
reg signed [6:0] offsetX, offsetY;
reg signed [7:0] vecX, vecY;
reg signed [7:0] targetX, targetY;

always @(*) begin
    if (!escapeDone) begin
        targetX = ESCAPE_X;
        targetY = ESCAPE_Y;
    end
    else begin
        offsetX = pacX;
        offsetY = pacY;

        case (pacDir)
            2'b00: offsetY = pacY - 2;
            2'b10: offsetY = pacY + 2;
            2'b01: offsetX = pacX + 2;
            2'b11: offsetX = pacX - 2;
        endcase

        vecX = offsetX - blinkyX;
        vecY = offsetY - blinkyY;

        targetX = offsetX + vecX;
        targetY = offsetY + vecY;

        if (targetX < 0)  targetX = 0;
        if (targetY < 0)  targetY = 0;
        if (targetX > 27) targetX = 27;
        if (targetY > 35) targetY = 35;
    end
end

// =======================================================
// Distance calculation
// =======================================================
reg [7:0] distUp, distDown, distLeft, distRight;

always @(*) begin
    distUp    = 255;
    distDown  = 255;
    distLeft  = 255;
    distRight = 255;

    if (canMoveUp && !forbidUp)
        distUp =
            (inkyX       > targetX ? inkyX       - targetX : targetX - inkyX) +
            ((inkyY - 1) > targetY ? (inkyY - 1) - targetY : targetY - (inkyY - 1));

    if (canMoveDown && !forbidDown) begin
        if (!escapeDone) begin
        end else if (!escapedShifted) begin
        end else begin
            distDown =
                (inkyX       > targetX ? inkyX       - targetX : targetX - inkyX) +
                ((inkyY + 1) > targetY ? (inkyY + 1) - targetY : targetY - (inkyY + 1));
        end
    end

    if (canMoveLeft && !forbidLeft)
        distLeft =
            ((inkyX - 1) > targetX ? (inkyX - 1) - targetX : targetX - (inkyX - 1)) +
            (inkyY       > targetY ? inkyY       - targetY : targetY - inkyY);

    if (canMoveRight && !forbidRight)
        distRight =
            ((inkyX + 1) > targetX ? (inkyX + 1) - targetX : targetX - (inkyX + 1)) +
            (inkyY       > targetY ? inkyY       - targetY : targetY - inkyY);
end

// =======================================================
// Movement update + TUNNEL TELEPORT
// =======================================================
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

        if (startupDone && moveTick) begin
            inkyAcc <= inkyAccAfter;

            if (inkyStep) begin
                reg [1:0] nextDir;

                if (distUp <= distDown &&
                    distUp <= distLeft &&
                    distUp <= distRight)
                    nextDir = 2'b00;

                else if (distDown <= distUp &&
                         distDown <= distLeft &&
                         distDown <= distRight)
                    nextDir = 2'b10;

                else if (distLeft <= distUp &&
                         distLeft <= distDown &&
                         distLeft <= distRight)
                    nextDir = 2'b11;

                else
                    nextDir = 2'b01;

                if (escapeDone && !escapedShifted) begin
                    if (nextDir == 2'b11 || nextDir == 2'b01)
                        escapedShifted <= 1;
                end

                dir <= nextDir;

                // -----------------------------
                // Regular movement
                // -----------------------------
                case (nextDir)
                    2'b00: if (canMoveUp)    inkyY <= inkyY - 1;
                    2'b10: if (canMoveDown)  inkyY <= inkyY + 1;
                    2'b01: if (canMoveRight) inkyX <= inkyX + 1;
                    2'b11: if (canMoveLeft)  inkyX <= inkyX - 1;
                endcase

                // =======================================================
                // TUNNEL TELEPORT — INSERTED HERE
                // =======================================================
                if ((inkyX == 6'd0) && (inkyY == 6'd19) && (dir == 2'b11)) begin
                    inkyX <= 6'd27;
                    inkyY <= 6'd19;
                end
                else if ((inkyX == 6'd27) && (inkyY == 6'd19) && (dir == 2'b01)) begin
                    inkyX <= 6'd0;
                    inkyY <= 6'd19;
                end
                // =======================================================

            end
        end
    end
end

endmodule
