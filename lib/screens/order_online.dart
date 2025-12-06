import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:mposv2/screens/payment_screen.dart';
import 'package:wakelock/wakelock.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;

class OrderOnline extends StatefulWidget {
  const OrderOnline({super.key});

  @override
  State<OrderOnline> createState() => _OrderOnlineState();
}

class _OrderOnlineState extends State<OrderOnline>
    with SingleTickerProviderStateMixin {
  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  Map<String, List<dynamic>> groupedOrders = {
    "masuk": [],
    "proses": [],
    "kirim": []
  };
  List<String> courierList = [];
  bool isLoading = true;
  String? selectedKurir;
  String? selected;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    _tabController = TabController(length: 3, vsync: this);
    loadData();
  }

  Future<void> loadData() async {
    setState(() {
      isLoading = true;
    });
    _loadSavedPrinter();
    await _fetchOrders();
    fetchKurir();

    setState(() {
      isLoading = false;
    });
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
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

  Future<void> fetchKurir() async {
    final token = await getToken();
    final branch = await _getBranch();
    final domain = await _getDomain();
    final device = await _getDevice();

    if (branch == null || branch.isEmpty || domain == null || domain.isEmpty) {
      throw Exception('Branch/Domain not found in local storage');
    }

    final uri = Uri.parse('$domain/api/online-order-courier');
    final body = {
      'device_id': device,
      'sub_branch': branch,
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
      final parsed = json.decode(response.body);
      final List data = parsed is List ? parsed : parsed['data'];
      setState(() {
        courierList =
            data.map((item) => item['name'].toString()).toSet().toList();
      });
    } else {
      print("Failed to fetch location: ${response.statusCode}");
    }
  }

  Future<Map<String, dynamic>> fetchOrderDetail(String idOrder) async {
    final token = await getToken();
    final branch = await _getBranch();
    final domain = await _getDomain();

    if (branch == null || branch.isEmpty || domain == null || domain.isEmpty) {
      throw Exception('Branch/Domain not found in local storage');
    }

    final uri = Uri.parse('$domain/api/detail-order-online');
    final body = {
      'idOrder': idOrder,
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
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else {
        throw Exception("Response bukan Map: $decoded");
      }
    } else {
      throw Exception("Gagal mengambil detail order (${response.statusCode})");
    }
  }

  void updateStatus(
      BuildContext context, String orderId, String currentStatus) async {
    final token = await getToken();
    final branch = await _getBranch();
    final domain = await _getDomain();
    final prefs = await SharedPreferences.getInstance();
    int printCaptainQty = prefs.getInt('print_captain_qty') ?? 1;

    if (branch == null || branch.isEmpty || domain == null || domain.isEmpty) {
      throw Exception('Branch/Domain not found in local storage');
    }

    final uri = Uri.parse('$domain/api/online-update-proses');
    final body = {
      'orderId': orderId,
      'currentStatus': currentStatus,
    };

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final String message =
            responseData['message'] ?? 'Status berhasil diperbarui';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );

        final data = responseData['order'];
        for (int i = 0; i < printCaptainQty; i++) {
          if (Platform.isWindows) {
            await _printCaptainOrderWindowsFFI(
                context, data); // Kirim context & data
          } else {
            await _printCaptainOrder(data);
          }
        }
        Navigator.pop(context);
        loadData();
      } else {
        String errorMessage = 'Failed to update status: ${response.statusCode}';
        try {
          final Map<String, dynamic> responseData = jsonDecode(response.body);
          if (responseData.containsKey('message')) {
            errorMessage = responseData['message'];
          }
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal update status: $e")),
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  bool writeRawToPrinter(String printerName, List<int> bytes,
      {String docName = 'CaptainOrder'}) {
    if (!Platform.isWindows) return false;

    final hPrinter = calloc<HANDLE>();
    final lpPrinterName = printerName.toNativeUtf16();
    final pDocName = docName.toNativeUtf16();
    final pDataType = 'RAW'.toNativeUtf16();

    final pDocInfo = calloc<DOC_INFO_1>()
      ..ref.pDocName = pDocName
      ..ref.pOutputFile = ffi.nullptr
      ..ref.pDatatype = pDataType;

    ffi.Pointer<ffi.Uint8>? dataPtr;
    final bytesWritten = calloc<ffi.Uint32>();

    try {
      final okOpen = OpenPrinter(lpPrinterName, hPrinter, ffi.nullptr);
      if (okOpen == 0) {
        return false;
      }

      final jobId = StartDocPrinter(hPrinter.value, 1, pDocInfo.cast());
      if (jobId == 0) {
        ClosePrinter(hPrinter.value);
        return false;
      }

      StartPagePrinter(hPrinter.value);

      dataPtr = calloc<ffi.Uint8>(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        dataPtr[i] = bytes[i];
      }

      final okWrite = WritePrinter(
          hPrinter.value, dataPtr.cast(), bytes.length, bytesWritten);
      EndPagePrinter(hPrinter.value);
      EndDocPrinter(hPrinter.value);
      ClosePrinter(hPrinter.value);

      return okWrite != 0 && bytesWritten.value == bytes.length;
    } finally {
      calloc.free(hPrinter);
      calloc.free(lpPrinterName);
      calloc.free(pDocInfo);
      calloc.free(pDocName);
      calloc.free(pDataType);
      if (dataPtr != null) calloc.free(dataPtr);
      calloc.free(bytesWritten);
    }
  }

  Future<void> _printCaptainOrderWindowsFFI(
      BuildContext context, Map<String, dynamic> order) async {
    if (!Platform.isWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Print Captain Order (Windows) hanya tersedia di Windows")),
      );
      return;
    }

    await Wakelock.enable();
    try {
      // === Ambil header & details dari 'order' ===
      final header = order;
      final details = List<Map<String, dynamic>>.from(order['details'] ?? []);

      // Tanggal
      final createdAt = (header['created_at'] ?? '').toString();
      final dt = DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now();
      final formatted = DateFormat('dd-MM-yyyy HH:mm:ss').format(dt);

      // ID / Struk
      final rawId = (header['id_post_header'] ?? '').toString();
      final idsession = rawId;

      // Customer / Phone (opsional)
      final prefs = await SharedPreferences.getInstance();
      String customerName = (header['customer_name'] ?? '-').toString();
      String userPhone = (header['customer_phone'] ?? '-').toString();
      if (userPhone.startsWith('0')) {
        userPhone = userPhone.replaceFirst('0', '+62');
      } else if (!userPhone.startsWith('+62') && userPhone != '-') {
        userPhone = '+62$userPhone';
      }

      // Printer names
      final printerKitchen = prefs.getString('usb_printer_kitchen'); // opsional
      final printerBar = prefs.getString('usb_printer_bar'); // opsional
      final printerFallback =
          prefs.getString('usb_printer_name'); // fallback umum

      // Pisah item by kategori (print_co: dapur/bar)
      final listDapur = <String>[];
      final listBar = <String>[];

      for (final it in details) {
        final name = (it['name'] ?? '').toString().toUpperCase();
        final qty = (it['qty'] ?? it['quantity'] ?? '').toString();
        final kategori = (it['print_co'] ?? '').toString().toLowerCase();

        final line = "- $qty x $name";
        if (kategori == 'dapur') {
          listDapur.add(line);
        } else if (kategori == 'bar') {
          listBar.add(line);
        }
      }

      // Header umum (tanpa harga/total)
      final commonHeader = StringBuffer()
        ..writeln("ID      : $idsession")
        ..writeln("Customer: $customerName")
        ..writeln("No. HP  : $userPhone")
        ..writeln("Tanggal : $formatted")
        ..writeln("Type    : DELIVERY")
        ..writeln("");

      // === Builder ESC/POS ===
      List<int> _escInit() => [27, 64]; // ESC @ (init)
      List<int> _alignLeft() => [27, 97, 0]; // ESC a 0
      List<int> _alignCenter() => [27, 97, 1]; // ESC a 1
      List<int> _boldOn() => [27, 69, 1]; // ESC E 1
      List<int> _boldOff() => [27, 69, 0]; // ESC E 0
      List<int> _cut() => [29, 86, 1]; // GS V 1 (partial cut)
      List<int> _nl([int n = 1]) => List<int>.filled(n, 10); // LF

      List<int> _text(String s) => utf8.encode(s);

      List<int> _buildSection(
          {required String title,
          required StringBuffer header,
          required List<String> lines}) {
        final bytes = <int>[];
        bytes.addAll(_escInit());
        bytes.addAll(_alignCenter());
        bytes.addAll(_boldOn());
        bytes.addAll(_text("== $title ==\n"));
        bytes.addAll(_boldOff());
        bytes.addAll(_nl());

        bytes.addAll(_alignLeft());
        bytes.addAll(_text(header.toString()));

        for (final l in lines) {
          bytes.addAll(_text("$l\n"));
        }

        bytes.addAll(_nl());
        bytes.addAll(_alignCenter());
        bytes.addAll(_text("------------------\n"));
        bytes.addAll(_nl(2));
        bytes.addAll(_cut());
        return bytes;
      }

      // === Siapkan payload untuk masing-masing kategori ===
      final bytesDapur = listDapur.isNotEmpty
          ? _buildSection(
              title: "DAPUR", header: commonHeader, lines: listDapur)
          : <int>[];

      final bytesBar = listBar.isNotEmpty
          ? _buildSection(title: "BAR", header: commonHeader, lines: listBar)
          : <int>[];

      // === Routing ke printer Windows ===
      bool anyPrinted = false;

      // Dapur
      if (bytesDapur.isNotEmpty) {
        final target = (printerKitchen != null && printerKitchen.isNotEmpty)
            ? printerKitchen
            : (printerFallback ?? '');
        if (target.isNotEmpty) {
          final ok = writeRawToPrinter(target, bytesDapur,
              docName: "CaptainOrder-Dapur");
          anyPrinted = anyPrinted || ok;
          if (!ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Gagal print DAPUR ke printer: $target")),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Printer DAPUR tidak diset.")),
          );
        }
      }

      // Bar
      if (bytesBar.isNotEmpty) {
        final target = (printerBar != null && printerBar.isNotEmpty)
            ? printerBar
            : (printerFallback ?? '');
        if (target.isNotEmpty) {
          final ok =
              writeRawToPrinter(target, bytesBar, docName: "CaptainOrder-Bar");
          anyPrinted = anyPrinted || ok;
          if (!ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Gagal print BAR ke printer: $target")),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Printer BAR tidak diset.")),
          );
        }
      }

      if (anyPrinted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Captain Order berhasil dicetak")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Tidak ada data untuk dicetak atau printer belum diset")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error print Captain Order: $e")),
      );
    } finally {
      await Wakelock.disable();
    }
  }

  Future<void> _printCaptainOrder(Map<String, dynamic> data) async {
    if (!isConnected) {
      _showMessage("Printer belum terhubung!");
      return;
    }
    await Wakelock.enable();
    try {
      final header = data;
      final details = List<Map<String, dynamic>>.from(header['details'] ?? []);

      // Pastikan created_at ada
      final createdAt = header['created_at'] ?? '';
      final dateTime =
          DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now();
      final formattedDateTime =
          DateFormat('dd-MM-yyyy HH:mm:ss').format(dateTime);

      String idPostHeader = (header['id_post_header'] ?? '').toString();
      // Hindari error substring jika panjang < 4
      String idsession = idPostHeader;

      final prefs = await SharedPreferences.getInstance();
      String customerName = (header['customer_name'] ?? '-').toString();
      String userPhone = (header['customer_phone'] ?? '-');

      if (userPhone.startsWith('0')) {
        userPhone = userPhone.replaceFirst('0', '+62');
      } else if (!userPhone.startsWith('+62')) {
        userPhone = '+62$userPhone';
      }

      String? ipDapur = prefs.getString('ip_printer_dapur');
      String? ipBar = prefs.getString('ip_printer_bar');
      // Ambil printQty di sini jika ingin dipakai untuk LAN
      int printQty = prefs.getInt('print_captain_qty') ?? 1;

      List<String> listDapur = [];
      List<String> listBar = [];

      for (var item in details) {
        String name = (item['name'] ?? '').toString().toUpperCase();
        String qty = (item['qty'] ?? item['quantity'] ?? '').toString();
        String kategori = (item['print_co'] ?? '').toString().toLowerCase();

        String line = "- $qty x $name";
        if (kategori == 'dapur') {
          listDapur.add(line);
        } else if (kategori == 'bar') {
          listBar.add(line);
        }
      }

      String commonHeader =
          "ID      : $idsession\nCustomer: $customerName\nNo. HP  : $userPhone\nTanggal : $formattedDateTime\nType    : DELIVERY \n";

      // Cetak ke Printer Bluetooth jika diaktifkan
      bool printCaptain = prefs.getBool('print_captain') ?? false;
      if (printCaptain) {
        if (listDapur.isNotEmpty) {
          printer.printNewLine();
          printer.printCustom("== DAPUR ==", 1, 1);
          printer.printCustom(commonHeader, 1, 0);
          for (var line in listDapur) {
            printer.printCustom(line, 1, 0);
          }
          printer.printNewLine();
          printer.printCustom("------------------", 1, 1);
          sendRawCutCommand();
        }
        if (listBar.isNotEmpty) {
          printer.printNewLine();
          printer.printCustom("== BAR ==", 1, 1);
          printer.printCustom(commonHeader, 1, 0);
          for (var line in listBar) {
            printer.printCustom(line, 1, 0);
          }
          printer.printNewLine();
          printer.printCustom("------------------", 1, 1);
          sendRawCutCommand();
        }
      }

      // Cetak ke Printer LAN jika IP tersedia
      if (ipDapur != null && ipDapur.isNotEmpty && listDapur.isNotEmpty) {
        String content = '$commonHeader${listDapur.join('\n')}\n\n';
        for (int i = 0; i < printQty; i++) {
          await printCaptainToLAN(ipDapur, content);
        }
      }
      if (ipBar != null && ipBar.isNotEmpty && listBar.isNotEmpty) {
        String content = '$commonHeader${listBar.join('\n')}\n\n';
        for (int i = 0; i < printQty; i++) {
          await printCaptainToLAN(ipBar, content);
        }
      }

      _showMessage("Captain Order berhasil dicetak");
    } catch (e) {
      _showMessage("Error saat mencetak: $e");
    } finally {
      await Wakelock.disable();
    }
  }

  void sendRawCutCommand() {
    final List<int> cutCommand = [0x1D, 0x56, 0x42, 0x00]; // Full cut command
    final Uint8List bytes = Uint8List.fromList(cutCommand);
    BlueThermalPrinter.instance.writeBytes(bytes);
  }

  Widget buildOrderList(String type) {
    final list = groupedOrders[type] ?? [];
    if (list.isEmpty) {
      return Center(child: Text("Tidak ada order $type"));
    }

    // Jika "masuk": flat list seperti sebelumnya
    if (type == 'masuk') {
      return _buildFlatOrderList(list);
    }

    // Jika "proses" atau "kirim": nested group per device
    return RefreshIndicator(
      onRefresh: _fetchOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(6),
        itemCount: list.length,
        itemBuilder: (context, groupIndex) {
          final group = list[groupIndex];
          final deviceName = group['device_name'] ?? '-';
          final orders = group['orders'] as List<dynamic>;
          // Ambil status dari order pertama (asumsi satu group statusnya sama)
          final orderStatus =
              orders.isNotEmpty ? orders.first['order_status'] : 'processing';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Device dengan tombol di kanan
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 2,
                  horizontal: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      deviceName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (orderStatus == 'processing')
                      (ElevatedButton(
                        onPressed: () async {
                          final selectedCourier = await showDialog<String>(
                            context: context,
                            builder: (context) {
                              String? tempSelected =
                                  selectedKurir; // simpan sementara untuk dialog
                              return StatefulBuilder(
                                builder: (context, setStateDialog) {
                                  return AlertDialog(
                                    title: const Text("Pengantar"),
                                    content: DropdownButton<String>(
                                      value: courierList.contains(tempSelected)
                                          ? tempSelected
                                          : null,
                                      hint: const Text("--Pilih--",
                                          style: TextStyle(fontSize: 13)),
                                      isExpanded: true,
                                      style: const TextStyle(
                                          fontSize: 13, color: Colors.black),
                                      items: courierList
                                          .toSet()
                                          .map((String kurir) {
                                        return DropdownMenuItem<String>(
                                          value: kurir,
                                          child: Text(kurir,
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                        );
                                      }).toList(),
                                      onChanged: (String? newValue) {
                                        setStateDialog(() {
                                          tempSelected = newValue;
                                        });
                                      },
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text("Batal"),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          if (tempSelected != null) {
                                            Navigator.pop(
                                                context, tempSelected);
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 10),
                                        ),
                                        child: const Text(
                                          "Kirim",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );

                          if (selectedCourier != null) {
                            setState(() {
                              selectedKurir =
                                  selectedCourier; // update ke parent state
                            });
                            await sendOrdersForDevice(
                              deviceName: deviceName,
                              courier: selectedCourier,
                              orders: orders,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        child: const Text(
                          "Kirim",
                          style: TextStyle(color: Colors.white),
                        ),
                      )),
                    if (orderStatus == 'shipped')
                      (ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        onPressed: () async {
                          await sendOrdersDelivered(
                            orders: orders,
                          );
                        },
                        child: const Text(
                          "Delivered",
                          style: TextStyle(color: Colors.white),
                        ),
                      )),
                  ],
                ),
              ),

              // List order di bawahnya
              ...orders.map((order) {
                DateTime dateTime =
                    DateTime.parse(order['created_at']).toLocal();
                String formattedDateTime =
                    DateFormat('dd-MM-yyyy HH:mm:ss').format(dateTime);
                return _buildOrderCard(order, formattedDateTime);
              }).toList(),

              const SizedBox(height: 10),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _getDomain() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('domain');
  }

  Future<String?> _getBranch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_branch_name');
  }

  Future<String?> _getDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id');
  }

  Future<void> _fetchOrders() async {
    final token = await getToken();

    try {
      final branch = await _getBranch();
      final domain = await _getDomain();
      final device = await _getDevice();

      if (branch == null ||
          branch.isEmpty ||
          domain == null ||
          domain.isEmpty) {
        throw Exception('Branch/Domain not found in local storage');
      }

      final uri = Uri.parse('$domain/api/new-order-online');
      final body = {
        'sub_branch': branch,
        'device_id': device,
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
          groupedOrders = Map<String, List<dynamic>>.from(
            data['data'].map(
              (key, value) => MapEntry(key, List<dynamic>.from(value)),
            ),
          );
        });
      } else {
        print("Failed to load orders: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching orders: $e");
    }
  }

  Future<void> sendOrdersForDevice({
    required String deviceName,
    required String courier,
    required List<dynamic> orders,
  }) async {
    try {
      final orderIds = orders.map((o) => o['id_post_header']).toList();
      final token = await getToken();
      final branch = await _getBranch();
      final domain = await _getDomain();
      final device = await _getDevice();
      if (branch == null ||
          branch.isEmpty ||
          domain == null ||
          domain.isEmpty) {
        throw Exception('Branch/Domain not found in local storage');
      }

      final uri = Uri.parse('$domain/api/send-orders');
      final body = {
        'device': device,
        'courier': courier,
        'orders': orderIds,
        'branch': branch,
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
        // Sukses update
        print("Pesanan berhasil dikirim ke backend");

        loadData();
      } else {
        print("Gagal kirim: ${response.body}");
      }
    } catch (e) {
      print("Error kirim pesanan: $e");
    }
  }

  Future<void> sendOrdersDelivered({
    required List<dynamic> orders,
  }) async {
    try {
      final orderIds = orders.map((o) => o['id_post_header']).toList();
      final token = await getToken();
      final branch = await _getBranch();
      final domain = await _getDomain();
      final device = await _getDevice();
      if (branch == null ||
          branch.isEmpty ||
          domain == null ||
          domain.isEmpty) {
        throw Exception('Branch/Domain not found in local storage');
      }

      final uri = Uri.parse('$domain/api/send-orders-delivered');
      final body = {
        'device': device,
        'orders': orderIds,
        'branch': branch,
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
        // Sukses update
        print("Pesanan berhasil dikirim ke backend");

        loadData();
      } else {
        print("Gagal kirim: ${response.body}");
      }
    } catch (e) {
      print("Error kirim pesanan: $e");
    }
  }

  void _showProcessDialog(BuildContext context, Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) {
        String currentStatus = order['order_status'];
        String? nextAction;

        switch (currentStatus) {
          case "new":
            nextAction = "Proses";

            break;
          case "processing":
            nextAction = "Kirim";

            break;
          case "ready":
            nextAction = "Shipped";

            break;
          case "shipped":
            nextAction = "Delivered";

            break;
          default:
            nextAction = null;
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text("Order #${order['id_post_header']}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Customer: ${order['customer_name']}"),
              const SizedBox(height: 10),
              Text("Status Saat Ini: ${currentStatus.toUpperCase()}"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Tutup"),
            ),
            if (nextAction != null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // hijau
                  foregroundColor: Colors.white, // teks putih
                ),
                onPressed: () {
                  // Kirim params ke updateStatus
                  updateStatus(
                    context,
                    order['id_post_header'].toString(),
                    currentStatus,
                  );
                },
                child: Text(nextAction),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showOrderDetailDialog(dynamic order) async {
    try {
      final detail = await fetchOrderDetail(order['id_post_header'].toString());
      final _currencyFormatter = NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp',
        decimalDigits: 0,
      );

      final List<dynamic> items = detail['data'] ?? [];

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Detail Order #${order['id_post_header']}"),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var item in items) ...[
                    Text(
                      "${item['name']} ${item['quantity']} x ${_currencyFormatter.format(
                        (item['price'] is num)
                            ? item['price']
                            : double.tryParse(item['price'].toString()) ?? 0,
                      )}",
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Divider(),
                  // Jika ingin menampilkan total semua item:
                  Text(
                    "Total: ${_currencyFormatter.format(
                      items.fold<num>(
                          0,
                          (sum, item) =>
                              sum +
                              (item['quantity'] ?? 0) *
                                  ((item['price'] is num)
                                      ? item['price']
                                      : double.tryParse(
                                              item['price'].toString()) ??
                                          0)),
                    )}",
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Tutup"),
              ),
            ],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  Widget _buildBadgeTab(String label, int count, IconData icon) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            "$label ($count)",
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w100),
          ),
        ],
      ),
    );
  }

  Color _getCardColor(String status) {
    switch (status.toLowerCase()) {
      case 'new':
        return Colors.blue[50]!;
      case 'processing':
        return Colors.orange[50]!;
      case 'shipped':
        return Colors.green[100]!;
      default:
        return Colors.blue[50]!;
    }
  }

  Widget _buildFlatOrderList(List<dynamic> list) {
    return RefreshIndicator(
      onRefresh: _fetchOrders,
      child: ListView.separated(
        padding: const EdgeInsets.all(6),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final order = list[index];
          DateTime dateTime = DateTime.parse(order['created_at']).toLocal();
          String formattedDateTime =
              DateFormat('dd-MM-yyyy HH:mm:ss').format(dateTime);
          return _buildOrderCard(order, formattedDateTime);
        },
      ),
    );
  }

