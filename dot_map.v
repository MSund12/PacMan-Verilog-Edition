// Dot Map Module
// Tracks which tiles contain dots (1 bit per tile, 28x36 = 1008 tiles)
// Dots exist only in path tiles (non-wall tiles)

module dot_map(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        level_reset,      // Reset dots when level starts/restarts
    
    // Tile coordinates to check/clear (for game logic)
    input  wire [4:0] tile_x,             // 0..27
    input  wire [5:0] tile_y,             // 0..35
    input  wire        clear_dot,         // Clear dot at (tile_x, tile_y)
    input  wire        is_wall_tile,      // 1 if this tile is a wall (no dot possible)
    
    // Read dot state for game logic
    output wire        has_dot,            // 1 if tile has a dot
    
    // Read dot state for rendering (separate port)
    input  wire [4:0] render_tile_x,     // 0..27
    input  wire [5:0] render_tile_y,       // 0..35
    input  wire        render_is_wall,     // 1 if render tile is wall
    output wire        render_has_dot,     // 1 if render tile has a dot
    
    output reg  [7:0]  dots_remaining     // Count of remaining dots (0-240)
);

    // 28 x 36 = 1008 tiles
    localparam TOTAL_TILES = 1008;
    localparam TOTAL_DOTS = 240;  // Standard Pac-Man has 240 dots per level
    
    // Dot map: 1 bit per tile (1 = dot exists, 0 = dot collected or wall)
    reg dot_bits [0:TOTAL_TILES-1];
    // Initial dot state (loaded from file, restored on level reset)
    reg dot_bits_init [0:TOTAL_TILES-1];
    
    // Calculate linear tile indices
    wire [9:0] tile_index = ((tile_y << 5) - (tile_y << 2)) + tile_x;  // tile_y*28 + tile_x
    wire [9:0] render_tile_index = ((render_tile_y << 5) - (render_tile_y << 2)) + render_tile_x;
    
    // Read dot state for game logic (only valid for non-wall tiles)
    assign has_dot = (tile_index < TOTAL_TILES) ? (dot_bits[tile_index] && !is_wall_tile) : 1'b0;
    
    // Read dot state for rendering (only valid for non-wall tiles)
    assign render_has_dot = (render_tile_index < TOTAL_TILES) ? (dot_bits[render_tile_index] && !render_is_wall) : 1'b0;
    
    // Count remaining dots (combinational)
    integer i;
    always @(*) begin
        dots_remaining = 8'd0;
        for (i = 0; i < TOTAL_TILES; i = i + 1) begin
            if (dot_bits[i])
                dots_remaining = dots_remaining + 1;
        end
    end
    
    // Load initial dot map from file (similar to level_rom)
    integer j;
    initial begin
        // Initialize to 0 in case file is missing/short
        for (j = 0; j < TOTAL_TILES; j = j + 1) begin
            dot_bits[j] = 1'b0;
            dot_bits_init[j] = 1'b0;
        end
        
        // Load dot map from file: one bit per line
        $readmemb("dot_map.bin", dot_bits_init);
    end
    
    // Initialize and manage dot map
    reg [9:0] reset_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reset_counter <= 10'd0;
        end else begin
            if (level_reset) begin
                // Reset all dots: copy from initial state
                // Use a counter to restore all tiles over multiple cycles
                if (reset_counter < TOTAL_TILES) begin
                    dot_bits[reset_counter] <= dot_bits_init[reset_counter];
                    reset_counter <= reset_counter + 10'd1;
                end else begin
                    reset_counter <= 10'd0;
                end
            end else begin
                reset_counter <= 10'd0;
                if (clear_dot && tile_index < TOTAL_TILES && !is_wall_tile) begin
                    // Clear dot when collected (only for non-wall tiles)
                    dot_bits[tile_index] <= 1'b0;
                end
            end
        end
    end
endmodule

