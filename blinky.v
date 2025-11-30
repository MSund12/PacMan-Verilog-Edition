module blinky(
    input  wire        clk,
    input  wire        rst_n,       // active-low reset
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

    input  wire [7:0]  ghost_speed,  // Speed percentage (0-100) relative to Pacman base speed

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
// Tile-based movement with variable speed
// Moves exactly 1 tile at a time, using the same tile grid Pac-Man uses
// Speed is controlled by ghost_speed percentage (relative to Pacman base speed)
// Uses frame skipping to achieve fractional speeds
// -------------------------------------------------------
// Calculate frames per move: 8 pixels per move, ghost_speed% of Pacman base (125/99 px/frame)
// Frames per move = 8 / ((125/99) * (ghost_speed/100)) = 79200 / (125 * ghost_speed) = 633.6 / ghost_speed
// For integer arithmetic with precision: use counter that increments by 100 each frame
// Threshold = 63360 / ghost_speed (scaled by 100)
reg [15:0] speed_counter;
wire [15:0] speed_threshold;

// Calculate threshold: 63360 / ghost_speed (scaled by 100 for precision)
// Example: ghost_speed = 75 -> threshold = 63360 / 75 = 844.8 ≈ 845
// Counter increments by 100 per frame, so after 8 frames = 800, after 9 frames = 900 >= 845 -> move
assign speed_threshold = (ghost_speed > 0) ? ((16'd63360) / ghost_speed) : 16'd9999;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        blinkyX <= 14;   // Spawn tile X (CENTER TOP like arcade)
        blinkyY <= 12;   // Spawn tile Y
        speed_counter <= 16'd0;
    end else begin
        if (frame_tick) begin
            speed_counter <= speed_counter + 16'd100;  // Increment by 100 for precision
            
            // Move when counter reaches threshold
            if (speed_counter >= speed_threshold) begin
                speed_counter <= speed_counter - speed_threshold;  // Keep remainder for accuracy
                
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
end

endmodule