// Card order dipisahkan ke widget reusable
  Widget _buildOrderCard(
    dynamic order,
    String formattedDateTime,
  ) {
    return GestureDetector(
      onTap: () {
        if (order['order_status'] == 'new') {
          _showProcessDialog(context, order);
        }
      },
      child: Card(
        elevation: 2,
        color: _getCardColor(order['order_status']),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device Title
              if (order['order_status'] == 'new') ...[
                Text(
                  order["device_name"] ?? "-",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                _buildDetailRow("Order id", order["id_post_header"] ?? "-"),
                _buildDetailRow("Cust Name", order["customer_name"] ?? "-"),
                _buildDetailRow("Cust Phone", order["customer_phone"] ?? "-"),
                _buildDetailRow("Qty", order["total_qty"].toString()),
                _buildDetailRow("Date", formattedDateTime),
              ] else if (order['order_status'] == 'shipped') ...[
                _buildDetailRow("Order id", order["id_post_header"] ?? "-"),
                _buildDetailRow("Diantar", order["courier"] ?? "-"),
                _buildDetailRow("Cust Name", order["customer_name"] ?? "-"),
                _buildDetailRow("Cust Phone", order["customer_phone"] ?? "-"),
              ] else ...[
                _buildDetailRow("Order id", order["id_post_header"] ?? "-"),
                _buildDetailRow("Cust Name", order["customer_name"] ?? "-"),
                _buildDetailRow("Cust Phone", order["customer_phone"] ?? "-"),
                _buildDetailRow("Qty", order["total_qty"].toString()),
                _buildDetailRow("Date", formattedDateTime),
              ],

              const SizedBox(height: 8),

              // Total + Badge Lunas
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Kiri: Grand Total + LUNAS
                  Row(
                    children: [
                      Text(
                        NumberFormat.currency(
                                locale: 'id', symbol: "Rp ", decimalDigits: 0)
                            .format(double.tryParse(
                                    order["grand_total"].toString()) ??
                                0),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[500],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          "LUNAS",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),

                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      try {
                        final detail = await fetchOrderDetail(
                            order['id_post_header'].toString());
                        final _currencyFormatter = NumberFormat.currency(
                          locale: 'id_ID',
                          symbol: 'Rp',
                          decimalDigits: 0,
                        );

                        // Hitung total manual
                        final List<dynamic> items = detail['data'] ?? [];
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: Text(
                                  "Detail Order #${order['id_post_header']}"),
                              content: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var item in items) ...[
                                      Text(
                                        "${item['name']} ${item['quantity']} x ${_currencyFormatter.format(
                                          (item['price'] is num)
                                              ? item['price']
                                              : double.tryParse(item['price']
                                                      .toString()) ??
                                                  0,
                                        )}",
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    const Divider(),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Tutup"),
                                ),
                              ],
                            );
                          },
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error: $e")),
                        );
                      }
                    },
                    child: const Text(
                      "Detail Orders",
                      style: TextStyle(
                        color: Colors.white, // teks putih
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  /// Widget bantu supaya detail lebih rapi
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 75,
            child: Text(
              "$label:",
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Online'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            _buildBadgeTab(
                "Masuk", groupedOrders["masuk"]?.length ?? 0, Icons.inbox),
            _buildBadgeTab(
                "Proses", groupedOrders["proses"]?.length ?? 0, Icons.settings),
            _buildBadgeTab("Kirim", groupedOrders["kirim"]?.length ?? 0,
                Icons.local_shipping),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                buildOrderList("masuk"),
                buildOrderList("proses"),
                buildOrderList("kirim"),
              ],
            ),
    );
  }
}
