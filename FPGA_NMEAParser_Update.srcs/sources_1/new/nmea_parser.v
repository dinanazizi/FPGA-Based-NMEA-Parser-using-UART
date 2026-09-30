`timescale 1ns / 1ps
// =============================================================================
// NMEA Parser - REVISI v3
// Perubahan dari revisi v2:
//   - led0 sekarang jadi indikator WATCHDOG "tidak ada data masuk":
//     * Timer di-reset ke 0 setiap kali ada 1 byte diterima (rx_ready),
//       di state APA PUN (bukan cuma saat IDLE) - supaya kalau parser
//       nyangkut di tengah sentence yang tidak pernah selesai pun tetap
//       terhitung sebagai "masih ada aktivitas data".
//     * Kalau timer mencapai NO_DATA_TIMEOUT_CYCLES (5 detik @ CLK_FREQ)
//       tanpa ada rx_ready sama sekali, led0 menyala dan tetap menyala
//       sampai ada byte baru masuk lagi.
//   - Semua fix/fitur sebelumnya tetap dipertahankan (synchronizer 2-FF,
//     checksum standar, buffer-clear di IDLE, gating checksum-valid,
//     kirim semua field per baris via CRLF).
// =============================================================================

module nmea_parser #(
    parameter CLK_FREQ = 125000000,   // harus sama dengan parameter di uart_rx/uart_tx
    parameter NO_DATA_TIMEOUT_SEC = 5 // ambang waktu "tidak ada data" dalam detik
)(
    input wire sysclk,
    input wire btn_rst,
    input wire uart_rxd,
    output wire uart_txd,
    output wire eth_rst_b,
    output wire led0,
    output wire led1,
    output wire led2,
    output wire led3
);

    assign eth_rst_b = 1'b1;

    // Synchronizer 2-FF untuk sinyal uart_rxd (asinkron terhadap sysclk)
    reg uart_rxd_meta, uart_rxd_sync;
    always @(posedge sysclk or posedge btn_rst) begin
        if (btn_rst) begin
            uart_rxd_meta <= 1'b1;
            uart_rxd_sync <= 1'b1;
        end else begin
            uart_rxd_meta <= uart_rxd;
            uart_rxd_sync <= uart_rxd_meta;
        end
    end

    localparam IDLE         = 3'd0;
    localparam START        = 3'd1;
    localparam READ_FIELD   = 3'd2;
    localparam CHECKSUM     = 3'd3;
    localparam DONE_OUTPUT  = 3'd4;

    reg [2:0] current_state, next_state;

    wire [7:0] rx_data;
    wire rx_ready;

    reg tx_start_signal;
    reg [7:0] data_to_send;
    wire tx_is_busy;

    wire is_dollar = (rx_data == 8'h24); // '$'
    wire is_comma  = (rx_data == 8'h2C); // ','
    wire is_star   = (rx_data == 8'h2A); // '*'

    reg [7:0] calculated_checksum;
    wire checksum_valid_internal;
    reg checksum_valid_flag;
    reg checksum_error_flag;

    // Deklarasi Buffer
    reg [7:0] message_id_buffer  [0:5];
    reg [7:0] time_buffer        [0:14];
    reg [7:0] lat_buffer         [0:14];
    reg [7:0] lat_dir_buffer     [0:0];
    reg [7:0] lon_buffer         [0:14];
    reg [7:0] lon_dir_buffer     [0:0];
    reg [7:0] gps_quality_buffer [0:0];
    reg [7:0] sat_num_buffer     [0:0];
    reg [7:0] hdop_buffer        [0:2];
    reg [7:0] alt_buffer         [0:5];

    reg [3:0] comma_buffer;
    reg [4:0] char_index;
    reg [1:0] chk_count;
    reg [7:0] char_hex1_buffer;
    reg [7:0] char_hex2_buffer;

    // --- Register untuk pengiriman multi-field, satu field per baris ---
    reg [3:0] field_sel;
    reg [4:0] byte_in_field;
    reg [1:0] crlf_phase;

    localparam FLD_MSGID   = 4'd0;
    localparam FLD_TIME    = 4'd1;
    localparam FLD_LAT     = 4'd2;
    localparam FLD_LATDIR  = 4'd3;
    localparam FLD_LON     = 4'd4;
    localparam FLD_LONDIR  = 4'd5;
    localparam FLD_QUALITY = 4'd6;
    localparam FLD_SATNUM  = 4'd7;
    localparam FLD_HDOP    = 4'd8;
    localparam FLD_ALT     = 4'd9;

    // --- Watchdog "tidak ada data" untuk led0 ---
    localparam integer NO_DATA_TIMEOUT_CYCLES = CLK_FREQ * NO_DATA_TIMEOUT_SEC; // 625_000_000 @ default
    reg [31:0] no_data_timer;
    reg        no_data_flag;

    always @(posedge sysclk or posedge btn_rst) begin
        if (btn_rst) begin
            no_data_timer <= 32'd0;
            no_data_flag  <= 1'b0;
        end else if (rx_ready) begin
            // Ada byte masuk (di state apa pun) -> reset timer & matikan flag
            no_data_timer <= 32'd0;
            no_data_flag  <= 1'b0;
        end else if (no_data_timer < NO_DATA_TIMEOUT_CYCLES) begin
            no_data_timer <= no_data_timer + 1'b1;
        end else begin
            no_data_flag <= 1'b1; // sudah >= 5 detik tanpa data sama sekali
        end
    end

    integer i, j;

    assign led0 = no_data_flag;          // <-- BERUBAH: sekarang indikator "tidak ada data"
    assign led1 = checksum_valid_flag;
    assign led2 = checksum_error_flag;
    assign led3 = rx_ready;

    // Ambil 1 byte dari field yang dipilih (comb, hanya membaca buffer)
    function [7:0] get_field_byte;
        input [3:0] fsel;
        input [4:0] idx;
        begin
            case (fsel)
                FLD_MSGID:   get_field_byte = message_id_buffer[idx];
                FLD_TIME:    get_field_byte = time_buffer[idx];
                FLD_LAT:     get_field_byte = lat_buffer[idx];
                FLD_LATDIR:  get_field_byte = lat_dir_buffer[0];
                FLD_LON:     get_field_byte = lon_buffer[idx];
                FLD_LONDIR:  get_field_byte = lon_dir_buffer[0];
                FLD_QUALITY: get_field_byte = gps_quality_buffer[0];
                FLD_SATNUM:  get_field_byte = sat_num_buffer[0];
                FLD_HDOP:    get_field_byte = hdop_buffer[idx];
                FLD_ALT:     get_field_byte = alt_buffer[idx];
                default:     get_field_byte = 8'h20;
            endcase
        end
    endfunction

    // Panjang tiap field (jumlah karakter yang harus dikirim sebelum CRLF)
    function [4:0] get_field_len;
        input [3:0] fsel;
        begin
            case (fsel)
                FLD_MSGID:   get_field_len = 5'd6;
                FLD_TIME:    get_field_len = 5'd15;
                FLD_LAT:     get_field_len = 5'd15;
                FLD_LATDIR:  get_field_len = 5'd1;
                FLD_LON:     get_field_len = 5'd15;
                FLD_LONDIR:  get_field_len = 5'd1;
                FLD_QUALITY: get_field_len = 5'd1;
                FLD_SATNUM:  get_field_len = 5'd1;
                FLD_HDOP:    get_field_len = 5'd3;
                FLD_ALT:     get_field_len = 5'd6;
                default:     get_field_len = 5'd0;
            endcase
        end
    endfunction

    // Inisialisasi awal (hanya berlaku saat power-on/konfigurasi bitstream)
    initial begin
        lat_dir_buffer[0]     = 8'h20;
        lon_dir_buffer[0]     = 8'h20;
        gps_quality_buffer[0] = 8'h20;
        sat_num_buffer[0]     = 8'h20;
        for (i = 0; i < 6; i = i + 1)  message_id_buffer[i] = 8'h20;
        for (i = 0; i < 3; i = i + 1)  hdop_buffer[i]        = 8'h20;
        for (i = 0; i < 6; i = i + 1)  alt_buffer[i]         = 8'h20;
        for (i = 0; i < 15; i = i + 1) begin
            time_buffer[i] = 8'h20;
            lat_buffer[i]  = 8'h20;
            lon_buffer[i]  = 8'h20;
        end
    end

    // Sequential Block (FSM & Processing)
    always @(posedge sysclk or posedge btn_rst) begin
        if (btn_rst) begin
            current_state <= IDLE;
            calculated_checksum <= 8'd0;
            comma_buffer <= 4'd0;
            char_index <= 5'd0;
            chk_count <= 2'd0;
            char_hex1_buffer <= 8'h00;
            char_hex2_buffer <= 8'h00;
            field_sel <= 4'd0;
            byte_in_field <= 5'd0;
            crlf_phase <= 2'd0;
            tx_start_signal <= 1'b0;
            data_to_send <= 8'h00;
            checksum_valid_flag <= 1'b0;
            checksum_error_flag <= 1'b0;
        end else begin
            current_state <= next_state;

            // Bersihkan SEMUA state & buffer setiap kali di IDLE
            if (current_state == IDLE) begin
                calculated_checksum <= 8'd0;
                comma_buffer <= 4'd0;
                char_index <= 5'd0;
                field_sel <= 4'd0;
                byte_in_field <= 5'd0;
                crlf_phase <= 2'd0;
                tx_start_signal <= 1'b0;

                lat_dir_buffer[0]     <= 8'h20;
                lon_dir_buffer[0]     <= 8'h20;
                gps_quality_buffer[0] <= 8'h20;
                sat_num_buffer[0]     <= 8'h20;
                for (j = 0; j < 6; j = j + 1)  message_id_buffer[j] <= 8'h20;
                for (j = 0; j < 3; j = j + 1)  hdop_buffer[j]        <= 8'h20;
                for (j = 0; j < 6; j = j + 1)  alt_buffer[j]         <= 8'h20;
                for (j = 0; j < 15; j = j + 1) begin
                    time_buffer[j] <= 8'h20;
                    lat_buffer[j]  <= 8'h20;
                    lon_buffer[j]  <= 8'h20;
                end
            end

            // Proses Ekstraksi Data NMEA Berdasarkan Koma (READ_FIELD)
            if (current_state == READ_FIELD && rx_ready) begin
                if (!is_star) begin
                    calculated_checksum <= calculated_checksum ^ rx_data;
                end

                if (is_comma) begin
                    comma_buffer <= comma_buffer + 1;
                    char_index <= 5'd0;
                end
                else if (!is_star) begin
                    case (comma_buffer)
                        4'd0: begin
                            if (char_index < 6) message_id_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        4'd1: begin
                            if (char_index < 15) time_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        4'd2: begin
                            if (char_index < 15) lat_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        4'd3: begin
                            if (char_index < 1) lat_dir_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        4'd4: begin
                            if (char_index < 15) lon_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        4'd5: begin
                            if (char_index < 1) lon_dir_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        4'd6: begin
                            if (char_index < 1) gps_quality_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        4'd7: begin
                            if (char_index < 1) sat_num_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        4'd8: begin
                            if (char_index < 3) hdop_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        4'd9: begin
                            if (char_index < 6) alt_buffer[char_index] <= rx_data;
                            char_index <= char_index + 1;
                        end
                        default: ;
                    endcase
                end
            end

            // Proses Menangkap 2 Karakter Checksum (CHECKSUM)
            if (current_state == CHECKSUM) begin
                if (rx_ready) begin
                    if (chk_count == 2'd0) begin
                        char_hex1_buffer <= rx_data;
                        chk_count <= 2'd1;
                    end else if (chk_count == 2'd1) begin
                        char_hex2_buffer <= rx_data;
                        chk_count <= 2'd2;
                    end
                end

                if (chk_count == 2'd2) begin
                    checksum_valid_flag <= checksum_valid_internal;
                    checksum_error_flag <= ~checksum_valid_internal;
                end
            end else if (current_state != CHECKSUM) begin
                chk_count <= 2'd0;
            end

            // ---------------------------------------------------------
            // DONE_OUTPUT: kirim semua field, satu field per baris (CRLF)
            // ---------------------------------------------------------
            if (current_state == DONE_OUTPUT) begin
                if (!tx_is_busy && !tx_start_signal) begin
                    case (crlf_phase)
                        2'd0: begin
                            if (byte_in_field < get_field_len(field_sel)) begin
                                data_to_send <= get_field_byte(field_sel, byte_in_field);
                                tx_start_signal <= 1'b1;
                                byte_in_field <= byte_in_field + 1'b1;
                            end else begin
                                data_to_send <= 8'h0D; // '\r'
                                tx_start_signal <= 1'b1;
                                crlf_phase <= 2'd1;
                            end
                        end
                        2'd1: begin
                            data_to_send <= 8'h0A; // '\n'
                            tx_start_signal <= 1'b1;
                            crlf_phase <= 2'd2;
                        end
                        2'd2: begin
                            tx_start_signal <= 1'b0;
                            if (field_sel < FLD_ALT) begin
                                field_sel <= field_sel + 1'b1;
                                byte_in_field <= 5'd0;
                                crlf_phase <= 2'd0;
                            end else begin
                                crlf_phase <= 2'd3;
                            end
                        end
                        default: tx_start_signal <= 1'b0;
                    endcase
                end else begin
                    tx_start_signal <= 1'b0;
                end
            end
        end
    end

    // Combinational Block (FSM Next State Logic)
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (rx_ready && is_dollar) next_state = START;
            end
            START: begin
                next_state = READ_FIELD;
            end
            READ_FIELD: begin
                if (rx_ready && is_star) next_state = CHECKSUM;
            end
            CHECKSUM: begin
                if (chk_count == 2'd2) begin
                    next_state = checksum_valid_internal ? DONE_OUTPUT : IDLE;
                end
            end
            DONE_OUTPUT: begin
                if (crlf_phase == 2'd3 && !tx_is_busy) begin
                    next_state = IDLE;
                end else begin
                    next_state = DONE_OUTPUT;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // Instansiasi Sub-Modul
    uart_rx #(
        .CLK_FREQ(CLK_FREQ)
    ) receiver_inst (
        .clk(sysclk),
        .rst(btn_rst),
        .rx(uart_rxd_sync),
        .rx_data(rx_data),
        .rx_ready(rx_ready)
    );

    checksum_validator chk_inst (
        .calculated_checksum(calculated_checksum),
        .char_hex1(char_hex1_buffer),
        .char_hex2(char_hex2_buffer),
        .is_valid(checksum_valid_internal)
    );

    uart_tx #(
        .CLK_FREQ(CLK_FREQ)
    ) transmitter_inst (
        .clk(sysclk),
        .rst(btn_rst),
        .tx_start(tx_start_signal),
        .tx_data(data_to_send),
        .tx(uart_txd),
        .tx_busy(tx_is_busy)
    );

endmodule


`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ = 125000000,
    parameter BAUD_RATE = 115200
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