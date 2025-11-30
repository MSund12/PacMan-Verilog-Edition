// ISSP Control Module
// Provides keyboard control signals via In-System Sources and Probes (ISSP)
// Allows real-time control over JTAG without requiring UART

module issp_control(
    input  wire        clk,
    input  wire        rst_n,
    output reg         move_up,
    output reg         move_down,
    output reg         move_left,
    output reg         move_right,
    output reg         start_game
);

    // ISSP source probe - 5 bits for control signals
    // Bit 0: move_up
    // Bit 1: move_down
    // Bit 2: move_left
    // Bit 3: move_right
    // Bit 4: start_game
    wire [4:0] issp_source_data;
    
    // Instantiate ISSP source probe primitive
    altsource_probe #(
        .sld_auto_instance_index("YES"),
        .sld_instance_index(0),
        .instance_id("ISSP_CTRL"),
        .probe_width(0),
        .source_width(5),
        .source_initial_value("0"),
        .enable_metastability("NO")
    ) issp_inst (
        .probe(5'b0),              // Not using probes, only sources
        .source(issp_source_data)   // 5-bit control register from JTAG
    );
    
    // Edge detection for pulse generation
    reg [4:0] issp_source_data_prev;
    wire [4:0] issp_source_data_edge;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issp_source_data_prev <= 5'b0;
        end else begin
            issp_source_data_prev <= issp_source_data;
        end
    end
    
    // Detect rising edges (when bit changes from 0 to 1)
    assign issp_source_data_edge = issp_source_data & ~issp_source_data_prev;
    
    // Generate pulse signals on rising edge (similar to UART decoder)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            move_up <= 1'b0;
            move_down <= 1'b0;
            move_left <= 1'b0;
            move_right <= 1'b0;
            start_game <= 1'b0;
        end else begin
            // Generate one-cycle pulses on rising edge
            move_up <= issp_source_data_edge[0];
            move_down <= issp_source_data_edge[1];
            move_left <= issp_source_data_edge[2];
            move_right <= issp_source_data_edge[3];
            start_game <= issp_source_data_edge[4];
        end
    end

endmodule

