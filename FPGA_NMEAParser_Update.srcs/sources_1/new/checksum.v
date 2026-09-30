`timescale 1ns / 1ps

module checksum_validator(
    input wire [7:0] calculated_checksum, 
    input wire [7:0] char_hex1,           
    input wire [7:0] char_hex2,           
    output wire is_valid                  
);

    function [3:0] ascii_to_hex;
        input [7:0] ascii_char;
        begin
            if (ascii_char >= 8'h30 && ascii_char <= 8'h39)
                ascii_to_hex = ascii_char - 8'h30;
            else if (ascii_char >= 8'h41 && ascii_char <= 8'h46)
                ascii_to_hex = ascii_char - 8'h37;
            else if (ascii_char >= 8'h61 && ascii_char <= 8'h66)
                ascii_to_hex = ascii_char - 8'h57;
            else 
                ascii_to_hex = 4'd0;
        end
    endfunction

    wire [7:0] expected_checksum = {ascii_to_hex(char_hex1), ascii_to_hex(char_hex2)};
    assign is_valid = (calculated_checksum == expected_checksum);

endmodule