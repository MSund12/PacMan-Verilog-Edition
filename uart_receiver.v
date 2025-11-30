// UART Receiver Module
// Baud rate: 115200 (configurable via BAUD_DIV parameter)
// Data format: 8N1 (8 data bits, no parity, 1 stop bit)

module uart_receiver(
    input  wire clk,
    input  wire rst_n,
    input  wire rx,              // UART RX line
    output reg  [7:0] data,      // Received byte
    output reg  data_valid        // High for one clock cycle when data is valid
);

    // Baud rate: 115200 at 50 MHz
    // Clock cycles per bit: 50,000,000 / 115200 ≈ 434
    localparam BAUD_DIV = 434;
    localparam BAUD_DIV_HALF = BAUD_DIV / 2;

    // Receiver state machine
    localparam IDLE = 3'd0;
    localparam START = 3'd1;
    localparam DATA = 3'd2;
    localparam STOP = 3'd3;

    reg [2:0] state;
    reg [2:0] bit_index;
    reg [8:0] baud_counter;
    reg [7:0] rx_data;

    // Synchronize RX input (double flop for metastability)
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    // Edge detection for start bit
    reg rx_prev;
    wire rx_falling_edge;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_prev <= 1'b1;
        else
            rx_prev <= rx_sync2;
    end
    assign rx_falling_edge = rx_prev && !rx_sync2;

    // State machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_index <= 3'd0;
            baud_counter <= 9'd0;
            rx_data <= 8'd0;
            data <= 8'd0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;  // Default: data_valid is one-shot

            case (state)
                IDLE: begin
                    if (rx_falling_edge) begin
                        state <= START;
                        baud_counter <= 9'd0;
                    end
                end

                START: begin
                    if (baud_counter >= BAUD_DIV_HALF) begin
                        // Sample start bit (should be 0)
                        if (!rx_sync2) begin
                            state <= DATA;
                            bit_index <= 3'd0;
                            baud_counter <= 9'd0;
                        end else begin
                            // False start bit, go back to IDLE
                            state <= IDLE;
                        end
                    end else begin
                        baud_counter <= baud_counter + 9'd1;
                    end
                end

                DATA: begin
                    if (baud_counter >= BAUD_DIV) begin
                        rx_data[bit_index] <= rx_sync2;
                        baud_counter <= 9'd0;
                        if (bit_index == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 9'd1;
                    end
                end

                STOP: begin
                    if (baud_counter >= BAUD_DIV) begin
                        // Sample stop bit (should be 1)
                        if (rx_sync2) begin
                            data <= rx_data;
                            data_valid <= 1'b1;
                        end
                        state <= IDLE;
                        baud_counter <= 9'd0;
                    end else begin
                        baud_counter <= baud_counter + 9'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule

