// Score Manager Module
// Tracks score, lives, and handles scoring events

module score_manager(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        game_started,
    
    // Scoring events
    input  wire        dot_collected,      // Dot collected (10 points)
    input  wire        pellet_collected,   // Power pellet collected (50 points)
    input  wire        ghost_eaten,        // Ghost eaten in fright mode (200/400/800/1600)
    input  wire [1:0]  ghost_eaten_count,  // Which ghost (0-3) for multiplier
    
    // Game state
    input  wire        lose_life,         // Pac-Man was caught by ghost
    input  wire        level_complete,    // All dots collected
    
    // Outputs
    output reg  [15:0] score,             // Current score (0-999999)
    output reg  [2:0]  lives,             // Remaining lives (0-7)
    output reg  [15:0] high_score,        // High score
    output wire        game_over          // 1 when lives = 0
);

    // Scoring values
    localparam [7:0] SCORE_DOT = 8'd10;
    localparam [7:0] SCORE_PELLET = 8'd50;
    localparam [9:0] SCORE_GHOST_1 = 10'd200;
    localparam [9:0] SCORE_GHOST_2 = 10'd400;
    localparam [9:0] SCORE_GHOST_3 = 10'd800;
    localparam [10:0] SCORE_GHOST_4 = 11'd1600;
    
    // Initial lives
    localparam [2:0] INITIAL_LIVES = 3'd3;
    
    // Ghost score lookup
    wire [10:0] ghost_score;
    assign ghost_score = (ghost_eaten_count == 2'd0) ? SCORE_GHOST_1 :
                         (ghost_eaten_count == 2'd1) ? SCORE_GHOST_2 :
                         (ghost_eaten_count == 2'd2) ? SCORE_GHOST_3 : SCORE_GHOST_4;
    
    assign game_over = (lives == 3'd0);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            score <= 16'd0;
            lives <= INITIAL_LIVES;
            high_score <= 16'd0;
        end else begin
            // Update high score
            if (score > high_score) begin
                high_score <= score;
            end
            
            // Handle scoring events
            if (dot_collected && game_started) begin
                score <= score + SCORE_DOT;
            end else if (pellet_collected && game_started) begin
                score <= score + SCORE_PELLET;
            end else if (ghost_eaten && game_started) begin
                score <= score + ghost_score;
            end
            
            // Handle life loss
            if (lose_life && game_started && lives > 3'd0) begin
                lives <= lives - 3'd1;
            end
            
            // Extra life at 10000 points (not implemented yet, but structure ready)
            // if (score >= 16'd10000 && score < 16'd10010) begin
            //     lives <= lives + 3'd1;
            // end
        end
    end
endmodule

