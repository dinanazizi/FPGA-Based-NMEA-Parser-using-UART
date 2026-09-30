`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ = 125000000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst,
    input wire tx_start,      
    input wire [7:0] tx_data, 
    output reg tx,            
    output reg tx_busy        
);

    localparam BAUD_TICK = CLK_FREQ / BAUD_RATE;
    
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
            tx <= 1'b1; 
            tx_busy <= 0;
            timer <= 0;
            bit_index <= 0;
            shift_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 0;
                    if (tx_start) begin
                        state <= START;
                        shift_reg <= tx_data;
                        tx_busy <= 1;
                        timer <= 0;
                    end
                end
                
                START: begin
                    tx <= 1'b0; 
                    if (timer == BAUD_TICK) begin
                        state <= DATA;
                        timer <= 0;
                        bit_index <= 0;
                    end else begin
                        timer <= timer + 1;
                    end
                end
                
                DATA: begin
                    tx <= shift_reg[0]; 
                    if (timer == BAUD_TICK) begin
                        timer <= 0;
                        shift_reg <= {1'b0, shift_reg[7:1]}; 
                        
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
                    tx <= 1'b1; 
                    if (timer == BAUD_TICK) begin
                        state <= IDLE;
                    end else begin
                        timer <= timer + 1;
                    end
                end
            endcase
        end
    end
endmodule