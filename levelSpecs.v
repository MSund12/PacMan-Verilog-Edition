//Based on what level player is on, set the power ups, movespeeds for the level
module level_params(
    input  wire [4:0] level,   // 1–21+
    
    output reg [7:0] pacman_speed,
    output reg [7:0] pacman_dots_speed,
    output reg [7:0] ghost_speed,
    output reg [7:0] ghost_tunnel_speed,

    output reg [7:0] elroy1_speed,
    output reg [7:0] elroy2_speed,
    output reg [6:0] elroy1_dots_left,
    output reg [6:0] elroy2_dots_left,

    output reg [7:0] fright_pacman_speed,
    output reg [7:0] fright_pacman_dots_speed,
    output reg [7:0] fright_ghost_speed,
    output reg [3:0] fright_time,       // seconds
    output reg [2:0] fright_flashes     // number of flashes
);

always @(*) begin
    case (level)

    //============================================================
    // LEVEL 1
    //============================================================
    1: begin
        pacman_speed            = 80;
        pacman_dots_speed       = 71;
        ghost_speed             = 75;
        ghost_tunnel_speed      = 40;

        elroy1_dots_left        = 20;
        elroy1_speed            = 80;
        elroy2_dots_left        = 10;
        elroy2_speed            = 85;

        fright_pacman_speed     = 90;
        fright_pacman_dots_speed= 79;
        fright_ghost_speed      = 50;
        fright_time             = 6;
        fright_flashes          = 5;
    end

    //============================================================
    // LEVEL 2
    //============================================================
    2: begin
        pacman_speed            = 90;
        pacman_dots_speed       = 79;
        ghost_speed             = 85;
        ghost_tunnel_speed      = 45;

        elroy1_dots_left        = 30;
        elroy1_speed            = 90;
        elroy2_dots_left        = 15;
        elroy2_speed            = 95;

        fright_pacman_speed     = 95;
        fright_pacman_dots_speed= 83;
        fright_ghost_speed      = 55;
        fright_time             = 5;
        fright_flashes          = 5;
    end

    //============================================================
    // LEVEL 3–4 (same values)
    //============================================================
    3,4: begin
        pacman_speed            = 90;
        pacman_dots_speed       = 79;
        ghost_speed             = 85;
        ghost_tunnel_speed      = 45;

        elroy1_dots_left        = 40;
        elroy1_speed            = 90;
        elroy2_dots_left        = 20;
        elroy2_speed            = 95;

        fright_pacman_speed     = 95;
        fright_pacman_dots_speed= 83;
        fright_ghost_speed      = 55;
        fright_time             = 4;
        fright_flashes          = 5;
    end

    //============================================================
    // LEVEL 5–20 (SAME VALUES)
    //============================================================
    5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20: begin
        pacman_speed            = 100;
        pacman_dots_speed       = 87;
        ghost_speed             = 95;
        ghost_tunnel_speed      = 50;

        // dots left vary by level but here is a simplified version:
        // If you want exact values per level, I can add them.
        elroy1_dots_left        = 50;
        elroy1_speed            = 100;
        elroy2_dots_left        = 25;
        elroy2_speed            = 105;

        fright_pacman_speed     = 100;
        fright_pacman_dots_speed= 87;
        fright_ghost_speed      = 60;

        case (level)
            5:  begin fright_time=5; fright_flashes=5; end
            6:  begin fright_time=5; fright_flashes=5; end
            7:  begin fright_time=2; fright_flashes=5; end
            8:  begin fright_time=2; fright_flashes=5; end
            9:  begin fright_time=1; fright_flashes=3; end
            10: begin fright_time=5; fright_flashes=5; end
            11: begin fright_time=2; fright_flashes=3; end
            12: begin fright_time=1; fright_flashes=3; end
            13: begin fright_time=1; fright_flashes=3; end
            14: begin fright_time=3; fright_flashes=3; end
            15: begin fright_time=1; fright_flashes=3; end
            16: begin fright_time=1; fright_flashes=3; end
            17: begin fright_time=0; fright_flashes=0; end
            18: begin fright_time=1; fright_flashes=3; end
            19: begin fright_time=1; fright_flashes=3; end
            20: begin fright_time=0; fright_flashes=0; end
        endcase
    end

    //============================================================
    // LEVEL 21+ (same forever)
    //============================================================
    default: begin
        pacman_speed            = 90;
        pacman_dots_speed       = 79;
        ghost_speed             = 95;
        ghost_tunnel_speed      = 50;

        elroy1_dots_left        = 120;
        elroy1_speed            = 100;
        elroy2_dots_left        = 60;
        elroy2_speed            = 105;

        fright_pacman_speed     = 0;
        fright_pacman_dots_speed= 0;
        fright_ghost_speed      = 0;
        fright_time             = 0;
        fright_flashes          = 0;
    end

    endcase
end

endmodule