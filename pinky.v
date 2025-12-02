module pinky(
    input  wire        clk,
    input  wire        reset,

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

// -----------------------------------------------------------
// Pinky's normal behavior settings
// -----------------------------------------------------------
localparam [5:0] CORNER_X = 27;
localparam [5:0] CORNER_Y = 0;

// Starting tile (inside box)
localparam [5:0] PINKY_START_TILE_X = 6'd13;
localparam [5:0] PINKY_START_TILE_Y = 6'd19;

// Escape tile (same as Inky)
localparam [5:0] ESCAPE_X = 6'd13;
localparam [5:0] ESCAPE_Y = 6'd16;

reg escapeDone = 0;
reg escapedShifted = 0;   // becomes 1 after pinky moves L/R after escape

// -----------------------------------------------------------
// 5-second delay before ghost begins movement
// -----------------------------------------------------------
localparam FIVE_SEC_TICKS = 25_000_000 * 5;
reg [27:0] startDelay = 0;
reg        delayDone  = 0;

// -----------------------------------------------------------
// 60Hz tick
// -----------------------------------------------------------
localparam MOVE_DIV = 416_666;
reg [19:0] moveCount = 0;
reg        moveTick = 0;

always @(posedge clk) begin
    if (moveCount >= MOVE_DIV) begin
        moveCount <= 0;
        moveTick <= 1;
    end else begin
        moveCount <= moveCount + 1;
        moveTick <= 0;
    end
end

// -----------------------------------------------------------
// Fractional speed accumulator
// -----------------------------------------------------------
reg [15:0] pinkyAcc;
wire [15:0] accNext = pinkyAcc + 16'd150;
wire doStep = (accNext >= 16'd1000);
wire [15:0] accAfter = doStep ? (accNext - 16'd1000) : accNext;

// -----------------------------------------------------------
// Determine target tile (normal behavior)
// -----------------------------------------------------------
reg [5:0] targetX;
reg [5:0] targetY;

always @(*) begin
    if (!escapeDone) begin
        // Escape target
        targetX = ESCAPE_X;
        targetY = ESCAPE_Y;
    end
    else if (isChase) begin
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

// -----------------------------------------------------------
// Movement legality logic
// -----------------------------------------------------------
wire canUp    = !wallUp;
wire canDown  = !wallDown;
wire canLeft  = !wallLeft;
wire canRight = !wallRight;

// -----------------------------------------------------------
// Direction 0=Up,1=Down,2=Left,3=Right
// -----------------------------------------------------------
reg [1:0] currDir;
reg [1:0] desiredDir;
reg [1:0] reverseDir;
reg moved;

// -----------------------------------------------------------
// Main movement logic
// -----------------------------------------------------------
reg downAllowed;  // use reg instead of wire for always block

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

        // Handle startup delay
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else
                delayDone <= 1;
        end

        // Has Pinky reached escape tile?
        if (!escapeDone && pinkyX == ESCAPE_X && pinkyY == ESCAPE_Y)
            escapeDone <= 1;

        // Determine if DOWN movement is allowed
        downAllowed <= escapeDone && (escapedShifted || desiredDir != 2'b01);

        // Movement tick
        if (delayDone && moveTick) begin
            pinkyAcc <= accAfter;

            if (doStep) begin
                moved = 0;

                // Reverse direction logic
                case (currDir)
                    2'b00: reverseDir = 2'b01;
                    2'b01: reverseDir = 2'b00;
                    2'b10: reverseDir = 2'b11;
                    2'b11: reverseDir = 2'b10;
                endcase

                // Desired direction toward target
                if (targetX > pinkyX)       desiredDir = 2'b11;
                else if (targetX < pinkyX)  desiredDir = 2'b10;
                else if (targetY > pinkyY)  desiredDir = 2'b01;
                else if (targetY < pinkyY)  desiredDir = 2'b00;
                else                        desiredDir = currDir;

                // ---------------------------------------------------
                // 1. Try desired direction (if legal & not reverse)
                // ---------------------------------------------------
                if (!moved && desiredDir != reverseDir) begin
                    case (desiredDir)
                        2'b00: if (canUp)    begin pinkyY <= pinkyY - 1; currDir <= 2'b00; moved = 1; end
                        2'b01: if (canDown && downAllowed)
                                        begin pinkyY <= pinkyY + 1; currDir <= 2'b01; moved = 1; end
                        2'b10: if (canLeft)  begin pinkyX <= pinkyX - 1; currDir <= 2'b10; moved = 1; end
                        2'b11: if (canRight) begin pinkyX <= pinkyX + 1; currDir <= 2'b11; moved = 1; end
                    endcase
                end

                // ---------------------------------------------------
                // Detect left/right shift AFTER escape
                // ---------------------------------------------------
                if (escapeDone && !escapedShifted &&
                    (currDir == 2'b10 || currDir == 2'b11))
                    escapedShifted <= 1;

                // ---------------------------------------------------
                // 2. Try continuing straight
                // ---------------------------------------------------
                if (!moved) begin
                    case (currDir)
                        2'b00: if (canUp)    begin pinkyY <= pinkyY - 1; moved = 1; end
                        2'b01: if (canDown && downAllowed)
                                        begin pinkyY <= pinkyY + 1; moved = 1; end
                        2'b10: if (canLeft)  begin pinkyX <= pinkyX - 1; moved = 1; end
                        2'b11: if (canRight) begin pinkyX <= pinkyX + 1; moved = 1; end
                    endcase
                end

                // ---------------------------------------------------
                // 3. Try any legal alternative (except reverse)
                // ---------------------------------------------------
                if (!moved) begin
                    if (canUp    && reverseDir != 2'b00) begin pinkyY <= pinkyY - 1; currDir <= 2'b00; moved = 1; end
                    else if (canDown && downAllowed && reverseDir != 2'b01)
                        begin pinkyY <= pinkyY + 1; currDir <= 2'b01; moved = 1; end
                    else if (canLeft  && reverseDir != 2'b10) begin pinkyX <= pinkyX - 1; currDir <= 2'b10; moved = 1; end
                    else if (canRight && reverseDir != 2'b11) begin pinkyX <= pinkyX + 1; currDir <= 2'b11; moved = 1; end
                end
            end
        end
    end
end

endmodule
