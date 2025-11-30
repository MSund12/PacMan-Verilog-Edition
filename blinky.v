module blinky(
    input  wire        clk,
    input  wire        reset,
    input  wire        frame_tick,  // Move once per frame

    input  wire [5:0]  pacmanX,   // pacman tile X (0..27)
    input  wire [5:0]  pacmanY,   // pacman tile Y (0..35)

    input  wire        isChase,
    input  wire        isScatter,

    // Now tile-based wall indicators, already provided by Pac-Man code
    input  wire        wallUp,
    input  wire        wallDown,
    input  wire        wallLeft,
    input  wire        wallRight,

    output reg [5:0]   blinkyX,   // tile X (0..27)
    output reg [5:0]   blinkyY    // tile Y (0..35)
);


/* 
Blinky (Red Ghost)

Movement Logic for chase mode is target position should be set to pacman's current position

Movement Logic for scatter mode is to go back to his corner. However, if he has his speed increased 
(happens twice per level based on how many dots remain) then he instead keeps on targeting pacman like 
in chase mode but he still reverses during the beginning and end of scatter mode 

Frighten mode is same as all other ghosts
*/

// Blinky’s scatter corner is top right
localparam [5:0] CORNER_X = 27;   // top-right of the 28×36 grid
localparam [5:0] CORNER_Y = 0;

reg [5:0] targetX;
reg [5:0] targetY;


// -------------------------------------------------------
// Target selection
// -------------------------------------------------------
always @(*) begin
    if (isChase) begin
        targetX = pacmanX;
        targetY = pacmanY;
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


// -------------------------------------------------------
// Tile-based movement
// Moves exactly 1 tile at a time, using the same tile grid Pac-Man uses
// Synchronized to frame_tick to move once per frame
// -------------------------------------------------------
always @(posedge clk or negedge reset) begin
    if (!reset) begin
        blinkyX <= 14;   // Spawn tile X (CENTER TOP like arcade)
        blinkyY <= 12;   // Spawn tile Y
    end else begin
        if (frame_tick) begin
            // Horizontal priority (like Pac-Man arcade ghost AI)
            if (targetX > blinkyX && !wallRight)
                blinkyX <= blinkyX + 1;
            else if (targetX < blinkyX && !wallLeft)
                blinkyX <= blinkyX - 1;

            // If blocked horizontally, attempt vertical
            else if (targetY > blinkyY && !wallDown)
                blinkyY <= blinkyY + 1;
            else if (targetY < blinkyY && !wallUp)
                blinkyY <= blinkyY - 1;

            // If both X and Y are blocked, Blinky stays in place
        end
    end
end

endmodule
