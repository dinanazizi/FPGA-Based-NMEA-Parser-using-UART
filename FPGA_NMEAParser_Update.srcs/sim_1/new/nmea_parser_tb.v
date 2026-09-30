`timescale 1ns / 1ps

module tb_nmea_parser();

    reg sysclk;
    reg btn_rst;
    reg uart_rxd;
    wire uart_txd;
    wire eth_rst_b;
    wire led0, led1, led2, led3;

    nmea_parser uut (
        .sysclk(sysclk), .btn_rst(btn_rst), .uart_rxd(uart_rxd),
        .uart_txd(uart_txd), .eth_rst_b(eth_rst_b),
        .led0(led0), .led1(led1), .led2(led2), .led3(led3)
    );

    initial begin
        sysclk = 0;
        forever #4 sysclk = ~sysclk; 
    end

    // Disesuaikan agar langsung menembak ke dalam modul uart_rx (receiver_inst)
    task inject_char;
        input [7:0] char_in;
        begin
            force uut.receiver_inst.rx_data = char_in;
            force uut.receiver_inst.rx_ready = 1'b1;
            #8; 
            force uut.receiver_inst.rx_ready = 1'b0;
            #40; 
        end
    endtask

    // String penuh 87 Karakter ($GPGGA...)
    reg [8*87-1:0] msg = "$GPGGA,172814.0,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0 0031*4F";
    integer i;
    reg [7:0] current_char;

    initial begin
        btn_rst = 1;
        uart_rxd = 1; 
        
        #100 btn_rst = 0; 
        #100;

        $display("========================================");
        $display("      INJECTING DUMMY DATA........      ");
        $display("========================================");

        for (i = 87; i > 0; i = i - 1) begin
            current_char = msg[ ((i-1)*8) +: 8 ];
            inject_char(current_char);
            
            $display("-> Mesin menangkap huruf: '%c' | Posisi State: %d | Koma ke-: %d", 
                      current_char, uut.current_state, uut.comma_buffer);
        end
        
        #200;
        
        $display("\n========================================");
        $display("             PARSED DATA                ");
        $display("========================================");
        
        $display("Message ID   : %c%c%c%c%c%c", 
                 uut.message_id_buffer[0], uut.message_id_buffer[1], uut.message_id_buffer[2], 
                 uut.message_id_buffer[3], uut.message_id_buffer[4], uut.message_id_buffer[5]);
                 
        $display("Waktu (Time) : %c%c%c%c%c%c%c%c", 
                 uut.time_buffer[0], uut.time_buffer[1], uut.time_buffer[2], uut.time_buffer[3], 
                 uut.time_buffer[4], uut.time_buffer[5], uut.time_buffer[6], uut.time_buffer[7]);
                 
        $display("Latitude     : %c%c%c%c%c%c%c%c%c%c%c%c%c", 
                 uut.lat_buffer[0], uut.lat_buffer[1], uut.lat_buffer[2], uut.lat_buffer[3], 
                 uut.lat_buffer[4], uut.lat_buffer[5], uut.lat_buffer[6], uut.lat_buffer[7], 
                 uut.lat_buffer[8], uut.lat_buffer[9], uut.lat_buffer[10], uut.lat_buffer[11], uut.lat_buffer[12]);
                 
        $display("Lat Dir      : %c", uut.lat_dir_buffer[0]);
                 
        $display("Longitude    : %c%c%c%c%c%c%c%c%c%c%c%c%c%c", 
                 uut.lon_buffer[0], uut.lon_buffer[1], uut.lon_buffer[2], uut.lon_buffer[3], 
                 uut.lon_buffer[4], uut.lon_buffer[5], uut.lon_buffer[6], uut.lon_buffer[7], 
                 uut.lon_buffer[8], uut.lon_buffer[9], uut.lon_buffer[10], uut.lon_buffer[11], 
                 uut.lon_buffer[12], uut.lon_buffer[13]);
                 
        $display("Lon Dir      : %c", uut.lon_dir_buffer[0]);
        $display("GPS Quality  : %c", uut.gps_quality_buffer[0]);
        $display("Satellites   : %c", uut.sat_num_buffer[0]);
        
        $display("HDOP         : %c%c%c", 
                 uut.hdop_buffer[0], uut.hdop_buffer[1], uut.hdop_buffer[2]);
                 
        $display("Altitude     : %c%c%c%c%c%c", 
                 uut.alt_buffer[0], uut.alt_buffer[1], uut.alt_buffer[2], 
                 uut.alt_buffer[3], uut.alt_buffer[4], uut.alt_buffer[5]);
                 
        $display("----------------------------------------");
        $display("Checksum Valid Status : %b", uut.checksum_valid_flag);
        $display("========================================\n");
        
        release uut.receiver_inst.rx_data;
        release uut.receiver_inst.rx_ready;
        
        $finish;
    end
endmodule