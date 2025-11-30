// Keyboard Command Decoder
// Converts UART bytes to movement signals
// Commands: 'W'=up, 'S'=down, 'A'=left, 'D'=right (case insensitive)

module keyboard_decoder(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  uart_data,
    input  wire        uart_valid,
    output reg         move_up,
    output reg         move_down,
    output reg         move_left,
    output reg         move_right
);

    // Decode ASCII characters
    // 'W' = 0x57, 'w' = 0x77 (up)
    // 'S' = 0x53, 's' = 0x73 (down)
    // 'A' = 0x41, 'a' = 0x61 (left)
    // 'D' = 0x44, 'd' = 0x64 (right)
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            move_up <= 1'b0;
            move_down <= 1'b0;
            move_left <= 1'b0;
            move_right <= 1'b0;
        end else begin
            // Reset all signals first
            move_up <= 1'b0;
            move_down <= 1'b0;
            move_left <= 1'b0;
            move_right <= 1'b0;
            
            // Decode on valid UART data
            if (uart_valid) begin
                case (uart_data)
                    8'h57, 8'h77: move_up <= 1'b1;      // 'W' or 'w'
                    8'h53, 8'h73: move_down <= 1'b1;  // 'S' or 's'
                    8'h41, 8'h61: move_left <= 1'b1;  // 'A' or 'a'
                    8'h44, 8'h64: move_right <= 1'b1; // 'D' or 'd'
                    default: ; // No movement for other keys
                endcase
            end
        end
    end
endmodule

