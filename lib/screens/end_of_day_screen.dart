import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mposv2/screens/login_screen.dart';
import 'package:http/http.dart' as http;
import 'package:mposv2/screens/payment_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:wakelock/wakelock.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;

class EndOfDayScreen extends StatefulWidget {
  const EndOfDayScreen({super.key});

  @override
  State<EndOfDayScreen> createState() => _EndOfDayScreenState();
}

class _EndOfDayScreenState extends State<EndOfDayScreen> {
  bool isConnected = false;
  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  BluetoothDevice? selectedDevice;

  final bool _isLoading = false;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    _loadSavedPrinter();
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

//perintah cut paper
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

  Future<Map<String, String?>> _getLocalStorageData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'domain': prefs.getString('domain'),
      'branch': prefs.getString('sub_branch_name'),
      'session_id': prefs.getString('session_id'),
    };
  }

  //printer
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
          _showMessage("Terhubung ke ${selectedDevice!.name}");
        }
      } catch (e) {
        setState(() => isConnected = false);
        _showError("Gagal terhubung ke printer: $e");

        // Coba reconnect setelah 2 detik
        Future.delayed(const Duration(seconds: 2), () async {
          _showMessage("Mencoba menghubungkan ulang...");
          await _connectToPrinter();
        });
      }
    } else {
      _showError("Tidak ada printer yang dipilih.");
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleLogout() async {
    Future.delayed(const Duration(seconds: 0), () {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  Future<void> _updateEndDate() async {
    final token = await getToken();

    try {
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();
      final sessionId = await getSession();

      if (branch == null || branch.isEmpty) {
        throw Exception('Branch not found in local storage');
      }
      if (domain == null || domain.isEmpty) {
        throw Exception('Domain not found in local storage');
      }

      final uri = Uri.parse('$domain/api/close-session');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sub_branch': branch, 'session_id': sessionId}),
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          if (data != null && data is Map<String, dynamic>) {
            _printReceipt(data);

            //print(data);
          } else {
            _showError("Response data tidak valid.");
          }
        } catch (e) {
          _showError("Gagal memproses respons: $e");
        }
      } else {
        _showError("Gagal menutup sesi: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Error: $e");
    }
  }

  Future<void> _printReceipt(Map<String, dynamic> data) async {
    bool? isConnected = await printer.isConnected;
    if (isConnected != true) {
      _showError("Printer tidak terhubung. Mencoba menghubungkan ulang...");
      try {
        await _connectToPrinter();
        isConnected = await printer.isConnected;
      } catch (e) {
        _showError("Gagal menghubungkan ulang: $e");
        return;
      }
    }

    if (isConnected == true) {
      String formatRupiah(double amount) {
        final formatter = NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp.', decimalDigits: 0);
        return formatter.format(amount);
      }

      if (!data.containsKey('data') || data['data'] is! Map) {
        _showError("Data tidak valid untuk dicetak.");
        return;
      }

      Map<String, dynamic> receiptData = data['data'];
      String kasir = await getCashier() ?? 'Unknown';
      String sessionPos = receiptData['header']['session_pos'] ?? 'Unknown';
      final addr = receiptData['address'];
      DateTime dateTime = DateTime.parse(receiptData['date']!).toLocal();
      String formattedDateTime =
          DateFormat('dd-MM-yyyy HH:mm:ss').format(dateTime);

      List<dynamic> items = receiptData['detail'];
      double subTotal =
          double.tryParse(receiptData['subTotal'].toString()) ?? 0;
      double totalDiscount =
          double.tryParse(receiptData['totalDiscount'].toString()) ?? 0;
      double totalRounding =
          double.tryParse(receiptData['totalRounding'].toString()) ?? 0;
      double totalTax =
          double.tryParse(receiptData['totalTax'].toString()) ?? 0;
      double totalService =
          double.tryParse(receiptData['totalService'].toString()) ?? 0;
      double grandTotal =
          double.tryParse(receiptData['grand_total'].toString()) ?? 0;
      double totalPayment =
          double.tryParse(receiptData['total_payment'].toString()) ?? 0;

      double totalPointDisc =
          double.tryParse(receiptData['total_point_disc'].toString()) ?? 0;

      double totalPointUsed =
          double.tryParse(receiptData['total_point_used'].toString()) ?? 0;

      Map<String, dynamic> combinedTotals =
          Map<String, dynamic>.from(receiptData['combinedTotals'] ?? {});

      Map<String, double> normalTotals = {};
      Map<String, double> dpTotals = {};

      printer.printCustom("Close Session", 1, 1);
      printer.printCustom("${addr['bname']}", 1, 1);
      printer.printCustom("${addr['device_addr']}", 1, 1);
      printer.printCustom("${addr['descript']}", 1, 1);
      printer.printNewLine();

      printer.printCustom("Tanggal: $formattedDateTime", 1, 0);
      printer.printCustom("Kasir      : $kasir", 1, 0);
      printer.printCustom("Session POS: $sessionPos", 1, 0);
      printer.printNewLine();

      printer.printCustom("Item        Qty    Harga", 1, 0);
      for (var item in items) {
        String itemName = item['name'].toString().toUpperCase();
        String itemQty = item['total_quantity'].toString();
        double itemPriceValue = double.tryParse(item['price'].toString()) ?? 0;
        double itemTotalValue = double.tryParse(item['total'].toString()) ?? 0;

        printer.printCustom(itemName, 1, 0);
        printer.printCustom(
            "${formatRupiah(itemPriceValue)} x $itemQty = ${formatRupiah(itemTotalValue)}",
            1,
            0);
      }

      printer.printNewLine();

      combinedTotals.forEach((type, obj) {
        double amt = (obj is Map)
            ? double.tryParse(obj['amount'].toString()) ?? 0
            : double.tryParse(obj.toString()) ?? 0;

        if (type.contains("(-DP)")) {
          dpTotals[type] = amt;
        } else {
          normalTotals[type] = amt;
        }
      });

      printer.printCustom("Sub Total    : ${formatRupiah(subTotal)}", 1, 0);
      printer.printCustom(
          "Discount     : ${formatRupiah(totalDiscount)}", 1, 0);
      printer.printCustom("PB1          : ${formatRupiah(totalTax)}", 1, 0);
      printer.printCustom("S.Charge     : ${formatRupiah(totalService)}", 1, 0);
      printer.printCustom(
          "Rounded      : ${formatRupiah(totalRounding)}", 1, 0);
      printer.printNewLine();
      printer.printCustom("Grand Total  : ${formatRupiah(grandTotal)}", 1, 0);
      printer.printNewLine();

      normalTotals.forEach((type, amt) {
        printer.printCustom("$type : ${formatRupiah(amt)}", 1, 0);
      });

      printer.printNewLine();

      printer.printCustom(
          "Total Payment : ${formatRupiah(totalPayment)}", 1, 0);
      printer.printNewLine();

      dpTotals.forEach((type, amt) {
        printer.printCustom("$type : ${formatRupiah(amt)}", 1, 0);
      });

      printer.printNewLine();
      printer.printCustom("Points Used: $totalPointUsed", 1, 0);
      printer.printCustom("Points Disc: ${formatRupiah(totalPointDisc)}", 1, 0);
      printer.printNewLine();

      sendRawCutCommand();
    } else {
      _showError("Printer belum terhubung!");
    }
  }

  Future<void> _printReceiptWindows(Map<String, dynamic> data) async {
    if (!Platform.isWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Print hanya tersedia di Windows")),
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

    try {
      // buka printer
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

      // ambil data
      final receiptData = data['data'];
      String kasir = await getCashier() ?? 'Unknown';
      String sessionPos = receiptData['header']['session_pos'] ?? 'Unknown';
      String addr = receiptData['address'];

      DateTime dateTime = DateTime.parse(receiptData['date']!).toLocal();
      String formattedDateTime =
          DateFormat('dd-MM-yyyy HH:mm:ss').format(dateTime);

      List<dynamic> items = receiptData['detail'];
      double subTotal =
          double.tryParse(receiptData['subTotal']?.toString() ?? '0') ?? 0;
      double totalCash =
          double.tryParse(receiptData['totalCash']?.toString() ?? '0') ?? 0;
      double totalDebit =
          double.tryParse(receiptData['totalDebit']?.toString() ?? '0') ?? 0;
      double totalCredit =
          double.tryParse(receiptData['totalCredit']?.toString() ?? '0') ?? 0;
      double totalother =
          double.tryParse(receiptData['totalother']?.toString() ?? '0') ?? 0;
      double totalQris =
          double.tryParse(receiptData['totalQris']?.toString() ?? '0') ?? 0;
      double totalVa =
          double.tryParse(receiptData['totalVa']?.toString() ?? '0') ?? 0;
      double totalQronline =
          double.tryParse(receiptData['totalQronline']?.toString() ?? '0') ?? 0;
      double totalDiscount =
          double.tryParse(receiptData['totalDiscount']?.toString() ?? '0') ?? 0;
      double totalRounding =
          double.tryParse(receiptData['totalRounding']?.toString() ?? '0') ?? 0;
      double totalTax =
          double.tryParse(receiptData['totalTax']?.toString() ?? '0') ?? 0;
      double totalService =
          double.tryParse(receiptData['totalService']?.toString() ?? '0') ?? 0;

      // isi struk
      final sb = StringBuffer();
      sb.writeln("        Close Session");
      sb.writeln("         Treat A Cup");
      sb.writeln("      $addr");
      sb.writeln("");
      sb.writeln("Tanggal    : $formattedDateTime");
      sb.writeln("Kasir      : $kasir");
      sb.writeln("Session POS: $sessionPos");
      sb.writeln("");
      sb.writeln("Item        Qty    Harga");

      for (var item in items) {
        String itemName = item['name'].toString().toUpperCase();
        String itemQty = item['total_quantity']?.toString() ?? '0';
        double itemPriceValue =
            double.tryParse(item['price']?.toString() ?? '0') ?? 0;
        double itemTotalValue =
            double.tryParse(item['total']?.toString() ?? '0') ?? 0;

        String itemPrice = formatRupiah(itemPriceValue);
        String itemTotal = formatRupiah(itemTotalValue);

        sb.writeln(itemName);
        sb.writeln("$itemPrice x $itemQty = $itemTotal");
      }

      sb.writeln("");
      sb.writeln("Sub Total     : ${formatRupiah(subTotal)}");
      sb.writeln("Discount      : ${formatRupiah(totalDiscount)}");
      sb.writeln("PB1           : ${formatRupiah(totalTax)}");
      sb.writeln("Service Charge: ${formatRupiah(totalService)}");
      sb.writeln("Rounded       : ${formatRupiah(totalRounding)}");
      sb.writeln("");
      sb.writeln("Total Cash    : ${formatRupiah(totalCash)}");
      sb.writeln("Total Debit   : ${formatRupiah(totalDebit)}");
      sb.writeln("Total Credit  : ${formatRupiah(totalCredit)}");
      sb.writeln("Total QRIS    : ${formatRupiah(totalQris)}");
      sb.writeln("Total Other   : ${formatRupiah(totalother)}");
      double total =
          totalCash + totalDebit + totalQris + totalCredit + totalother;
      sb.writeln("");
      sb.writeln("Grand Total   : ${formatRupiah(total)}");
      sb.writeln("");
      sb.writeln("Online Sale");
      sb.writeln("Total VA      : ${formatRupiah(totalVa)}");
      sb.writeln("Total Qronline: ${formatRupiah(totalQronline)}");
      double totalVirtual = totalVa + totalQronline;
      sb.writeln("");
      sb.writeln("Total Online  : ${formatRupiah(totalVirtual)}");
      sb.writeln("\n\n\n\n\n\n");

      // ubah ke byte ESC/POS
      final bytes = <int>[
        27, 64, // reset
        ...utf8.encode(sb.toString()),
        29, 86, 1, // cut
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
      }
    } finally {
      if (hPrinter.value != 0) ClosePrinter(hPrinter.value);
      calloc.free(hPrinter);
      calloc.free(jobInfo);
      calloc.free(utf16Doc);
      calloc.free(utf16PrinterName);
      if (dataPtr != null) calloc.free(dataPtr);
      if (bytesWrittenPtr != null) calloc.free(bytesWrittenPtr);
      await Wakelock.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Mencegah kembali ke halaman sebelumnya
      child: ScaffoldMessenger(
        key: _scaffoldMessengerKey,
        child: Scaffold(
          appBar: AppBar(
            title: const Text(
              "End of Day",
              style: TextStyle(color: Colors.black),
            ),
            backgroundColor: Colors.red[50],
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.black),
            automaticallyImplyLeading: false, // Menghapus tombol back di AppBar
          ),
          backgroundColor: Colors.red[50],
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(
                        vertical: 15, horizontal: 30),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.normal),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    _updateEndDate();
                    _showMessage("Mencetak ulang data End of Day...");
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.print, color: Colors.white),
                      SizedBox(width: 10),
                      Text("Print Ulang Data",
                          style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(
                        vertical: 15, horizontal: 30),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.normal),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isLoading ? null : _handleLogout,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.logout, color: Colors.white),
                            SizedBox(width: 10),
                            Text("Lanjutkan",
                                style: TextStyle(color: Colors.white)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
