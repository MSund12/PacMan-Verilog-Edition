module pinky(
    input  wire        clk,
    input  wire        reset,

    input  wire [5:0]  pacmanX,    // pacman tile X (0..27)
    input  wire [5:0]  pacmanY,    // pacman tile Y (0..35)
    input  wire [1:0]  pacmanDir,  // 0=Up,1=Down,2=Left,3=Right

    input  wire        isChase,
    input  wire        isScatter,

    // Tile-based wall indicators
    input  wire        wallUp,
    input  wire        wallDown,
    input  wire        wallLeft,
    input  wire        wallRight,

    output reg [5:0]   pinkyX,     // tile X (0..27)
    output reg [5:0]   pinkyY      // tile Y (0..35)
);

/* 
Pinky (Pink Ghost)
Chase mode: target 4 tiles ahead of Pac-Man in his current moving direction
Scatter mode: target top-left corner
*/

// Scatter corner
localparam [5:0] CORNER_X = 0;
localparam [5:0] CORNER_Y = 0;

// Pixel-based starting position
localparam IMG_X0 = 208;
localparam IMG_Y0 = 96;
localparam TILE_W = 8;
localparam TILE_H = 8;
localparam PINKY_START_X_PIX = IMG_X0 + 13*TILE_W + 4 + 3;  
localparam PINKY_START_Y_PIX = IMG_Y0 + 14*TILE_H + 4 + 19;  
localparam [5:0] PINKY_START_TILE_X = (PINKY_START_X_PIX - IMG_X0) / TILE_W;
localparam [5:0] PINKY_START_TILE_Y = (PINKY_START_Y_PIX - IMG_Y0) / TILE_H;
localparam [2:0] PINKY_OFFSET_X = (PINKY_START_X_PIX - IMG_X0) % TILE_W;
localparam [2:0] PINKY_OFFSET_Y = (PINKY_START_Y_PIX - IMG_Y0) % TILE_H;

// Target
reg [5:0] targetX;
reg [5:0] targetY;

// Start delay
localparam FIVE_SEC_TICKS = 25_000_000 * 5;
reg [27:0] startDelay = 0;
reg        delayDone  = 0;

// 60Hz movement tick
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

// Fractional speed accumulator
reg [15:0] pinkyAcc;
wire [15:0] pinkyAccNext = pinkyAcc + 16'd150;
wire pinkyStep = (pinkyAccNext >= 16'd1000);
wire [15:0] pinkyAccAfter = pinkyStep ? (pinkyAccNext - 16'd1000) : pinkyAccNext;

// -------------------------------------------------------
// Determine target tile (Chase / Scatter)
// -------------------------------------------------------
always @(*) begin
    if (isChase) begin
        case (pacmanDir)
            2'b00: begin // Up
                targetX = pacmanX;
                targetY = (pacmanY >= 4) ? pacmanY - 4 : 0;
            end
            2'b01: begin // Down
                targetX = pacmanX;
                targetY = (pacmanY + 4 <= 35) ? pacmanY + 4 : 35;
            end
            2'b10: begin // Left
                targetX = (pacmanX >= 4) ? pacmanX - 4 : 0;
                targetY = pacmanY;
            end
            2'b11: begin // Right
                targetX = (pacmanX + 4 <= 27) ? pacmanX + 4 : 27;
                targetY = pacmanY;
            end
            default: begin
                targetX = pacmanX;
                targetY = pacmanY;
            end
        endcase
    end else if (isScatter) begin
        targetX = CORNER_X;
        targetY = CORNER_Y;
    end else begin
        targetX = pacmanX;
        targetY = pacmanY;
    end
end

// -------------------------------------------------------
// Track current direction to prevent unnecessary reversals
// 0=Up,1=Down,2=Left,3=Right
// -------------------------------------------------------
reg [1:0] currDir; 
function [1:0] opposite;
    input [1:0] dir;
    begin
        case(dir)
            2'b00: opposite = 2'b01;
            2'b01: opposite = 2'b00;
            2'b10: opposite = 2'b11;
            2'b11: opposite = 2'b10;
            default: opposite = 2'b00;
        endcase
    end
endfunction

reg [1:0] nextDir;

// -------------------------------------------------------
// Intersection logic: choose best next direction
// -------------------------------------------------------
always @(*) begin
    integer bestDist;
    integer dist;
    bestDist = 1000;
    nextDir = currDir; // default keep going straight

    // Up
    if (!wallUp && opposite(currDir) != 2'b00) begin
        dist = (pinkyX - targetX)*(pinkyX - targetX) + (pinkyY-1 - targetY)*(pinkyY-1 - targetY);
        if (dist < bestDist) begin
            bestDist = dist;
            nextDir = 2'b00;
        end
    end
    // Down
    if (!wallDown && opposite(currDir) != 2'b01) begin
        dist = (pinkyX - targetX)*(pinkyX - targetX) + (pinkyY+1 - targetY)*(pinkyY+1 - targetY);
        if (dist < bestDist) begin
            bestDist = dist;
            nextDir = 2'b01;
        end
    end
    // Left
    if (!wallLeft && opposite(currDir) != 2'b10) begin
        dist = (pinkyX-1 - targetX)*(pinkyX-1 - targetX) + (pinkyY - targetY)*(pinkyY - targetY);
        if (dist < bestDist) begin
            bestDist = dist;
            nextDir = 2'b10;
        end
    end
    // Right
    if (!wallRight && opposite(currDir) != 2'b11) begin
        dist = (pinkyX+1 - targetX)*(pinkyX+1 - targetX) + (pinkyY - targetY)*(pinkyY - targetY);
        if (dist < bestDist) begin
            bestDist = dist;
            nextDir = 2'b11;
        end
    end
end

// -------------------------------------------------------
// Pinky movement at each tick
// -------------------------------------------------------
reg [2:0] startOffsetX;
reg [2:0] startOffsetY;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        pinkyX      <= PINKY_START_TILE_X;
        pinkyY      <= PINKY_START_TILE_Y;
        startOffsetX <= PINKY_OFFSET_X;
        startOffsetY <= PINKY_OFFSET_Y;
        startDelay   <= 0;
        delayDone    <= 0;
        pinkyAcc    <= 0;
        currDir      <= 2'b00; // default Up
    end else begin
        if (!delayDone) begin
            if (startDelay < FIVE_SEC_TICKS)
                startDelay <= startDelay + 1;
            else
                delayDone <= 1;
        end
        else if (moveTick) begin
            pinkyAcc <= pinkyAccAfter;
            if (pinkyStep) begin
                currDir <= nextDir; // update direction

                case(nextDir)
                    2'b00: pinkyY <= pinkyY - 1;
                    2'b01: pinkyY <= pinkyY + 1;
                    2'b10: pinkyX <= pinkyX - 1;
                    2'b11: pinkyX <= pinkyX + 1;
                endcase

                startOffsetX <= 0;
                startOffsetY <= 0;
            end
        end
    end
end

endmodule
