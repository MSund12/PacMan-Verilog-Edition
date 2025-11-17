module pacman(
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

    output reg [5:0]   blinkyX,
    output reg [5:0]   blinkyY
);


/* 
Blinky (Red Ghost)

Movement Logic for chase mode is target position should be set to pacman's current position


Movement Logic for scatter mode is to go back to his corner. However, if he is has his speed increased 
(happens twice per level based on how many dots remain) then he instead keeps on targeting pacman like 
in chase mode but he still reverses during the beginning and end of scatter mode 


Frighten mode is same as all other ghosts
*/


    // Blinky’s scatter corner is top right
    localparam [5:0] CORNER_X = 0;
    localparam [5:0] CORNER_Y = 0;

    reg [5:0] targetX;
    reg [5:0] targetY;

    
    // Set target position in chase (pacman) or go to corner in scatter mode
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

    
    //Spawn points
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            blinkyX <= 0; //x cordinate of pixel where Blinky spawns in the map
            blinkyY <= 0; //y cordinate of pixel where Blinky spawns in the map
        end
        else begin
            // Horizontal move
            if (targetX > blinkyX && !wallRight)
                blinkyX <= blinkyX + 1;
            else if (targetX < blinkyX && !wallLeft)
                blinkyX <= blinkyX - 1;

            // If not moving horizontally then move vertically
            else if (targetY > blinkyY && !wallDown)
                blinkyY <= blinkyY + 1;
            else if (targetY < blinkyY && !wallUp)
                blinkyY <= blinkyY - 1;
        end
    end

endmodule 




