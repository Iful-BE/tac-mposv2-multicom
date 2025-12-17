import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:mposv2/screens/transaction_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock/wakelock.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:collection/collection.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import 'package:image/image.dart' as img;

class TransactionScreen extends StatefulWidget {
  const TransactionScreen({super.key});

  @override
  _TransactionScreenState createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  List<dynamic> transactions = [];
  DateTime selectedDate = DateTime.now();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String errorText = '';

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    _fetchTransactionData(selectedDate: selectedDate);
    _loadSavedPrinter();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<String?> getDomainFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('domain');
  }

  Future<String?> getBranchFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_branch_name');
  }

  Future<String?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('session_id');
  }

  Future<String?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  Future<String?> getPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_phone');
  }

  Future<String?> customerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('customer_name');
  }

  String formatRupiah(double amount) {
    final format =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return format.format(amount);
  }

  String getFormattedDate() {
    final now = DateTime.now();
    final formatter = DateFormat('dd-MM-yy HH:mm');
    return formatter.format(now); // contoh hasil: 23-07-25 08:00
  }

  Future<void> _loadSavedPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString('printer_address');
      if (address != null) {
        final devices = await printer.getBondedDevices();

        selectedDevice = devices.firstWhereOrNull((d) => d.address == address);

        if (selectedDevice != null) {
          final bool? alreadyConnected = await printer.isConnected;
          if (alreadyConnected == true) {
            setState(() => isConnected = true);
          } else {
            await _connectToPrinter();
          }
        } else {
          await _clearSavedPrinter();
          _showMessage("Printer tersimpan tidak ditemukan.");
        }
      } else {
        _showMessage("Alamat printer belum disimpan.");
      }
    } catch (e) {
      _showMessage("Error memuat printer: $e");
    }
  }

  Future<void> _connectToPrinter() async {
    if (selectedDevice != null) {
      try {
        final bool? alreadyConnected = await printer.isConnected;
        if (alreadyConnected != true) {
          await printer.connect(selectedDevice!);
          setState(() => isConnected = true);
          //_showMessage("Terhubung ke ${selectedDevice!.name}");
        }
      } catch (e) {
        setState(() => isConnected = false);
        _showMessage("Gagal terhubung ke printer: $e");
      }
    } else {
      _showMessage("Tidak ada printer yang dipilih.");
    }
  }

  Future<void> _clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('printer_address');
  }

  Future<void> _printLogo() async {
    final prefs = await SharedPreferences.getInstance();
    final base64Logo = prefs.getString("logo_base64");
    final width = prefs.getInt("logo_width") ?? 200;
    final height = prefs.getInt("logo_height");

    if (base64Logo != null) {
      try {
        Uint8List logoBytes = base64Decode(base64Logo);
        final image = img.decodeImage(logoBytes);

        if (image != null) {
          final resized = img.copyResize(
            image,
            width: width,
            height: height, // null = auto
          );

          final resizedBytes = Uint8List.fromList(img.encodePng(resized));
          await printer.printImageBytes(resizedBytes);
        }
      } catch (e) {
        debugPrint("Gagal decode logo dari cache: $e");
      }
    } else {
      debugPrint("Logo belum diset di cache!");
    }
  }

  List<int> imageToRasterEscPos(img.Image image) {
    final bytes = <int>[];
    final widthBytes = (image.width + 7) ~/ 8;
    final height = image.height;

    for (var y = 0; y < height; y++) {
      bytes.addAll(
          [29, 118, 48, 0, widthBytes & 0xFF, (widthBytes >> 8) & 0xFF, 1, 0]);

      for (var x = 0; x < widthBytes * 8; x += 8) {
        int byte = 0;
        for (var b = 0; b < 8; b++) {
          if (x + b >= image.width) continue;

          final px = image.getPixel(x + b, y);
          final r = px.r.toInt();
          final g = px.g.toInt();
          final bl = px.b.toInt();
          final luma = ((299 * r + 587 * g + 114 * bl) / 1000).round();

          if (luma < 128) {
            byte |= (1 << (7 - b));
          }
        }
        bytes.add(byte);
      }
    }
    return bytes;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> commandReprint(idPos) async {
    // Aktifkan wakelock agar layar tidak tidur
    await Wakelock.enable();
    try {
      var connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult == ConnectivityResult.none) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("Tidak ada koneksi internet. Cek jaringan dan coba lagi."),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      bool printCustomer = prefs.getBool('print_customer') ?? true;

      final token = await getToken();
      final domain = await getDomainFromLocalStorage();

      if (domain == null) {
        print('Domain or Sub-Branch not found');
        return;
      }

      final url = Uri.parse('$domain/api/reprint-receipt');

      // Ensure that values are properly formatted
      Map<String, dynamic> body = {};

      body = {
        'id_pos': idPos ?? '',
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (printCustomer) {
          for (int i = 0; i < 1; i++) {
            if (data['data']['postHeader']['payment'] == 300) {
              await _printCompliment(data);
            } else {
              if (Platform.isWindows) {
                await _printReceiptWindows(data);
              } else {
                await _printReceipt(data);
              }
            }
          }
        }
      } else {
        print('Payment failed with status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error during payment: $e');
    } finally {
      // Matikan wakelock setelah semua proses selesai
      await Wakelock.disable();
    }
  }

  Future<void> commandCO(idPos) async {
    // Aktifkan wakelock agar layar tidak tidur
    await Wakelock.enable();
    try {
      var connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult == ConnectivityResult.none) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("Tidak ada koneksi internet. Cek jaringan dan coba lagi."),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      int printCaptainQty = prefs.getInt('print_captain_qty') ?? 1;

      final token = await getToken();
      final domain = await getDomainFromLocalStorage();

      if (domain == null) {
        print('Domain or Sub-Branch not found');
        return;
      }

      final url = Uri.parse('$domain/api/reprint-receipt');

      // Ensure that values are properly formatted
      Map<String, dynamic> body = {};

      body = {
        'id_pos': idPos ?? '',
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        for (int i = 0; i < printCaptainQty; i++) {
          await _printCaptainOrder(data);
        }
      } else {
        print('Payment failed with status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error during payment: $e');
    } finally {
      // Matikan wakelock setelah semua proses selesai
      await Wakelock.disable();
    }
  }

  Future<void> _printReceipt(Map<String, dynamic> data) async {
    if (isConnected) {
      await Wakelock.enable();
      String formatRupiah(double amount) {
        final formatter = NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp.', decimalDigits: 0);
        return formatter.format(amount);
      }

      try {
        final header = data['data']['postHeader'];
        final details = data['data']['postDetails'];
        final addr = data['data']['address'];
        final splitPayments = data['data']['split_payments'];
        final dynamicTableId = details.first['table_id'];
        final guestStr = header['total_guest']?.toString();

        // Data pembayaran dari backend
        final currentTime = getFormattedDate();
        DateTime dateTime = DateTime.parse(header['created_at']!).toLocal();
        String formattedDateTime =
            DateFormat('dd-MM-yyyy HH:mm:ss').format(dateTime);
        // Mengambil ID dan memotong  tanpa 4 angka terakhir
        String idPostHeader = header['id_post_header'].toString();
        String idsession = idPostHeader.substring(0, idPostHeader.length - 4);
        //mengambil data 4 angka terakhir
        String idPostHeader2 = header['id_post_header'].toString();
        String lastFourDigits =
            idPostHeader2.split('').reversed.take(4).toList().reversed.join('');

        printer.printCustom("", 1, 1);
        printer.printCustom("", 1, 1);
        await _printLogo();
        printer.printNewLine();
        printer.printCustom("${addr['bname']}", 1, 1);
        printer.printCustom("${addr['device_addr']}", 1, 1);
        printer.printCustom("${addr['descript']}", 1, 1);
        printer.printCustom("--Reprint on--", 1, 1);
        printer.printCustom(currentTime, 1, 1);
        printer.printNewLine();
        printer.printCustom("Kasir   : ${header['kasir_name']}", 1, 0);
        printer.printCustom("Tanggal : $formattedDateTime", 1, 0);
        printer.printCustom(
            "Id      : $idsession", 1, 0); // ID tanpa 4 angka terakhir
        printer.printCustom(
            "Struk   : $lastFourDigits", 1, 0); // 4 angka terakhir
        if (header['customer'] != null &&
            header['customer'].toString().isNotEmpty) {
          printer.printCustom(
            "Customer: ${header['customer']}",
            1,
            0,
          );
        }
        if (header['nowa'] != null && header['nowa'].toString().isNotEmpty) {
          printer.printCustom(
            "Phone   : +62${header['nowa']}",
            1,
            0,
          );
        }
        printer.printCustom("Type    : ${header['order_type']}", 1, 0);
        if (dynamicTableId != null &&
            dynamicTableId.isNotEmpty &&
            dynamicTableId != '0') {
          printer.printCustom(
            "Table   : $dynamicTableId - ${guestStr ?? '-'} Pax",
            1,
            0,
          );
        }

        printer.printNewLine();
        printer.printCustom("Item        Qty    Harga", 1, 0);
        for (var item in details) {
          String itemName = item['name'].toString().toUpperCase();
          String itemQty = item['quantity'].toString();
          String itemPrice = formatRupiah(double.parse(item['price']));
          String itemTotal =
              formatRupiah(double.parse(item['price']) * item['quantity']);

          printer.printCustom(itemName, 1, 0);
          printer.printCustom("$itemQty x $itemPrice = $itemTotal", 1, 0);
        }

        printer.printNewLine();
        //parsing data

        String ket = (header['description'] ?? "").toString();
        // Parsing ke double agar aman dari error
        double subTotal = double.parse(header['sub_total'].toString());
        double rounding = double.parse(header['rounding'].toString());
        double tax = double.parse(header['tax'].toString());
        double svc = double.parse(header['service_charge'].toString());
        double grandTotal = double.parse(header['grand_total'].toString());
        double paid = double.parse(header['paid'].toString());
        double discount = double.parse(header['discount'].toString());
        double kembali = paid - grandTotal;
        // Cetak subtotal, pajak, total, dibayar, dan kembalian dengan format rupiah
        printer.printCustom("Subtotal  : ${formatRupiah(subTotal)}", 1, 0);
        printer.printCustom("Discount  : ${formatRupiah(discount)}", 1, 0);
        printer.printCustom("Srv Charge: ${formatRupiah(svc)}", 1, 0);
        printer.printCustom("PB1       : ${formatRupiah(tax)}", 1, 0);
        printer.printCustom("Rounded   : ${formatRupiah(rounding)}", 1, 0);
        printer.printCustom("Total     : ${formatRupiah(grandTotal)}", 1, 0);
        // SPLIT PAYMENT
        if (splitPayments != null &&
            splitPayments is List &&
            splitPayments.isNotEmpty) {
          printer.printCustom("Split Payment", 1, 0);

          for (var p in splitPayments) {
            String method = (p['pay_method'] ?? '-').toString().toUpperCase();
            double amount = double.tryParse(p['amount'].toString()) ?? 0;

            // DP FLAG (perbaikan disini)
            bool isDP = (p['is_down_payment'] ?? 0) == 1;
            if (isDP) method = "$method (DP)";
            // Cetak metode
            printer.printCustom("$method : ${formatRupiah(amount)}", 1, 0);
          }
        } else {
          if (header['type'].isEmpty) {
            printer.printCustom("Payment   : CASH", 1, 0);
            printer.printCustom("Paid      : ${formatRupiah(paid)}", 1, 0);
            printer.printCustom("Change    : ${formatRupiah(kembali)}", 1, 0);
          } else {
            printer.printCustom("Payment   : Non CASH", 1, 0);

            if (header['type'].isNotEmpty) {
              printer.printCustom("Tipe      : ${header['type']}", 1, 0);
              printer.printCustom("Paid      : ${formatRupiah(paid)}", 1, 0);
            }
          }
        }
        printer.printNewLine();
        printer.printCustom("Keterangan: $ket", 1, 0);
        printer.printNewLine();
        printer.printCustom("Terimakasih!\n\n", 1, 1);
        printer.printCustom("", 1, 1);
        printer.printCustom("", 1, 1);
        printer.printCustom("", 1, 1);
        sendRawCutCommand();
      } catch (e) {
        _showMessage("Error saat mencetak: $e");
      } finally {
        // Setelah selesai, izinkan sleep lagi
        await Wakelock.disable();
      }
    } else {
      _showMessage("Printer belum terhubung!");
    }
  }

  Future<void> printCaptainToLAN(String ipAddress, String content,
      {int port = 9100}) async {
    try {
      final socket = await Socket.connect(ipAddress, port,
          timeout: const Duration(seconds: 5));
      final List<int> bytes = [];

      bytes.addAll([0x1B, 0x40]); // Init
      bytes.addAll([0x1B, 0x61, 0x01]); // Center
      bytes.addAll(utf8.encode("CAPTAIN ORDER\n"));
      bytes.addAll([0x1B, 0x61, 0x00]); // Left
      bytes.addAll(utf8.encode(content));
      bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x0A]);
      bytes.addAll([0x1D, 0x56, 0x00]); // Cut
      socket.add(Uint8List.fromList(bytes));
      await socket.flush();
      await socket.close();
    } catch (e) {
      print("Gagal cetak ke $ipAddress: $e");
    }
  }

  Future<void> _printCompliment(Map<String, dynamic> data) async {
    if (isConnected) {
      await Wakelock.enable();
      String formatRupiah(double amount) {
        final formatter = NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp.', decimalDigits: 0);
        return formatter.format(amount);
      }

      try {
        final header = data['data']['postHeader'];
        final details = data['data']['postDetails'];
        final addr = data['data']['address'];
        final dynamicTableId = details.first['table_id'];
        final guestStr = header['total_guest']?.toString();
        // Data pembayaran dari backend
        final currentTime = getFormattedDate();
        DateTime dateTime = DateTime.parse(header['created_at']!).toLocal();
        String formattedDateTime =
            DateFormat('dd-MM-yyyy HH:mm:ss').format(dateTime);
        // Mengambil ID dan memotong  tanpa 4 angka terakhir
        String idPostHeader = header['id_post_header'].toString();
        String idsession = idPostHeader.substring(0, idPostHeader.length - 4);
        //mengambil data 4 angka terakhir
        String idPostHeader2 = header['id_post_header'].toString();
        String lastFourDigits =
            idPostHeader2.split('').reversed.take(4).toList().reversed.join('');

        printer.printCustom("", 1, 1);
        printer.printCustom("", 1, 1);
        await _printLogo();
        printer.printNewLine();
        printer.printCustom("${addr['bname']}", 1, 1);
        printer.printCustom("${addr['device_addr']}", 1, 1);
        printer.printCustom("${addr['descript']}", 1, 1);
        printer.printCustom("--Reprint on--", 1, 1);
        printer.printCustom(currentTime, 1, 1);
        printer.printNewLine();
        printer.printCustom("Kasir   : ${header['kasir_name']}", 1, 0);
        printer.printCustom("Tanggal : $formattedDateTime", 1, 0);
        printer.printCustom(
            "Id      : $idsession", 1, 0); // ID tanpa 4 angka terakhir
        printer.printCustom(
            "Struk   : $lastFourDigits", 1, 0); // 4 angka terakhir
        if (header['customer'] != null &&
            header['customer'].toString().isNotEmpty) {
          printer.printCustom(
            "Customer: ${header['customer']}",
            1,
            0,
          );
        }
        if (header['nowa'] != null && header['nowa'].toString().isNotEmpty) {
          printer.printCustom(
            "Phone   : +62${header['nowa']}",
            1,
            0,
          );
        }
        printer.printCustom("Type    : ${header['order_type']}", 1, 0);
        if (dynamicTableId != null &&
            dynamicTableId.isNotEmpty &&
            dynamicTableId != '0') {
          printer.printCustom(
            "Table   : $dynamicTableId - ${guestStr ?? '-'} Pax",
            1,
            0,
          );
        }

        printer.printNewLine();
        printer.printCustom("Item        Qty    Harga", 1, 0);
        for (var item in details) {
          String itemName = item['name'].toString().toUpperCase();
          String itemQty = item['quantity'].toString();
          String itemPrice = formatRupiah(double.parse(item['price']));
          String itemTotal =
              formatRupiah(double.parse(item['price']) * item['quantity']);

          printer.printCustom(itemName, 1, 0);
          printer.printCustom("$itemQty x $itemPrice = $itemTotal", 1, 0);
        }

        printer.printNewLine();
        //parsing data

        String ket = (header['description'] ?? "").toString();
        String cpl = (header['compliment'] ?? "").toString();
        double grandTotal = double.parse(header['grand_total'].toString());
        // printer.printCustom("Pajak    : ${formatRupiah(tax)}", 1, 0);
        printer.printCustom("Total      : ${formatRupiah(grandTotal)}", 1, 0);
        printer.printCustom("Grand Total: 0", 1, 0);
        printer.printCustom("Payment    : Compliment", 1, 0);
        printer.printCustom("Compliment $cpl", 1, 0);
        printer.printNewLine();
        printer.printCustom("Keterangan : $ket", 1, 0);
        printer.printCustom("", 1, 1);
        const int paperWidth =
            32; // Ganti ke 48 jika printer kamu support 48 karakter
        String alignLeftRight(String left, String right,
            {int width = paperWidth}) {
          int space = width - left.length - right.length;
          if (space < 0) space = 1;
          return left + ' ' * space + right;
        }

        printer.printCustom("-" * paperWidth, 1, 1); // Garis horizontal
        printer.printCustom(alignLeftRight("Atas Nama", "Mengetahui"), 1,
            0); // Baris label tanda tangan
        printer.printCustom("\n\n\n", 1, 1); // Ruang tanda tangan
        printer.printCustom(alignLeftRight("__________", "__________"), 1,
            0); // Garis bawah tangan
        printer.printCustom("", 1, 1);
        printer.printCustom("", 1, 1);
        printer.printCustom("", 1, 1);
        sendRawCutCommand();
      } catch (e) {
        _showMessage("Error saat mencetak: $e");
      } finally {
        // Setelah selesai, izinkan sleep lagi
        await Wakelock.disable();
      }
    } else {
      _showMessage("Printer belum terhubung!");
    }
  }

  Future<void> _printCaptainOrder(Map<String, dynamic> data) async {
    if (!isConnected) {
      _showMessage("Printer belum terhubung!");
      return;
    }
    await Wakelock.enable();
    try {
      final header = data['data']['postHeader'];
      final details = data['data']['postDetails'];
      final currentTime = getFormattedDate();
      DateTime dateTime = DateTime.parse(header['created_at']!).toLocal();
      String formattedDateTime =
          DateFormat('dd-MM-yyyy HH:mm:ss').format(dateTime);
      String idPostHeader = header['id_post_header'].toString();
      String idsession = idPostHeader.substring(0, idPostHeader.length - 4);
      String lastFourDigits =
          idPostHeader.split('').reversed.take(4).toList().reversed.join('');

      final prefs = await SharedPreferences.getInstance();
      String customerName = prefs.getString('customer_name') ?? '-';
      String userPhone = prefs.getString('user_phone') ?? '-';

      if (userPhone.startsWith('0')) {
        userPhone = userPhone.replaceFirst('0', '+62');
      } else if (!userPhone.startsWith('+62')) {
        userPhone = '+62$userPhone';
      }

      // Settings
      String? ipDapur = prefs.getString('ip_printer_dapur');
      String? ipBar = prefs.getString('ip_printer_bar');
      int printQty = prefs.getInt('print_captain_qty') ?? 1;

      //Pisah produk
      List<String> listDapur = [];
      List<String> listBar = [];

      for (var item in details) {
        String name = item['name'].toString().toUpperCase();
        String qty = item['quantity'].toString();
        String kategori = item['print_co'].toString().toLowerCase();

        String line = "- $qty x $name";
        if (kategori == 'dapur') {
          listDapur.add(line);
        } else if (kategori == 'bar') {
          listBar.add(line);
        }
      }

      String commonHeader =
          "ID      : $idsession\nStruk   : $lastFourDigits\nCustomer: $customerName\nNo. HP  : $userPhone\nTanggal : $formattedDateTime\n";

      // Cetak ke Printer Bluetooth (hanya jika printCaptain == true)
      bool printCaptain = prefs.getBool('print_captain') ?? false;
      if (printCaptain) {
        // Cetak bagian Dapur
        if (listDapur.isNotEmpty) {
          printer.printNewLine();
          printer.printCustom("== DAPUR ==", 1, 1);
          printer.printCustom("--Reprint on--", 1, 1);
          printer.printCustom(currentTime, 1, 1);
          printer.printCustom(commonHeader, 1, 0);
          for (var line in listDapur) {
            printer.printCustom(line, 1, 0);
          }
          printer.printNewLine();
          printer.printCustom("------------------", 1, 1);
          printer.printCustom("", 1, 1);
          printer.printCustom("", 1, 1);
          printer.printCustom("", 1, 1);
          sendRawCutCommand();
        }

        // Cetak bagian Bar
        if (listBar.isNotEmpty) {
          printer.printNewLine();
          printer.printCustom("== BAR ==", 1, 1);
          printer.printCustom("--Reprint on--", 1, 1);
          printer.printCustom(currentTime, 1, 1);
          printer.printCustom(commonHeader, 1, 0);
          for (var line in listBar) {
            printer.printCustom(line, 1, 0);
          }
          printer.printNewLine();
          printer.printCustom("------------------", 1, 1);
          printer.printCustom("", 1, 1);
          printer.printCustom("", 1, 1);
          printer.printCustom("", 1, 1);
          sendRawCutCommand();
        }
      }

      // Cetak ke Printer LAN (hanya jika IP tersedia)
      if (ipDapur != null && ipDapur.isNotEmpty && listDapur.isNotEmpty) {
        String content = '$commonHeader${listDapur.join('\n')}\n\n';
        for (int i = 0; i < printQty; i++) {
          await printCaptainToLAN(ipDapur, content);
        }
        _showMessage("Captain Order berhasil dicetak (Bluetooth & LAN)");
      }

      if (ipBar != null && ipBar.isNotEmpty && listBar.isNotEmpty) {
        String content = '$commonHeader${listBar.join('\n')}\n\n';
        for (int i = 0; i < printQty; i++) {
          await printCaptainToLAN(ipBar, content);
        }
        _showMessage("Captain Order berhasil dicetak (Bluetooth & LAN)");
      }
    } catch (e) {
      _showMessage("Error saat mencetak: $e");
    } finally {
      // Setelah selesai, izinkan sleep lagi
      await Wakelock.disable();
    }

    //
  }

  Future<void> _printReceiptWindows(Map<String, dynamic> data) async {
    if (!Platform.isWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Test print hanya tersedia di Windows")),
      );
      return;
    }
    await Wakelock.enable();

    String formatRupiah(double amount) {
      final formatter = NumberFormat.currency(
          locale: 'id_ID', symbol: 'Rp.', decimalDigits: 0);
      return formatter.format(amount);
    }

    final prefs = await SharedPreferences.getInstance();
    final printerName = prefs.getString('usb_printer_name');

    if (printerName == null || printerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nama printer belum diatur")),
      );
      return;
    }

    final docName = 'Print Struk';
    final utf16Doc = docName.toNativeUtf16();
    final utf16PrinterName = printerName.toNativeUtf16();
    final hPrinter = calloc<HANDLE>();
    final jobInfo = calloc<DOC_INFO_1>()
      ..ref.pDocName = utf16Doc
      ..ref.pOutputFile = ffi.nullptr
      ..ref.pDatatype = "RAW".toNativeUtf16();

    ffi.Pointer<ffi.Uint8>? dataPtr;
    ffi.Pointer<ffi.Uint32>? bytesWrittenPtr;
    // Load logo dari asset atau file
    final dataLogo = await rootBundle.load("assets/tac-logo.png");
    final logo = img.decodePng(dataLogo.buffer.asUint8List())!;
    final logoBytes = imageToRasterEscPos(logo);

    try {
      final openResult = OpenPrinter(utf16PrinterName, hPrinter, ffi.nullptr);
      if (openResult == 0) {
        final err = GetLastError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal membuka printer. Error: $err")),
        );
        return;
      }

      final jobId = StartDocPrinter(hPrinter.value, 1, jobInfo.cast());
      if (jobId == 0) {
        final err = GetLastError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal memulai job print. Error: $err")),
        );
        ClosePrinter(hPrinter.value);
        return;
      }

      StartPagePrinter(hPrinter.value);

      // ===== Ambil data dari backend =====
      final header = data['data']['postHeader'];
      final details = data['data']['postDetails'];
      final addr = data['data']['address'];
      final currentTime = getFormattedDate();
      DateTime dateTime = DateTime.parse(header['created_at']!).toLocal();
      String formattedDateTime =
          DateFormat('dd-MM-yyyy HH:mm:ss').format(dateTime);

      String idPostHeader = header['id_post_header'].toString();
      String idsession = idPostHeader.substring(0, idPostHeader.length - 4);
      String lastFourDigits =
          idPostHeader.split('').reversed.take(4).toList().reversed.join('');

      // ===== Buat isi struk =====
      final headerText = StringBuffer();
      headerText.writeln("Treat A Cup");
      headerText.writeln("${addr}");
      headerText.writeln("@treatacup | 0823-1500-7324");
      headerText.writeln("--Reprint on--");
      headerText.writeln(currentTime);
      StringBuffer sb = StringBuffer();
      sb.writeln("");
      sb.writeln("Kasir   : ${header['kasir_name']}");
      sb.writeln("Tanggal : $formattedDateTime");
      sb.writeln("Id      : $idsession");
      sb.writeln("Struk   : $lastFourDigits");
      sb.writeln("Type    : ${header['order_type']}");
      sb.writeln("");
      sb.writeln("Item  Qty   Harga");

      for (var item in details) {
        String itemName = item['name'].toString().toUpperCase();
        String itemQty = item['quantity'].toString();
        String itemPrice = formatRupiah(double.parse(item['price'].toString()));
        String itemTotal = formatRupiah(
          double.parse(item['price'].toString()) * item['quantity'],
        );

        sb.writeln(itemName);
        sb.writeln(" $itemQty x $itemPrice = $itemTotal");
      }

      sb.writeln("");
      double subTotal = double.parse(header['sub_total'].toString());
      double rounding = double.parse(header['rounding'].toString());
      double tax = double.parse(header['tax'].toString());
      double svc = double.parse(header['service_charge'].toString());
      double grandTotal = double.parse(header['grand_total'].toString());
      double paid = double.parse(header['paid'].toString());
      double discount = double.parse(header['discount'].toString());
      double kembali = paid - grandTotal;

      sb.writeln("Subtotal  : ${formatRupiah(subTotal)}");
      sb.writeln("Discount  : ${formatRupiah(discount)}");
      sb.writeln("SrvCharge : ${formatRupiah(svc)}");
      sb.writeln("PB1       : ${formatRupiah(tax)}");
      sb.writeln("Rounded   : ${formatRupiah(rounding)}");
      sb.writeln("Total     : ${formatRupiah(grandTotal)}");

      String type = (header['type'] ?? "-").toString();
      if (type.isEmpty || type == "Cash") {
        sb.writeln("Payment   : CASH");
      } else {
        sb.writeln("Payment   : Non CASH");
        sb.writeln("Tipe      : $type");
        sb.writeln("Bank      : ${header['bank'] ?? "-"}");
        sb.writeln("Card      : ${header['card'] ?? "-"}");
        sb.writeln("Ref No    : ${header['ref_no'] ?? "-"}");
      }

      sb.writeln("Paid      : ${formatRupiah(paid)}");
      sb.writeln("Change    : ${formatRupiah(kembali)}");
      sb.writeln("");
      sb.writeln("Keterangan: ${header['description'] ?? ""}");
      sb.writeln("");
      sb.writeln("      Terimakasih!");
      sb.writeln("\n\n\n");

      // ===== Convert ke bytes ESC/POS =====
      final bytes = <int>[
        27, 64, // Reset printer

        27, 97, 1, // Center
        ...logoBytes,
        ...utf8.encode(headerText.toString()),

        10, // newline
        27, 97, 0, // Balik kiri lagi
        ...utf8.encode(sb.toString()),

        29, 86, 1, // Cut
      ];
      dataPtr = calloc<ffi.Uint8>(bytes.length);
      bytesWrittenPtr = calloc<ffi.Uint32>();

      final byteList = Uint8List.fromList(bytes);
      for (var i = 0; i < byteList.length; i++) {
        dataPtr[i] = byteList[i];
      }

      final writeResult = WritePrinter(
        hPrinter.value,
        dataPtr.cast(),
        bytes.length,
        bytesWrittenPtr,
      );

      if (writeResult == 0 || bytesWrittenPtr.value != bytes.length) {
        final err = GetLastError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal menulis ke printer. Error: $err")),
        );
      } else {
        EndPagePrinter(hPrinter.value);
        EndDocPrinter(hPrinter.value);

        await Future.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      if (hPrinter.value != 0) {
        ClosePrinter(hPrinter.value);
      }

      calloc.free(hPrinter);
      calloc.free(jobInfo);
      calloc.free(utf16Doc);
      calloc.free(utf16PrinterName);
      if (dataPtr != null) calloc.free(dataPtr);
      if (bytesWrittenPtr != null) calloc.free(bytesWrittenPtr);

      await Wakelock.disable();
    }
  }

  void sendRawCutCommand() {
    final List<int> cutCommand = [0x1D, 0x56, 0x42, 0x00]; // Full cut command
    final Uint8List bytes = Uint8List.fromList(cutCommand);
    BlueThermalPrinter.instance.writeBytes(bytes);
  }

  void sendCutAndOpenDrawer() async {
    final List<int> commands = [
      // Cut command
      //0x1B, 0x70, 0x00, 0x40, 0x50
      0x1D, 0x56, 0x42, 0x00,
      // Open drawer
      0x1B, 0x70, 0x00, 0x19, 0xFA,
    ];

    final Uint8List bytes = Uint8List.fromList(commands);
    await BlueThermalPrinter.instance.writeBytes(bytes);
  }

  Future<void> _fetchTransactionData({DateTime? selectedDate}) async {
    final token = await getToken();

    try {
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();
      final sessionId = await getSession();
      final userPos = await getUser();

      if (branch == null || branch.isEmpty) {
        throw Exception('Branch not found in local storage');
      }
      if (domain == null || domain.isEmpty) {
        throw Exception('Domain not found in local storage');
      }

      final uri = Uri.parse('$domain/api/transaction');

      // Jika selectedDate tidak null, kirim dalam format yyyy-MM-dd
      final body = {
        'sub_branch': branch,
        'session_id': sessionId,
        'userPos': userPos,
        if (selectedDate != null)
          'date': DateFormat('yyyy-MM-dd').format(selectedDate),
      };

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          transactions = data['data'] ?? [];
        });
      } else if (response.statusCode == 404) {
        // Tangani "No transactions found" → tampilkan kosong
        setState(() {
          transactions = [];
        });
      } else {
        print("Failed to load transactions: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching transaction: $e");
    }
  }

  Color getPaymentColor(String paymentType) {
    switch (paymentType) {
      case 'CASH':
        return Colors.green;
      case 'DEBIT':
        return Colors.blue;
      case 'QRIS':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> handleCancelTransaction({
    required BuildContext context,
    required String password,
    required String note,
    required String noStruk,
    required VoidCallback onSuccess,
    required void Function(String message) onError,
  }) async {
    List<String> allowedPasswords = [
      'tac453',
      'teuan453',
    ];

    if (!allowedPasswords.contains(password)) {
      onError('Password salah!');
      return;
    }

    if (note.trim().isEmpty) {
      onError('Keterangan harus diisi!');
      return;
    }
    final token = await getToken();

    try {
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();

      if (branch == null || branch.isEmpty) {
        throw Exception('Branch not found in local storage');
      }
      if (domain == null || domain.isEmpty) {
        throw Exception('Domain not found in local storage');
      }

      final uri = Uri.parse('$domain/api/transaction-cancel');

      // Jika selectedDate tidak null, kirim dalam format yyyy-MM-dd
      final body = {
        'note': note,
        'id_pos': noStruk,
      };

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        Navigator.pop(context);
        onSuccess();
      } else {
        onError('Gagal cancel transaksi!');
      }
      Navigator.pop(context); // Tutup dialog
    } catch (e) {
      onError('Error: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction History')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // 👉 Baris filter tanggal
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tanggal: ${DateFormat('yyyy-MM-dd').format(selectedDate)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null && picked != selectedDate) {
                      setState(() {
                        selectedDate = picked;
                      });
                      _fetchTransactionData(selectedDate: picked);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white, // Warna teks
                    backgroundColor: Colors.blue, // Warna background tombol
                  ),
                  child: const Text('Pilih Tanggal'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 👉 List transaksi
            Expanded(
              child: transactions.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        var transaction = transactions[index];
                        DateTime transactionDate =
                            DateTime.parse(transaction['transaction_date']);
                        String formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss')
                            .format(transactionDate);

                        IconData paymentIcon;
                        switch (transaction['payment_type']) {
                          case 'CASH':
                            paymentIcon = Icons.attach_money;
                            break;
                          case 'DEBIT':
                            paymentIcon = Icons.credit_card;
                            break;
                          case 'QRIS':
                            paymentIcon = Icons.qr_code;
                            break;
                          default:
                            paymentIcon = Icons.payment;
                        }

                        bool isToday =
                            DateFormat('yyyy-MM-dd').format(transactionDate) ==
                                DateFormat('yyyy-MM-dd').format(DateTime.now());

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TransactionDetailPage(
                                  noStruk: transaction['id_pos'],
                                ),
                              ),
                            );
                          },
                          child: Card(
                            color: getPaymentColor(transaction['payment_type']),
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(paymentIcon,
                                              color: Colors.white, size: 24),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Struk No: ${transaction['no_struk']}',
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                        ],
                                      ),
                                      Flexible(
                                        child: Text(
                                          formattedDate,
                                          style: const TextStyle(
                                              color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Payment Type: ${transaction['payment_type']}',
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                          const SizedBox(height: 4),
                                          if (isToday)
                                            ElevatedButton(
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (context) {
                                                    String password = '';
                                                    String note = '';
                                                    String error = '';
                                                    return StatefulBuilder(
                                                      builder:
                                                          (context, setState) {
                                                        return AlertDialog(
                                                          title: const Text(
                                                              'Otorisasi Cancel'),
                                                          content:
                                                              SingleChildScrollView(
                                                            child: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                TextField(
                                                                  obscureText:
                                                                      true,
                                                                  decoration:
                                                                      const InputDecoration(
                                                                    labelText:
                                                                        'Password',
                                                                    isDense:
                                                                        true,
                                                                  ),
                                                                  onChanged: (value) =>
                                                                      password =
                                                                          value,
                                                                ),
                                                                const SizedBox(
                                                                    height: 10),
                                                                TextField(
                                                                  decoration:
                                                                      const InputDecoration(
                                                                    labelText:
                                                                        'Keterangan',
                                                                    isDense:
                                                                        true,
                                                                  ),
                                                                  onChanged:
                                                                      (value) =>
                                                                          note =
                                                                              value,
                                                                ),
                                                                if (error
                                                                    .isNotEmpty)
                                                                  Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        top: 8),
                                                                    child: Text(
                                                                        error,
                                                                        style: const TextStyle(
                                                                            color:
                                                                                Colors.red)),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              child: const Text(
                                                                  'Batal'),
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      context),
                                                            ),
                                                            ElevatedButton(
                                                              style:
                                                                  ElevatedButton
                                                                      .styleFrom(
                                                                backgroundColor:
                                                                    Colors
                                                                        .amber,
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                              child: const Text(
                                                                  'Verifikasi Cancel'),
                                                              onPressed:
                                                                  () async {
                                                                List<String>
                                                                    allowedPasswords =
                                                                    [
                                                                  'tac453',
                                                                  'teuan453',
                                                                ];

                                                                String pass =
                                                                    password
                                                                        .trim(); // bersihkan spasi

                                                                if (!allowedPasswords
                                                                    .contains(
                                                                        pass)) {
                                                                  setState(() =>
                                                                      error =
                                                                          'Password salah!');
                                                                  return;
                                                                }

                                                                if (note
                                                                    .trim()
                                                                    .isEmpty) {
                                                                  setState(() =>
                                                                      error =
                                                                          'Keterangan harus diisi!');
                                                                  return;
                                                                }

                                                                // Panggil fungsi cancel transaksi
                                                                await handleCancelTransaction(
                                                                  context:
                                                                      context,
                                                                  password:
                                                                      password,
                                                                  note: note,
                                                                  noStruk: transaction[
                                                                          'id_pos']
                                                                      .toString(),
                                                                  onSuccess:
                                                                      () {
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                        content:
                                                                            Text('Transaksi berhasil di-cancel: ${transaction['id_pos']}'),
                                                                        backgroundColor:
                                                                            Colors.green,
                                                                      ),
                                                                    );
                                                                  },
                                                                  onError:
                                                                      (message) {
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                        content:
                                                                            Text(message),
                                                                        backgroundColor:
                                                                            Colors.red,
                                                                      ),
                                                                    );
                                                                  },
                                                                );
                                                              },
                                                            ),
                                                          ],
                                                        );
                                                      },
                                                    );
                                                  },
                                                );
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.amber,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 8),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              child: const Text(
                                                "Cancel",
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            formatRupiah(
                                                transaction['grand_total']
                                                    .toDouble()),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (isToday)
                                            ElevatedButton(
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder:
                                                      (BuildContext context) {
                                                    return AlertDialog(
                                                      title: const Text(
                                                          'Pilih Jenis Cetak'),
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          ListTile(
                                                            leading: const Icon(
                                                                Icons.receipt),
                                                            title: const Text(
                                                                'Reprint Receipt'),
                                                            onTap: () {
                                                              Navigator.of(
                                                                      context)
                                                                  .pop();

                                                              final idPos =
                                                                  transaction[
                                                                      'id_pos'];

                                                              commandReprint(
                                                                  idPos); // panggil fungsi dengan parameter idPos
                                                            },
                                                          ),
                                                          ListTile(
                                                            leading: const Icon(
                                                                Icons
                                                                    .assignment_ind),
                                                            title: const Text(
                                                                'Reprint Label'),
                                                            onTap: () {
                                                              Navigator.of(
                                                                      context)
                                                                  .pop();

                                                              final idPos =
                                                                  transaction[
                                                                      'id_pos'];
                                                              print(
                                                                  "Label CO: $idPos");
                                                              commandCO(idPos);
                                                            },
                                                          ),
                                                          ListTile(
                                                            leading: const Icon(
                                                                Icons
                                                                    .assignment_ind),
                                                            title: const Text(
                                                                'Reprint CO'),
                                                            onTap: () {
                                                              Navigator.of(
                                                                      context)
                                                                  .pop();

                                                              final idPos =
                                                                  transaction[
                                                                      'id_pos'];
                                                              print(
                                                                  "Printing CO: $idPos");
                                                              commandCO(idPos);
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor:
                                                    getPaymentColor(transaction[
                                                        'payment_type']),
                                                shape: const CircleBorder(),
                                                padding:
                                                    const EdgeInsets.all(12),
                                              ),
                                              child: const Icon(Icons.print),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
