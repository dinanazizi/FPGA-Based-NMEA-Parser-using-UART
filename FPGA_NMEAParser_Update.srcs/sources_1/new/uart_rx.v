`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ = 125000000, // Clock Zybo Z7 (125 MHz)
    parameter BAUD_RATE = 115200    // Standar Baud Rate GPS
)(
    input wire clk,
    input wire rst,
    input wire rx,            
    output reg [7:0] rx_data, 
    output reg rx_ready       
);

    localparam BAUD_TICK = CLK_FREQ / BAUD_RATE;
    localparam HALF_BAUD_TICK = BAUD_TICK / 2;

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state;
    reg [15:0] timer;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            timer <= 0;
            bit_index <= 0;
            rx_ready <= 0;
            rx_data <= 0;
        end else begin
            rx_ready <= 0; 

            case (state)
                IDLE: begin
                    if (rx == 1'b0) begin 
                        state <= START;
                        timer <= 0;
                    end
                end
                
                START: begin
                    if (timer == HALF_BAUD_TICK) begin
                        state <= DATA;
                        timer <= 0;
                        bit_index <= 0;
                    end else begin
                        timer <= timer + 1;
                    end
                end
                
                DATA: begin
                    if (timer == BAUD_TICK) begin
                        timer <= 0;
                        shift_reg <= {rx, shift_reg[7:1]};
                        
                        if (bit_index == 7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        timer <= timer + 1;
                    end
                end
                
                STOP: begin
                    if (timer == BAUD_TICK) begin
                        state <= IDLE;
                        rx_data <= shift_reg; 
                        rx_ready <= 1'b1;     
                    end else begin
                        timer <= timer + 1;
                    end
                end
            endcase
        end
    end
endmodule