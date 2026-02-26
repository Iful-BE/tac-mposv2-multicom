import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:mposv2/screens/sales_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock/wakelock.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:image/image.dart' as img;
import 'package:collection/collection.dart';

class TransactionQue extends StatefulWidget {
  const TransactionQue({super.key});

  @override
  _TransactionScreenState createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionQue> {
  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> filteredItems = [];
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    _fetchTransactionData();
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

  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id');
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

  Future<void> _fetchTransactionData() async {
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

      final uri = Uri.parse('$domain/api/cart/hold-transaksi');

      // Jika selectedDate tidak null, kirim dalam format yyyy-MM-dd
      final body = {
        'sub_branch': branch,
        'session_id': sessionId,
        'userPos': userPos,
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
        final decoded = jsonDecode(response.body);

        setState(() {
          items = List<Map<String, dynamic>>.from(decoded['data']);
          filteredItems = items;
        });
      }
    } catch (e) {
      print("Error fetching transaction: $e");
    }
  }

  Future<void> _printHoldTransaction(String antrianId) async {
    final token = await getToken();
    final domain = await getDomainFromLocalStorage();
    final branch = await getBranchFromLocalStorage();
    final device = await getDeviceId();
    final session = await getSession();

    if (domain == null || token == null) {
      _showMessage("Domain atau token tidak ditemukan");
      return;
    }

    // === Tampilkan loading dialog ===
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text(
                  "Mencetak struk sementara...",
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );

    final body = {
      'antrian_id': antrianId,
      'branch': branch,
      'device': device,
      'session': session,
    };

    final uri = Uri.parse("$domain/api/cart/print-hold");

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      Navigator.pop(context); // Tutup loading dialog

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["success"] == true) {
          await _doPrintTagihan(data["data"]);
        } else {
          _showMessage("Gagal print: ${data['message'] ?? 'Unknown error'}");
        }
      } else {
        _showMessage("Gagal request print: ${response.statusCode}");
      }
    } catch (e) {
      Navigator.pop(context); // Pastikan loading selalu ditutup
      _showMessage("Error saat print: $e");
    }
  }

  Future<void> _doPrintTagihan(Map<String, dynamic> trx) async {
    try {
      if (!isConnected) await _connectToPrinter();

      await _printLogo();
      printer.printNewLine();
      printer.printCustom("Struk Sementara", 1, 1);
      printer.printNewLine();

      printer.printCustom("Tgl  : ${trx['tanggal'] ?? '-'}", 1, 0);
      printer.printCustom("Kasir: ${trx['kasir'] ?? '-'}", 1, 0);
      printer.printCustom("Cust : ${trx['customer'] ?? '-'}", 1, 0);
      printer.printCustom("Meja : ${trx['table'] ?? '-'}", 1, 0);
      printer.printCustom("Note : ${trx['note'] ?? '-'}", 1, 0);
      printer.printNewLine();

      printer.printCustom("------------------------------", 1, 0);
      printer.printCustom("Item                 Qty   Sub", 1, 0);
      printer.printCustom("------------------------------", 1, 0);

      final List<dynamic> detailItems = trx['items'] ?? [];

      for (var item in detailItems) {
        final nama = item['nama']?.toString() ?? '';
        final qty = item['qty']?.toString() ?? '0';
        final harga = formatRupiah(
            (num.tryParse(item['harga'].toString()) ?? 0).toDouble());
        final subtotal = formatRupiah(
            (num.tryParse(item['subtotal'].toString()) ?? 0).toDouble());

        // Cetak nama produk
        printer.printCustom(nama.toUpperCase(), 1, 0);
        // Cetak qty, harga, dan total dalam satu baris
        printer.printCustom("$qty x $harga = $subtotal", 1, 0);
      }

      printer.printCustom("------------------------------", 1, 0);

// SUBTOTAL
      printer.printCustom(
        "Sub Total : ${formatRupiah(num.tryParse(trx['subtotal'].toString())?.toDouble() ?? 0)}",
        1,
        0,
      );

// DISKON
      printer.printCustom(
        "Diskon    : ${formatRupiah(num.tryParse(trx['discount'].toString())?.toDouble() ?? 0)}",
        1,
        0,
      );

// TOTAL SETELAH DISKON (subtotal - diskon)
      printer.printCustom(
        "Total     : ${formatRupiah(num.tryParse(trx['total_after_discount'].toString())?.toDouble() ?? 0)}",
        1,
        0,
      );

// SERVICE CHARGE
      printer.printCustom(
        "S.Charge  : ${formatRupiah(num.tryParse(trx['service_charge'].toString())?.toDouble() ?? 0)}",
        1,
        0,
      );

// PAJAK
      printer.printCustom(
        "PB1       : ${formatRupiah(num.tryParse(trx['tax'].toString())?.toDouble() ?? 0)}",
        1,
        0,
      );

      // ROUNDING
      printer.printCustom(
        "Rounding  : ${formatRupiah(num.tryParse(trx['rounding'].toString())?.toDouble() ?? 0)}",
        1,
        0,
      );

// GRAND TOTAL
      printer.printCustom(
        "Grand Total : ${formatRupiah(num.tryParse(trx['grand_total'].toString())?.toDouble() ?? 0)}",
        1,
        0,
      );

      printer.printNewLine();
      printer.printCustom("Terima kasih", 1, 1);
      printer.printNewLine();
      sendRawCutCommand();
    } catch (e) {
      _showMessage("Gagal mencetak tagihan: $e");
    }
  }

  void sendRawCutCommand() {
    final List<int> cutCommand = [0x1D, 0x56, 0x42, 0x00]; // Full cut command
    final Uint8List bytes = Uint8List.fromList(cutCommand);
    BlueThermalPrinter.instance.writeBytes(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hold Transaction')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // 🔍 SEARCH FIELD
            TextField(
              controller: searchController,
              onChanged: (value) {
                String query = value.toLowerCase();

                setState(() {
                  filteredItems = items.where((item) {
                    final meja =
                        (item['table_id'] ?? '').toString().toLowerCase();
                    final note = (item['note'] ?? '').toString().toLowerCase();
                    final customer =
                        (item['nama'] ?? '').toString().toLowerCase();

                    return meja.contains(query) ||
                        note.contains(query) ||
                        customer.contains(query);
                  }).toList();
                });
              },
              decoration: InputDecoration(
                hintText: "Cari meja / note / customer...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: filteredItems.isEmpty
                  ? const Center(
                      child: Text(
                        "Tidak ada data",
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final antrian = filteredItems[index];

                        return Card(
                          color: Colors.blueGrey.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          margin: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 12),
                          child: ListTile(
                            title: Text(
                              'Meja: ${antrian['table_id'] ?? 'Tidak ada'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hold Id: ${antrian['antrian_id'] ?? '-'}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Note: ${antrian['note'] ?? ''}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Customer: ${antrian['nama'] ?? ''}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Total Item: ${antrian['total_quantity'] ?? 0}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.print,
                                      color: Colors.white),
                                  onPressed: () => _printHoldTransaction(
                                      antrian['antrian_id']),
                                ),
                                const Icon(Icons.arrow_forward_ios,
                                    color: Colors.white),
                              ],
                            ),
                            onTap: () async {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              final localUserId =
                                  prefs.getString('user_id') ?? '';
                              final mgTable =
                                  prefs.getBool('aktif_table') ?? false;

                              final kasirId = antrian['kasir_id'];
                              // print('localUserId = $localUserId');
                              // print('kasirId = $kasirId');
                              // print('mgTable = $mgTable');
                              // if (localUserId != kasirId && mgTable == false) {
                              //   ScaffoldMessenger.of(context).showSnackBar(
                              //     const SnackBar(
                              //       content: Text(
                              //         'Antrian bisa diproses oleh user upselling',
                              //         style: TextStyle(
                              //             fontWeight: FontWeight.bold),
                              //       ),
                              //       backgroundColor: Colors.red,
                              //       duration: Duration(seconds: 2),
                              //     ),
                              //   );
                              //   return;
                              // }

                              await prefs.remove('customer_name');
                              await prefs.remove('user_phone');
                              final phone = antrian['nomor'] ?? '';
                              await prefs.setString('user_phone', phone);
                              final custname = antrian['nama'] ?? '';
                              await prefs.setString('customer_name', custname);

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SalesScreen(
                                    isSelfService: false,
                                    antrianId: antrian['antrian_id'],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}
