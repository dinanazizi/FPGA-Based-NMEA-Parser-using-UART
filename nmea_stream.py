import serial
import time

SERIAL_PORT = 'COM9'
BAUD_RATE = 115200

NUM_FIELDS = 10
FIELD_LABELS = [
    "MsgID", "Time", "Lat", "LatDir", "Lon",
    "LonDir", "Quality", "Sat", "HDOP", "Alt"
]

# Perhatikan: field terakhir pakai koma (bukan spasi) - lihat pembahasan checksum sebelumnya
NMEA_SENTENCE = "$GPGGA,172814.0,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4F\r\n"


def main():
    fpga_serial = None
    try:
        fpga_serial = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0.2)
        print(f"[*] Berhasil terhubung ke FPGA di {SERIAL_PORT} @ {BAUD_RATE} bps")
        time.sleep(2)  # jeda supaya koneksi serial stabil

        print("\n[+] Memulai streaming data NMEA ke FPGA (Simulasi 1 Hz)...")
        print("[!] Tekan Ctrl+C kapan saja untuk menghentikan program.\n")

        count = 0
        while True:
            count += 1

            # Buang sisa byte lama di buffer RX (misal sisa balasan yang
            # belum sempat terbaca dari pengiriman sebelumnya), supaya
            # pembacaan kali ini benar-benar mulai dari awal sentence baru.
            fpga_serial.reset_input_buffer()

            fpga_serial.write(NMEA_SENTENCE.encode('ascii'))

            # FPGA mengirim tepat NUM_FIELDS baris, masing-masing diakhiri \r\n
            lines = []
            for _ in range(NUM_FIELDS):
                line = fpga_serial.readline()  # blocking sampai '\n' atau timeout
                if not line:
                    break
                lines.append(line.decode('ascii', errors='ignore').strip())

            if len(lines) == NUM_FIELDS:
                print(f"[{count}] Mengirim NMEA -> Balasan FPGA:")
                for label, val in zip(FIELD_LABELS, lines):
                    print(f"    {label:8s}: {val}")
            elif lines:
                print(f"[{count}] Balasan FPGA tidak lengkap ({len(lines)}/{NUM_FIELDS} baris): {lines}")
            else:
                print(f"[{count}] FPGA tidak membalas (kemungkinan checksum invalid).")

            time.sleep(1)  # simulasi update 1 Hz

    except serial.SerialException as e:
        print(f"Error Koneksi Serial: {e}")
    except KeyboardInterrupt:
        print("\n[!] Streaming dihentikan oleh pengguna (Ctrl+C).")
    finally:
        if fpga_serial is not None and fpga_serial.is_open:
            fpga_serial.close()
            print("[*] Port serial telah ditutup dengan aman. Goodbye!")


if __name__ == "__main__":
    main()