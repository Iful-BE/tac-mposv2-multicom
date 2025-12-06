import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:mposv2/screens/home_screen.dart';
//import 'package:mposv2/screens/home_screen.dart';
import 'package:mposv2/screens/login_screen.dart';
import 'package:mposv2/screens/member_point.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
//import '../models/cart_item.dart';
import 'package:intl/intl.dart'; // Add this package for number formatting
import 'package:flutter/services.dart' show rootBundle;
import 'package:wakelock/wakelock.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import 'package:image/image.dart' as img;

class PaymentScreen extends StatefulWidget {
  final String sessionId;
  final String subBranch;
  final int typePayment;
  final double subtotal;
  final double grandtotal;
  final double discount;
  final double tax;
  final double svc;
  final double rounding;
  final double total;
  final String voucherCode;
  final bool isSelfService;
  final String? antrianId;

  const PaymentScreen(
      {super.key,
      required this.sessionId,
      required this.subBranch,
      required this.typePayment,
      required this.subtotal,
      required this.grandtotal,
      required this.discount,
      required this.tax,
      required this.svc,
      required this.rounding,
      required this.total,
      required this.voucherCode,
      this.isSelfService = false,
      this.antrianId});

  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  bool sendWa = false;
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  final TextEditingController cashController = TextEditingController();
  final TextEditingController cardNumberController = TextEditingController();
  final TextEditingController refNumberController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController waNumberController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController namaController = TextEditingController();
  late double totalAmount;
  double change = 0;
  String? selectedEDC;
  String? selectedCompliment;
  List<String> locationList = [];
  List<String> edcList = [];
  List<String> get kasirList =>
      edcList.where((e) => e.toLowerCase().startsWith("kasir")).toList();
  List<String> get bankList =>
      edcList.where((e) => !e.toLowerCase().startsWith("kasir")).toList();
  List<String> complimentList = [];
  String? selectedLocation;

  String selectedPaymentMethod = "Debit";
  String? base64QrImage;
  bool isLoadingQr = false;
  Uint8List? imageBytes;
  List<Map<String, dynamic>> payments = [];
  double sumPayments = 0;
  bool isDownPayment = false;
  TextEditingController splitAmountController = TextEditingController();
  String splitType = "Non-Cash"; // default
  bool hasCashPayment = false;
  bool hasNonCashPayment = false;
  double get paid => payments.fold(0.0, (p, c) => p + (c["amount"] ?? 0.0));
  double get remaining => totalAmount - paid;

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    _loadCustomerData();
    totalAmount = widget.grandtotal;

    if (widget.typePayment == 3) {
      fetchQrCode();
    } else if (widget.typePayment == 300) {
      _fetchCompliment();
    } else if (widget.typePayment == 2 || widget.typePayment == 4) {
      //_fetchLocations();
      _fetchEdc();
    }
    _loadSavedPrinter();
  }

  String _getPaymentType(int typePayment) {
    switch (typePayment) {
      case 1:
        return "1";
      case 2:
        return "2";
      case 3:
        return "3";
      default:
        return "Unknown";
    }
  }

  Future<void> _loadCustomerData() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');
    final name = prefs.getString('customer_name');

    if (phone != null) waNumberController.text = phone;
    if (name != null) namaController.text = name;
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
            //_showMessage("Printer sudah terhubung.");
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> fetchQrCode() async {
    setState(() {
      isLoadingQr = true;
      base64QrImage = null;
    });
    try {
      final token = await getToken();
      final domain = await getDomainFromLocalStorage();

      final url = Uri.parse('$domain/api/test-qr-bca');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        //final qrImage = jsonResponse['original']?['data']?['qrImage'];
        final qrImage = jsonResponse['original']?['data'];

        if (qrImage != null && qrImage is String && qrImage.isNotEmpty) {
          // Hapus whitespace lalu normalize
          String cleaned = qrImage.replaceAll(RegExp(r'\s+'), '');
          String normalized = base64.normalize(cleaned);

          try {
            // Coba decode
            //Uint8List decodedBytes = base64Decode(normalized);
            setState(() {
              base64QrImage = normalized;
              isLoadingQr = false;
            });
          } catch (e) {
            print('Error decode base64: $e');
            throw Exception('Gagal decode QR Image: ${e.toString()}');
          }
        } else {
          throw Exception('QR Image kosong di server');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to fetch QR code');
      }
    } catch (e) {
      print('Error fetching QR Code: $e');
      setState(() {
        isLoadingQr = false;
      });
    }
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

  Future<String?> getCashier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cashier');
  }

  Future<String?> TotalGuest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('total_guest');
  }

  Future<String?> getorderType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('orderType');
  }

  Future<String> _getDeviceId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id') ?? 'No Device available';
  }

  Future<String?> getPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_phone');
  }

  Future<String?> customerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('customer_name');
  }

  Future<bool?> afterTrx() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('after_transaction');
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

  // Convert logo ke ESC/POS bytes
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

  //Size
  //0:normal
  //1:normal-bold
  //2:medium-bold
  //3:large-boldplat
  //Align
  //0:left
  //1:center
  //2:right
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
        // Data pembayaran dari backend
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
        printer.printNewLine();
        printer.printCustom("Kasir   : ${header['kasir_name']}", 1, 0);
        printer.printCustom("Tanggal : $formattedDateTime", 1, 0);
        printer.printCustom(
            "Id      : $idsession", 1, 0); // ID tanpa 4 angka terakhir
        printer.printCustom(
            "Struk   : $lastFourDigits", 1, 0); // 4 angka terakhir
        printer.printCustom("Type    : ${header['order_type']}", 1, 0);
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
        String bank = (header['bank'] ?? "-").toString();
        String noCard = (header['card'] ?? "-").toString();
        String refNo = (header['ref_no'] ?? "-").toString();
        String type = (header['type'] ?? "-").toString();
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
        // Cek apakah ada metode pembayaran selain CASH
        if (header['type'].isEmpty) {
          printer.printCustom("Payment   : CASH", 1, 0);
        } else if (header['type'] == "Debit") {
          printer.printCustom("Payment   : Non CASH", 1, 0);
          printer.printCustom("Tipe      : $type", 1, 0);
          printer.printCustom("Bank      : $bank", 1, 0);
          printer.printCustom("Card      : $noCard", 1, 0);
          printer.printCustom("Ref No    : $refNo", 1, 0);
        } else {
          printer.printCustom("Payment   : Non CASH", 1, 0);
          printer.printCustom("Tipe      : $type", 1, 0);
          printer.printCustom("Bank      : $bank", 1, 0);
          printer.printCustom("Ref No    : $refNo", 1, 0);
        }

        printer.printCustom("Paid      : ${formatRupiah(paid)}", 1, 0);
        printer.printCustom("Change    : ${formatRupiah(kembali)}", 1, 0);
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
        // Data pembayaran dari backend
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
        printer.printNewLine();
        printer.printCustom("Kasir    : ${header['kasir_name']}", 1, 0);
        printer.printCustom("Tanggal : $formattedDateTime", 1, 0);
        printer.printCustom(
            "Id      : $idsession", 1, 0); // ID tanpa 4 angka terakhir
        printer.printCustom(
            "Struk   : $lastFourDigits", 1, 0); // 4 angka terakhir
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
        double rounding = double.parse(header['rounding'].toString());

        // printer.printCustom("Pajak    : ${formatRupiah(tax)}", 1, 0);
        printer.printCustom("Total      : ${formatRupiah(grandTotal)}", 1, 0);
        printer.printCustom("Rounded   : ${formatRupiah(rounding)}", 1, 0);
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

  void sendRawCutCommand() async {
    final List<int> commands = [
      // Open drawer
      0x1B, 0x70, 0x00, 0x19, 0xFA,
      // Cut command
      0x1D, 0x56, 0x42, 0x00,
    ];

    final Uint8List bytes = Uint8List.fromList(commands);
    await BlueThermalPrinter.instance.writeBytes(bytes);
  }

  void addCashAmount(int amount) {
    double currentCash = double.tryParse(cashController.text) ?? 0;
    double newCash = currentCash + amount;
    cashController.text = newCash.toInt().toString();
    calculateChange(cashController.text);
  }

  void calculateChange(String value) {
    double cashPaid = double.tryParse(value) ?? 0;
    setState(() {
      change = cashPaid - totalAmount;
    });
  }

  void setExactCash() {
    // Mengonversi totalAmount menjadi integer untuk menghilangkan desimal
    cashController.text = totalAmount.toInt().toString();
    calculateChange(cashController.text);
  }

  void validateAndPay() {
    if (widget.typePayment == 1) {
      // Validasi pembayaran cash
      double paid =
          (double.tryParse(cashController.text) ?? 0).truncateToDouble();
      if (paid < totalAmount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("Jumlah pembayaran kurang dari total yang harus dibayar"),
          ),
        );
        return;
      }
    } else if (widget.typePayment == 2 && selectedPaymentMethod == "OTHER") {
      if (selectedEDC == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pilih Kasir")),
        );
        return;
      }

      // Validasi compliment
    } else if (widget.typePayment == 2 && selectedPaymentMethod != "OTHER") {
      if (selectedEDC == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pilih Pembayaran")),
        );
        return;
      }
    } else if (widget.typePayment == 4) {
      if (selectedEDC == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pilih Pembayaran")),
        );
        return;
      }
    } else if (widget.typePayment == 300) {
      if (selectedCompliment == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pilih Compliment")),
        );
        return;
      }
    } else if (widget.typePayment == 4 && remaining > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Masih ada sisa pembayaran",
          ),
        ),
      );
      return;
    }

    // Jika valid, lanjutkan pembayaran dan cetak nota
    _payAndPrintBill();
  }

  void _payAndPrintBill() async {
    final prefs = await SharedPreferences.getInstance();
    final after = prefs.getBool('after_transaction') ?? false;
    final phone = prefs.getString('user_phone');

    // ✅ Tampilkan loading (kunci UI full stack)
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await checkOut();
      final hasPhone = phone != null && phone.isNotEmpty && phone != '0';
      if (hasPhone) {
        await showMemberPointDialog(context, after);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Pembayaran berhasil, mencetak invoice...")),
      );
      await Future.delayed(Duration(seconds: hasPhone ? 10 : 1));
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (_) => after ? const HomeScreen() : const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Terjadi kesalahan: $e")),
      );
    }
  }

  Future<void> checkOut() async {
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
      bool printLabelProd = prefs.getBool('print_label_prod') ?? true;
      int printCaptainQty = prefs.getInt('print_captain_qty') ?? 1;

      final token = await getToken();
      final domain = await getDomainFromLocalStorage();
      final deviceId = await _getDeviceId();
      final sessionId = await getSession();
      final subBranch = await getBranchFromLocalStorage();
      final cashier = await getCashier();
      final cashierId = await getUser();
      final guest = await TotalGuest();
      final orderType = await getorderType();
      final antrianId = widget.antrianId ?? '';

      if (domain == null) {
        print('Domain or Sub-Branch not found');
        return;
      }

      final url = Uri.parse('$domain/api/payment');
      final paidAmount = cashController.text;
      const type = '';
      //const voucherCode = '';
      Map<String, dynamic> body = {};

      if (widget.typePayment == 1) {
        body = {
          'user': deviceId,
          'cashier': cashier ?? '',
          'cashier_id': cashierId ?? '',
          'session_id': sessionId ?? '',
          'sub_branch': subBranch ?? '',
          'payment': '1',
          'sub_total': widget.subtotal,
          'discount': widget.discount,
          'total': widget.total,
          'tax': widget.tax,
          'svc': widget.svc,
          'rounding': widget.rounding,
          'grand_total': widget.grandtotal,
          'paid': paidAmount,
          'type': type,
          'nowa': waNumberController.text,
          'lokasi': selectedLocation,
          'totalGuest': guest,
          'orderType': orderType,
          'customer': namaController.text,
          'description': descriptionController.text,
          'voucher_code': widget.voucherCode,
          'antrian': antrianId,
          'send_wa': sendWa ? true : false,
        };
      } else if (widget.typePayment == 2) {
        if (selectedPaymentMethod != "QRIS") {
          body = {
            'session_id': sessionId ?? '',
            'sub_branch': subBranch ?? '',
            "payment": "2",
            "sub_total": widget.subtotal,
            "discount": widget.discount,
            "total": widget.total,
            "tax": widget.tax,
            'svc': widget.svc,
            'rounding': widget.rounding,
            "grand_total": widget.grandtotal,
            "paid": widget.grandtotal,
            "user": deviceId,
            'cashier': cashier ?? '',
            'cashier_id': cashierId ?? '',
            "card": cardNumberController
                .text, // Ensure you extract text from the controller
            "bank": selectedEDC,
            "ref_no": refNumberController
                .text, // Ensure you extract text from the controller
            "type": selectedEDC,
            'nowa': waNumberController.text,
            'lokasi': selectedLocation,
            'totalGuest': guest,
            'orderType': orderType,
            'customer': namaController.text,
            'description': descriptionController.text,
            'voucher_code': widget.voucherCode,
            'antrian': antrianId,
            'send_wa': sendWa ? true : false,
          };
        } else if (selectedPaymentMethod == "QRIS") {
          body = {
            'session_id': sessionId ?? '',
            'sub_branch': subBranch ?? '',
            "payment": "2",
            "sub_total": widget.subtotal,
            "discount": widget.discount,
            "total": widget.total,
            "tax": widget.tax,
            'svc': widget.svc,
            'rounding': widget.rounding,
            "grand_total": widget.grandtotal,
            "paid": widget.grandtotal,
            "user": deviceId,
            'cashier': cashier ?? '',
            'cashier_id': cashierId ?? '',
            "card": '', // Empty for QRIS
            "bank": selectedEDC,
            "ref_no": refNumberController
                .text, // Ensure you extract text from the controller
            "type": selectedEDC,
            'nowa': waNumberController.text,
            'lokasi': selectedLocation,
            'totalGuest': guest,
            'orderType': orderType,
            'customer': namaController.text,
            'description': descriptionController.text,
            'voucher_code': widget.voucherCode,
            'antrian': antrianId,
            'send_wa': sendWa ? true : false,
          };
        }
      } else if (widget.typePayment == 4) {
        List<Map<String, dynamic>> splitData = payments.map((p) {
          return {
            "method": p["method"],
            "amount": p["amount"],
            "is_dp": p["is_dp"] == true ? 1 : 0,
            "description": descriptionController.text,
          };
        }).toList();
        body = {
          'session_id': sessionId ?? '',
          'sub_branch': subBranch ?? '',
          "payment": "2",
          "sub_total": widget.subtotal,
          "discount": widget.discount,
          "total": widget.total,
          "tax": widget.tax,
          'svc': widget.svc,
          'rounding': widget.rounding,
          "grand_total": widget.grandtotal,
          "paid": widget.grandtotal,
          "user": deviceId,
          'cashier': cashier ?? '',
          'cashier_id': cashierId ?? '',
          "card": cardNumberController
              .text, // Ensure you extract text from the controller
          "bank": selectedEDC,
          "ref_no": refNumberController
              .text, // Ensure you extract text from the controller
          "type": selectedEDC,
          'nowa': waNumberController.text,
          'lokasi': selectedLocation,
          'totalGuest': guest,
          'orderType': orderType,
          'customer': namaController.text,
          'description': descriptionController.text,
          'voucher_code': widget.voucherCode,
          'antrian': antrianId,
          'send_wa': sendWa ? true : false,
          "split_payments": splitData,
        };
      } else if (widget.typePayment == 3) {
        body = {
          'session_id': sessionId ?? '',
          'sub_branch': subBranch ?? '',
          'payment': '3',
          'sub_total': widget.subtotal,
          'discount': widget.discount,
          'total': widget.total,
          'tax': widget.tax,
          'svc': widget.svc,
          'rounding': widget.rounding,
          'grand_total': widget.grandtotal,
          'paid': widget.grandtotal, // Misalnya QRIS harus dibayar penuh
          'user': deviceId,
          'cashier': cashier ?? '',
          'cashier_id': cashierId ?? '',
          'payment_method': 'midtrans_qris', // Bisa disesuaikan
          //'midtrans_order_id': midtransOrderId, // Dapatkan dari API Midtrans
          'nowa': waNumberController.text,
          'lokasi': selectedLocation,
          'totalGuest': guest,
          'orderType': orderType,
          'customer': namaController.text,
          'description': descriptionController.text,
          'voucher_code': widget.voucherCode,
          'antrian': antrianId,
          'send_wa': sendWa ? true : false,
        };
      } else if (widget.typePayment == 300) {
        body = {
          'session_id': sessionId ?? '',
          'sub_branch': subBranch ?? '',
          'payment': '300',
          'sub_total': widget.subtotal,
          'discount': widget.discount,
          'total': widget.total,
          'tax': widget.tax,
          'svc': widget.svc,
          'rounding': widget.rounding,
          'grand_total': widget.grandtotal,
          'paid': widget.grandtotal,
          'user': deviceId,
          'cashier': cashier ?? '',
          'cashier_id': cashierId ?? '',
          'selectCompliment': selectedCompliment ?? '',
          'nowa': waNumberController.text,
          'lokasi': selectedLocation,
          'totalGuest': guest,
          'orderType': orderType,
          'customer': namaController.text,
          'description': descriptionController.text,
          'voucher_code': widget.voucherCode,
          'antrian': antrianId,
          'send_wa': sendWa ? true : false,
        };
      }

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

        // Ambil jumlah print customer dari SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        int printCustQty = prefs.getInt('print_cust_qty') ?? 1;

        // === CETAK CUSTOMER ===
        if (printCustomer) {
          for (int i = 0; i < printCustQty; i++) {
            if (widget.typePayment == 300) {
              await _printCompliment(data);
            } else if (Platform.isWindows) {
              await _printReceiptWindows(data);
            } else {
              await _printReceipt(data);
            }
          }
        }

        // === CETAK LABEL PRODUK (opsi terpisah) ===
        if (printLabelProd) {
          await printLabelXP4601B(data);
        }

        // === CETAK CAPTAIN ===
        // for (int i = 0; i < printCaptainQty; i++) {
        //   await _printCaptainOrder(data);
        // }
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

  Future<void> printLabelXP4601B(
    Map<String, dynamic> data, {
    int port = 9100,
  }) async {
    Socket? socket;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ipAddress = prefs.getString('ip_label');
      if (ipAddress == null || ipAddress.isEmpty) {
        return;
      }
      // --- Ambil settingan printer dari prefs ---
      final width = prefs.getString('labelWidth') ?? '35';
      final height = prefs.getString('labelHeight') ?? '15';
      final topMargin = prefs.getInt('labelTopMargin') ?? 40;
      final lineSpacing = prefs.getInt('label_line_spacing') ?? 30;
      final maxCharsPerLine = prefs.getInt('labelMaxChars') ?? 22;
      final fontType = prefs.getString('label_font_type') ?? "1";
      // --- Ambil data header ---
      final header = data['data']['postHeader'];
      final details = data['data']['postDetails'] as List<dynamic>? ?? [];
      if (details.isEmpty) return;
      String idPostHeader = header['id_post_header'].toString();
      String customerName = prefs.getString('customer_name') ?? '-';
      String userPhone = prefs.getString('user_phone') ?? '-';
      if (userPhone.startsWith('0')) {
        userPhone = userPhone.replaceFirst('0', '+62');
      } else if (!userPhone.startsWith('+62')) {
        userPhone = '+62$userPhone';
      }

      socket = await Socket.connect(ipAddress, port,
          timeout: const Duration(seconds: 5));
      // Inisialisasi printer
      final initBuffer = StringBuffer()
        ..writeln("SIZE $width mm,$height mm")
        ..writeln("GAP 2 mm,0")
        ..writeln("DIRECTION 1");
      socket.add(latin1.encode(initBuffer.toString()));
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 200));

      for (final item in details) {
        final name = item['name'].toString();
        final qty = int.tryParse(item['quantity'].toString()) ?? 1;

        for (int i = 0; i < qty; i++) {
          final wrappedLines =
              wrapTextFlexible(name.toUpperCase(), maxCharsPerLine);

          final labelBuffer = StringBuffer();
          labelBuffer.writeln("CLS");

          double y = topMargin.toDouble();

          // --- Cetak Header ---
          labelBuffer.writeln(
              'TEXT 0,${y.toInt()},"$fontType",0,1,1,"ID: $idPostHeader"');
          y += lineSpacing;
          labelBuffer.writeln(
              'TEXT 0,${y.toInt()},"$fontType",0,1,1,"Cust: $customerName"');
          y += lineSpacing;
          labelBuffer.writeln(
              'TEXT 0,${y.toInt()},"$fontType",0,1,1,"Phone: $userPhone"');
          y += lineSpacing;

          // --- Cetak Item ---
          for (final line in wrappedLines) {
            labelBuffer
                .writeln('TEXT 0,${y.toInt()},"$fontType",0,1,1,"$line"');
            y += lineSpacing;
          }

          labelBuffer.writeln("PRINT 1");

          socket.add(latin1.encode(labelBuffer.toString()));
          await socket.flush();

          await Future.delayed(
              Duration(milliseconds: 500 + wrappedLines.length * 30));
        }
      }

      // print(
      //     "✅ Berhasil cetak ${details.fold<int>(0, (prev, e) => prev + (int.tryParse(e['quantity'].toString()) ?? 1))} label unit ke $ipAddress");
    } catch (e) {
      print("❌ Gagal cetak ke printer: $e");
    } finally {
      await socket?.close();
    }
  }

  /// Wrap text fleksibel
  List<String> wrapTextFlexible(String text, int maxChars) {
    if (text.length <= maxChars) return [text];

    final result = <String>[];
    final buffer = StringBuffer();

    for (final word in text.split(' ')) {
      if (buffer.isEmpty) {
        buffer.write(word);
      } else if (buffer.length + word.length + 1 <= maxChars) {
        buffer.write(' $word');
      } else {
        result.add(buffer.toString());
        buffer.clear();
        buffer.write(word);
      }
    }

    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }

  Future<void> _fetchLocations() async {
    final branch = await getBranchFromLocalStorage();
    final domain = await getDomainFromLocalStorage();

    final token = await getToken();

    if (domain == null || branch == null) {
      print('Missing required parameters for API request.');
      return;
    }
    final body = jsonEncode({
      'sub_branch': branch,
    });

    final url = Uri.parse("$domain/api/master-location");

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final parsed = json.decode(response.body);
        final List data = parsed is List ? parsed : parsed['data'];
        setState(() {
          locationList = data.map((item) => item['name'].toString()).toList();
        });
      } else {
        print("Failed to fetch location: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching location: $e");
    }
  }

  Future<void> _fetchEdc() async {
    final branch = await getBranchFromLocalStorage();
    final domain = await getDomainFromLocalStorage();

    final token = await getToken();

    if (domain == null || branch == null) {
      print('Missing required parameters for API request.');
      return;
    }
    final body = jsonEncode({
      'sub_branch': branch,
    });

    final url = Uri.parse("$domain/api/master-edc");

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final parsed = json.decode(response.body);
        final List data = parsed is List ? parsed : parsed['data'];
        setState(() {
          edcList = data.map((item) => item['bank_name'].toString()).toList();
        });
      } else {
        print("Failed to fetch edc: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching edc: $e");
    }
  }

  Future<void> _fetchCompliment() async {
    final branch = await getBranchFromLocalStorage();
    final domain = await getDomainFromLocalStorage();

    final token = await getToken();

    if (domain == null || branch == null) {
      print('Missing required parameters for API request.');
      return;
    }
    final body = jsonEncode({
      'sub_branch': branch,
    });

    final url = Uri.parse("$domain/api/index-compliments");

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final parsed = json.decode(response.body);
        final List data = parsed is List ? parsed : parsed['data'];
        setState(() {
          complimentList = data.map((item) => item['code'].toString()).toList();
        });
      } else {
        print("Failed to fetch compliment: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching compliment: $e");
    }
  }

  Widget _buildReadonlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdditionalDescription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text("Keterangan Tambahan",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            SizedBox(width: 6),
            Text("(opsional)",
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: descriptionController,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            hintText: "Masukkan keterangan jika ada",
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final NumberFormat currencyFormatter =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    double paid = payments.fold(0.0, (p, c) => p + (c['amount'] ?? 0));
    double remaining = totalAmount - paid;
    return Scaffold(
      resizeToAvoidBottomInset: true, // Mencegah bottom overflow
      appBar: AppBar(
        title: const Text('Pembayaran'),
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior
            .onDrag, // Tutup keyboard saat scroll
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.typePayment != 4) ...[
                Text(
                  "Total: ${currencyFormatter.format(totalAmount)}",
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
              ],

              //SPLIT PAYMENT
              if (widget.typePayment == 4) ...[
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(
                      16), // Increased padding for better spacing
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50, // Soft color without gradient
                    borderRadius: BorderRadius.circular(
                        16), // Slightly larger radius for softness
                    border: Border.all(
                        color: Colors.blue.shade100.withOpacity(0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      // =================================
                      // PILIH JENIS PEMBAYARAN
                      // =================================
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth <
                              800; // Threshold bisa diubah

                          Widget paymentOptions = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Pilihan Non-Cash / Cash
                              Row(
                                children: [
                                  Radio<String>(
                                    value: "Non-Cash",
                                    groupValue: splitType,
                                    activeColor: Colors.teal.shade400,
                                    onChanged: (val) {
                                      setState(() {
                                        splitType = val!;
                                        selectedEDC = null;
                                      });
                                    },
                                  ),
                                  Text(
                                    "Non-Cash",
                                    style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 14),
                                  ),
                                  const SizedBox(width: 16),
                                  Radio<String>(
                                    value: "Cash",
                                    groupValue: splitType,
                                    activeColor: Colors.teal.shade400,
                                    onChanged: (val) {
                                      setState(() {
                                        splitType = val!;
                                        selectedEDC = null;
                                      });
                                    },
                                  ),
                                  Text(
                                    "Cash",
                                    style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 14),
                                  ),
                                ],
                              ),

                              // Switch DP
                              Row(
                                children: [
                                  Switch(
                                    value: isDownPayment,
                                    onChanged: (val) {
                                      setState(() {
                                        isDownPayment = val;
                                      });
                                    },
                                    activeColor: Theme.of(context).primaryColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Down Payment (DP)",
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                        ),
                                        Text(
                                          "Aktifkan jika transaksi menggunakan DP",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );

                          Widget totalSplit = Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  "Total Split : ${currencyFormatter.format(paid)} / "
                                  "${currencyFormatter.format(totalAmount)}",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Sisa           : ${currencyFormatter.format(remaining)}",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (isMobile) {
                            // Mobile → total di atas
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                totalSplit,
                                const SizedBox(height: 12),
                                paymentOptions,
                              ],
                            );
                          } else {
                            // PC / desktop → total di kanan
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: paymentOptions),
                                const SizedBox(width: 20),
                                SizedBox(
                                  width: 550, // lebar kotak total split
                                  child: totalSplit,
                                ),
                              ],
                            );
                          }
                        },
                      ),

                      // =================================
                      // AUTO FILL SISA PEMBAYARAN
                      // =================================
                      if (payments.isNotEmpty) ...[
                        Text(
                          "Auto Fill Sisa Pembayaran",
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  double sum = payments.fold(
                                      0.0, (p, c) => p + (c['amount'] ?? 0));
                                  double remaining = totalAmount - sum;
                                  if (remaining <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              "Tidak ada sisa pembayaran")),
                                    );
                                    return;
                                  }

                                  payments.add({
                                    "method": "Cash",
                                    "amount": remaining,
                                    "is_dp": isDownPayment,
                                  });
                                  isDownPayment = false;

                                  hasCashPayment = true;
                                  setState(() {});
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade300,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  elevation: 2,
                                ),
                                child: const Text("Isi Sisanya dengan Cash",
                                    style: TextStyle(fontSize: 14)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  double sum = payments.fold(
                                      0.0, (p, c) => p + (c['amount'] ?? 0));
                                  double remaining = totalAmount - sum;
                                  if (remaining <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              "Tidak ada sisa pembayaran")),
                                    );
                                    return;
                                  }
                                  if (selectedEDC == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              "Pilih metode non-cash terlebih dahulu")),
                                    );
                                    return;
                                  }
                                  payments.add({
                                    "method": selectedEDC,
                                    "amount": remaining,
                                    "is_dp": isDownPayment,
                                  });
                                  isDownPayment = false;

                                  hasNonCashPayment = true;
                                  setState(() {});
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple.shade300,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  elevation: 2,
                                ),
                                child: const Text("Isi Sisanya dengan Non-Cash",
                                    style: TextStyle(fontSize: 14)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      const SizedBox(height: 12),

                      // =================================
                      // FORM INPUT NON-CASH (muncul duluan)
                      // =================================
                      if (splitType == "Non-Cash") ...[
                        TextField(
                          controller: splitAmountController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black87),
                          decoration: InputDecoration(
                            hintText: "Nominal Non-Cash",
                            hintStyle: TextStyle(color: Colors.grey.shade500),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.blue.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Colors.teal.shade400, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Pilih pembayaran",
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Hitung jumlah kolom responsif
                            int crossAxisCount = 2; // default mobile

                            if (constraints.maxWidth > 480) crossAxisCount = 3;
                            if (constraints.maxWidth > 768) crossAxisCount = 4;
                            if (constraints.maxWidth > 1024)
                              crossAxisCount =
                                  6; // Adjusted for better mobile fit

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: bankList.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio:
                                    4.0, // Adjusted for better proportion on mobile
                              ),
                              itemBuilder: (context, index) {
                                final bank = bankList[index];
                                final isSelected = selectedEDC == bank;

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      selectedEDC = bank;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeInOut,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.teal
                                              .shade100 // Soft selected color
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.teal.shade400
                                            : Colors.grey.shade300,
                                        width: isSelected ? 2 : 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    child: Text(
                                      bank,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: isSelected
                                            ? Colors.teal.shade800
                                            : Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],

                      // =================================
                      // FORM INPUT CASH (muncul PALING AKHIR)
                      // =================================
                      if (splitType == "Cash") ...[
                        TextField(
                          controller: splitAmountController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: "Nominal Cash",
                            labelStyle: TextStyle(color: Colors.grey.shade600),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.blue.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Colors.teal.shade400, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                splitAmountController.text =
                                    totalAmount.toString();
                                setState(() {});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors
                                    .pink.shade300, // Soft colorful button
                                foregroundColor: Colors.white, // White text
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                elevation: 2,
                              ),
                              child: const Text("Uang Pas",
                                  style: TextStyle(fontSize: 14)),
                            ),
                            ...[10000, 20000, 50000, 100000].map((amount) {
                              return ElevatedButton(
                                onPressed: () {
                                  double oldVal = double.tryParse(
                                          splitAmountController.text) ??
                                      0;
                                  splitAmountController.text =
                                      (oldVal + amount).toString();
                                  setState(() {});
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors
                                      .orange.shade300, // Varied soft colors
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  elevation: 2,
                                ),
                                child: Text(
                                  currencyFormatter.format(amount),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              );
                            }),
                          ],
                        ),
                      ],

                      const SizedBox(height: 12),

                      // =================================
                      // TOMBOL TAMBAH PAYMENT
                      // =================================
                      ElevatedButton.icon(
                        onPressed: () {
                          // VALIDASI: jika Non-Cash tetapi belum memilih EDC
                          if (splitType != "Cash" && selectedEDC == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Silahkan pilih pembayaran")),
                            );
                            return;
                          }

                          double value =
                              double.tryParse(splitAmountController.text) ?? 0;
                          if (value <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Nominal harus lebih dari 0")),
                            );
                            return;
                          }

                          double sum =
                              payments.fold(0, (p, c) => p + c["amount"]);

                          if (sum + value > totalAmount) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text("Total melebihi jumlah tagihan!")),
                            );
                            return;
                          }

                          payments.add({
                            "method":
                                splitType == "Cash" ? "Cash" : selectedEDC,
                            "amount": value,
                            "is_dp": isDownPayment, // DP ikut sesuai switch
                          });

                          isDownPayment = false;

                          if (splitType == "Cash") hasCashPayment = true;
                          if (splitType != "Cash") hasNonCashPayment = true;

                          splitAmountController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text("Tambah Pembayaran",
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade400, // Elegant teal
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          elevation: 3,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // =================================
                      // LIST PAYMENT
                      // =================================
                      ...payments.map((p) {
                        bool isDP = p['is_dp'] == true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            title: Row(
                              children: [
                                Text(
                                  "${p['method']} - ${currencyFormatter.format(p['amount'])}",
                                  style: TextStyle(
                                    color: Colors.grey.shade800,
                                    fontSize: 14,
                                  ),
                                ),

                                // ===== Tambahkan label DP jika flag aktif =====
                                if (isDP) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "DP",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ]
                              ],
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.delete,
                                  color: Colors.red.shade400),
                              onPressed: () {
                                if (p['method'] == "Cash")
                                  hasCashPayment = false;
                                if (p['method'] != "Cash")
                                  hasNonCashPayment = false;

                                payments.remove(p);
                                setState(() {});
                              },
                            ),
                          ),
                        );
                      }),

                      // =================================
                      // TOTAL
                      // =================================

                      const Row(
                        children: [
                          Text(
                            "Keterangan Tambahan",
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          SizedBox(width: 6),
                          Text(
                            "(opsional)",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: descriptionController,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: "Masukkan keterangan jika ada",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          isDense: true, // memperkecil tinggi field
                        ),
                      ),
                    ],
                  ),
                ),
              ]
              // CASH PAYMENT
              else if (widget.typePayment == 1) ...[
                TextField(
                  controller: cashController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Jumlah Bayar"),
                  onChanged: calculateChange,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: setExactCash,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8), // lebih kecil
                        textStyle:
                            const TextStyle(fontSize: 14), // kecilkan font
                        minimumSize:
                            const Size(80, 36), // batas minimum ukuran tombol
                      ),
                      child: const Text("Uang Pas"),
                    ),
                    ...[10000, 20000, 50000, 100000].map((amount) {
                      return ElevatedButton(
                        onPressed: () => addCashAmount(amount),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                          minimumSize: const Size(80, 36),
                        ),
                        child: Text(currencyFormatter.format(amount)),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          "Keterangan Tambahan",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          "(opsional)",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: descriptionController,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: "Masukkan keterangan jika ada",
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        isDense: true, // memperkecil tinggi field
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "Kembali: ${currencyFormatter.format(change)}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3748),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Struk via WhatsApp"),
                  value: sendWa,
                  onChanged: (value) {
                    setState(() {
                      sendWa = value;
                    });
                  },
                  activeColor: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 10),
                _buildReadonlyField(
                  "No. WhatsApp",
                  "+62 ${waNumberController.text}",
                ),
                const SizedBox(height: 10),
                _buildReadonlyField(
                  "Nama",
                  namaController.text.isNotEmpty
                      ? namaController.text.toUpperCase()
                      : "-",
                ),
              ]

              // NON-CASH PAYMENT
              else if (widget.typePayment == 2) ...[
                const SizedBox(height: 8),
                const Text("Pilih pembayaran", style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Hitung jumlah kolom responsif
                    int crossAxisCount = 2; // default mobile

                    if (constraints.maxWidth > 480) crossAxisCount = 3;
                    if (constraints.maxWidth > 768) crossAxisCount = 4;
                    if (constraints.maxWidth > 1024) crossAxisCount = 8;

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: bankList.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 3.6, // LEBIH KECIL DAN PANJANG
                      ),
                      itemBuilder: (context, index) {
                        final bank = bankList[index];
                        final isSelected = selectedEDC == bank;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedEDC = bank;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.fastEaseInToSlowEaseOut,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.shade50
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.grey.shade300,
                                width: isSelected ? 1.6 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    bank,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? Colors.blue.shade800
                                          : Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildAdditionalDescription(),
                const SizedBox(height: 10),
                _buildReadonlyField(
                    "No. WhatsApp", "+62 ${waNumberController.text}"),
                const SizedBox(height: 10),
                _buildReadonlyField(
                    "Nama",
                    namaController.text.isNotEmpty
                        ? namaController.text.toUpperCase()
                        : "-"),
              ]

              //compliment
              else if (widget.typePayment == 300) ...[
                const SizedBox(height: 8),
                const Text("Compliment", style: TextStyle(fontSize: 13)),
                DropdownButton<String>(
                  value: selectedCompliment,
                  hint: const Text("--Pilih--", style: TextStyle(fontSize: 13)),
                  isExpanded: true,
                  style: const TextStyle(fontSize: 13, color: Colors.black),
                  items: complimentList.map((String compliment) {
                    return DropdownMenuItem<String>(
                      value: compliment,
                      child: Text(compliment,
                          style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      selectedCompliment = newValue;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          "Keterangan Tambahan",
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        SizedBox(width: 6),
                        Text(
                          "(opsional)",
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descriptionController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: "Masukkan keterangan jika ada",
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildReadonlyField(
                    "No. WhatsApp", "+62 ${waNumberController.text}"),
                const SizedBox(height: 10),
                _buildReadonlyField(
                  "Nama",
                  namaController.text.isNotEmpty
                      ? namaController.text.toUpperCase()
                      : "-",
                ),
              ],

              const SizedBox(height: 20),

              // BUTTON PAY & PRINT BILL
              if (widget.typePayment == 1 ||
                  widget.typePayment == 2 ||
                  widget.typePayment == 4)
                Center(
                  child: ElevatedButton(
                    onPressed: validateAndPay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 24),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                    child: const Text("Simpan & Cetak",
                        style: TextStyle(color: Colors.white)),
                  ),
                ),

              if (widget.typePayment == 300)
                Center(
                  child: ElevatedButton(
                    onPressed: validateAndPay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 24),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                    child: const Text("Simpan & Cetak",
                        style: TextStyle(color: Colors.white)),
                  ),
                ),

              if (widget.typePayment == 3)
                Center(
                  child: isLoadingQr
                      ? const CircularProgressIndicator()
                      : base64QrImage != null
                          ? Image.memory(
                              base64Decode(base64QrImage!),
                              width: 250,
                              height: 250,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Text('Gagal decode gambar QR.');
                              },
                            )
                          : const Text("Gagal memuat QR Code."),
                ),
              const SizedBox(height: 40),
              if (widget.typePayment == 3)
                Center(
                  child: ElevatedButton(
                    onPressed: isLoadingQr ? null : fetchQrCode,
                    child: const Text('Generate QR'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
