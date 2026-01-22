import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:intl/intl.dart';
import 'package:mposv2/screens/home_screen.dart';
import 'package:mposv2/screens/login_screen.dart';
import 'package:mposv2/screens/payment_screen.dart';
import 'package:mposv2/screens/sales_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock/wakelock.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;

class CartItemScreen extends StatefulWidget {
  final String sessionId;
  final String subBranch;
  final bool isSelfService;
  final String? antrianId;

  const CartItemScreen({
    super.key,
    required this.sessionId,
    required this.subBranch,
    required this.antrianId,
    this.isSelfService = false,
  });

  @override
  State<CartItemScreen> createState() => _CartItemScreenState();
}

class GlobalState {
  static ValueNotifier<bool> isKasir = ValueNotifier<bool>(false);
  static ValueNotifier<bool> isSplitMode = ValueNotifier(false);
}

class _CartItemScreenState extends State<CartItemScreen> {
  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  List cartItems = [];
  List<TextEditingController> qtyControllers = [];
  bool isLoading = true;
  bool kurangiDariPoint = false;
  double point = 0;
  double discPoint = 0;
  double nominalPoint = 0;
  double tempDp = 0;
  double skemaMember = 0;
  bool isMember = false;
  bool isCalculating = false;
  double subtotal = 0;
  double grandtotal = 0;
  double discount = 0;
  double tax = 0;
  double tax1 = 0;
  double svc1 = 0;
  double svcharge = 0;
  double total = 0;
  double totalQty = 0;
  double gt = 0;
  double rounding = 0;
  String voucherCode = '';
  String _orderType = '';
  double splitTotal = 0;
  String? inputNote;
  String variantString = '';
  bool isSplitMode = true;
  List<Map<String, dynamic>> splitItems = [];
  Map<String, dynamic>? tempSales;

  String? role;

  final TextEditingController _voucherController = TextEditingController();
  List<Map<String, dynamic>> _vouchers = [];
  bool _isLoadingVoucher = false;
  String _barcodeBuffer = ""; // penampung input barcode
  String? userRole;

  String formatRupiah(double value) {
    final formatter =
        NumberFormat.currency(locale: 'id', symbol: 'Rp', decimalDigits: 0);
    return formatter.format(value);
  }

  bool isTaxEnabled = true;
  bool isServiceEnabled = true;

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    loadRole();
    loadData();
  }

  void loadRole() async {
    role = await getRole();
    GlobalState.isKasir.value = (role == 'kasir');

    setState(() {});
  }

  Future<void> loadData() async {
    setState(() => isLoading = true);
    _loadSavedPrinter();
    GlobalState.isSplitMode.value = false;

    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Oops, tidak ada internet"),
            ),
          );
          await Future.delayed(const Duration(seconds: 2));
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
        return;
      }

      await fetchCartItems();
      await getTax();
      await getsvCharge();

      await getPoint();
      // === HANYA PANGGIL DISCOUNT KALAU VOUCHER TIDAK KOSONG ===
      if (voucherCode.isNotEmpty) {
        await getDiscount();
      }

      _loadOrderType();
      calculateTotals();
    } catch (e) {
      debugPrint("Error loadData: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Terjadi kesalahan pastikan internet aktif, kembali ke login"),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
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

  Future<void> _loadOrderType() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _orderType = prefs.getString('orderType')?.toLowerCase() ?? 'dine in';
    });
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

  Future<String> _getDeviceId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id') ?? 'No Device available';
  }

  Future<String?> getCashier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cashier');
  }

  Future<String?> getCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('customer_name');
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role');
  }

  Future<bool?> getCrm() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('aktif_table');
  }

  Future<void> printCaptainToLANmodif(String ipAddress, String content,
      {int port = 9100}) async {
    try {
      final socket = await Socket.connect(ipAddress, port,
          timeout: const Duration(seconds: 5));

      final List<int> bytes = [];

      bytes.addAll([0x1B, 0x40]); // Init
      bytes.addAll([0x1B, 0x61, 0x00]); //Text Kiri

      // Font besar  x28
      bytes.addAll([0x1B, 0x21, 0x28]);
      //spasi 50
      bytes.addAll([0x1B, 0x33, 50]);
      // Cetak content besar
      bytes.addAll(utf8.encode(content));

      // End + Cut
      bytes.addAll([
        0x0A,
        0x0A,
        0x0A,
      ]);
      bytes.addAll([0x1D, 0x56, 0x00]);

      socket.add(Uint8List.fromList(bytes));
      await socket.flush();
      await socket.close();
    } catch (e) {
      print("Gagal cetak ke $ipAddress: $e");
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
      // bytes.addAll(utf8.encode("CAPTAIN ORDER\n"));
      bytes.addAll([0x1B, 0x61, 0x00]); // Left
      bytes.addAll([0x1B, 0x21, 0x25]);
      //spasi 50
      bytes.addAll([0x1B, 0x33, 50]);
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _printCaptainOrder(Map<String, dynamic> data) async {
    // if (!isConnected) {
    //   _showMessage("Printer belum terhubung!");
    //   return;
    // }

    await Wakelock.enable();

    try {
      final header = data['header'] ?? {};
      final details = List<Map<String, dynamic>>.from(data['detail'] ?? []);

      final formattedDateTime =
          DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.now());

      final prefs = await SharedPreferences.getInstance();

      // Ambil list printer dari local storage
      List<String> barPrinters = prefs.getStringList('printer_bar_list') ?? [];
      List<String> dapurPrinters =
          prefs.getStringList('printer_dapur_list') ?? [];
      int qtyPrint = prefs.getInt('print_captain_qty') ?? 1;

      String antrianId = (header['antrian_id'] ?? '').toString();
      String tableId = (header['table_id'] ?? '-').toString();
      String customer = (header['customer'] ?? '-').toString();
      String phone = (header['phone'] ?? '-').toString();
      String kasir = (header['kasir_name'] ?? '-').toString();

      if (phone.startsWith('0')) {
        phone = phone.replaceFirst('0', '+62');
      } else if (!phone.startsWith('+62')) {
        phone = '+62$phone';
      }

      String layoutHeader = "User : $kasir\n"
          "MEJA : $tableId\n"
          // "PHONE   : $phone\n"
          "TGL  : $formattedDateTime\n"
          "CUSTOMER: $customer\n\n";
      // Kelompokkan detail berdasarkan print_co
      Map<String, List<String>> printGroups = {};

      for (var item in details) {
        String name = (item['name'] ?? '').toString();
        int qty = item['qty'] ?? 0;
        String co = (item['print_co'] ?? '').toString().toLowerCase();

        if (!printGroups.containsKey(co)) {
          printGroups[co] = [];
        }

        printGroups[co]!.add("- $qty x $name");

        // ---------------- VARIANT (MAP) ----------------
        Map<String, dynamic> variants = {};
        if (item['variant'] != null && item['variant'] is Map) {
          variants = Map<String, dynamic>.from(item['variant']);
        }

        variants.forEach((key, v) {
          String vname = v['variant_name']?.toString() ?? '';
          if (vname.isNotEmpty) {
            printGroups[co]!.add("  * $vname");
          }
        });

        // ---------------- BUNDLE (LIST) ----------------
        List<dynamic> bundles = [];
        if (item['bundle_items'] != null && item['bundle_items'] is List) {
          bundles = List<Map<String, dynamic>>.from(item['bundle_items']);
        }

        for (var b in bundles) {
          String bname = b['name']?.toString() ?? '';
          int bqty = b['qty'] ?? 1;

          if (bname.isNotEmpty) {
            printGroups[co]!.add("  *($bqty) $bname ");
          }
        }

        // ---------------- DESCRIPTION ----------------
        String description = item['description']?.toString() ?? '';
        if (description.isNotEmpty) {
          printGroups[co]!.add("  Note: $description");
        }
      }

      // CETAK BLUETOOTH (jika aktif)
      if (prefs.getBool('print_captain') ?? false) {
        for (var entry in printGroups.entries) {
          //printer.printCustom("=== ${entry.key.toUpperCase()} ===", 2, 1);
          printer.printCustom(layoutHeader, 2, 0);

          for (var line in entry.value) {
            printer.printCustom(line, 2, 0);
          }

          printer.printCustom("----------------------", 1, 1);
          sendRawCutCommand();
        }
      }

      //lan dinamic
      for (var entry in printGroups.entries) {
        List<String> coList = entry.key.split(",");
        List<String> items = entry.value;

        for (String co in coList) {
          bool isDapur = co.startsWith("dapur");
          bool isBar = co.startsWith("bar");

          int index = int.tryParse(co.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          int realIndex = index - 1;

          String? targetPrinter;

          if (isDapur && realIndex < dapurPrinters.length) {
            targetPrinter = dapurPrinters[realIndex];
          }

          if (isBar && realIndex < barPrinters.length) {
            targetPrinter = barPrinters[realIndex];
          }

          // skip jika tidak ada printer
          if (targetPrinter == null) continue;

          // layout content
          String content =
              //"=== ${co.toUpperCase()} ===\n$layoutHeader${items.join('\n')}\n\n";
              "$layoutHeader${items.join('\n')}\n\n";

          // cetak sesuai qtyPrint
          for (int i = 0; i < qtyPrint; i++) {
            await printCaptainToLAN(targetPrinter, content);
          }
        }
      }

      _showMessage("Captain Order berhasil dicetak");
    } catch (e) {
      _showMessage("Error: $e");
    } finally {
      await Wakelock.disable();
    }
  }

  void sendRawCutCommand() {
    final List<int> cutCommand = [0x1D, 0x56, 0x42, 0x00]; // Full cut command
    final Uint8List bytes = Uint8List.fromList(cutCommand);
    BlueThermalPrinter.instance.writeBytes(bytes);
  }

  void _onKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      final key = event.logicalKey;

      // Simpan karakter biasa
      if (key.keyLabel.isNotEmpty && key.keyLabel.length == 1) {
        _barcodeBuffer += key.keyLabel;
      }

      // Enter = akhir barcode
      if (key == LogicalKeyboardKey.enter) {
        if (_barcodeBuffer.isNotEmpty) {
          _processBarcode(_barcodeBuffer.trim());
          _barcodeBuffer = ""; // reset buffer
        }
      }
    }
  }

  Future<void> _processBarcode(String barcode) async {
    try {
      final token = await getToken();
      final domain = await getDomainFromLocalStorage();
      final device = await _getDeviceId();
      final cashier = await getCashier();
      final userId = await getUser();
      final branch = await getBranchFromLocalStorage();
      final sessionId = await getSession();
      final customer = await getCustomer();

      final response = await http.post(
        Uri.parse('$domain/api/add-sku-to-cart'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "sku": barcode,
          "sub_branch": branch,
          "user": device,
          "session_pos": sessionId,
          "antrian": widget.antrianId,
          "customer": customer,
          "cashier": cashier,
          "cashierId": userId,
          "quantity": 1
        }),
      );

      if (response.statusCode == 200) {
        await fetchCartItems();
        await getTax();
        await getsvCharge();
        await getDiscount();
        calculateTotals();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Produk $barcode tidak ditemukan")),
        );
      }
    } catch (e) {
      print("Error scan barcode: $e");
    }
  }

  Future<void> fetchCartItems() async {
    final token = await getToken();
    final domain = await getDomainFromLocalStorage();
    final sessionId = await getSession();
    final kasirId = await getUser();
    final antrianId = widget.antrianId ?? '';
    final body = jsonEncode({
      'session_id': sessionId,
      'sub_branch': widget.subBranch,
      'antrian': antrianId,
      'id_kasir': kasirId
    });
    final response = await http.post(
      Uri.parse('$domain/api/cart/items'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['voucher_code'] != null && data['voucher_code'] != '') {
        _voucherController.text = data['voucher_code'];
        voucherCode = data['voucher_code'];
      } else {
        _voucherController.clear();
        voucherCode = '';
      }

      setState(() {
        final items = data is Map ? data['items'] : data;
        cartItems = List<Map<String, dynamic>>.from(items).map((item) {
          return {
            ...item,
            'price': double.tryParse(item['price'].toString()) ?? 0,
            'quantity': item['quantity'] ?? 0,
          };
        }).toList();

        qtyControllers = List.generate(cartItems.length, (index) {
          return TextEditingController(
            text: cartItems[index]['quantity'].toString(),
          );
        });

        calculateTotals();
      });
    } else {
      print('Failed to load cart items. Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');
      throw Exception('Failed to load cart items');
    }
  }

  Future<void> removeFromCart(String productId, {String variant = '{}'}) async {
    try {
      final token = await getToken();
      final domain = await getDomainFromLocalStorage();
      final sessionId = await getSession();
      final kasirId = await getUser();
      final antrianId = widget.antrianId ?? '';

      if (domain == null || domain.isEmpty) {
        throw Exception('Invalid domain');
      }

      final response = await http.post(
        Uri.parse('$domain/api/cart/remove'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'product_id': productId,
          'session_pos': sessionId,
          'sub_branch': widget.subBranch,
          'antrian': antrianId,
          'id_kasir': kasirId,
          'variant': variant,
        }),
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          cartItems.removeWhere((item) => item['product_id'] == productId);
          loadData();
          //resetData();
          //();
        });
      } else {
        throw Exception(responseData['message'] ?? 'Failed to remove item');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove item: ${e.toString()}')),
      );
      loadData();
    }
  }

  Future<void> updateQuantity(String productId, int newQty,
      {String variant = '{}'}) async {
    try {
      final token = await getToken();
      final domain = await getDomainFromLocalStorage();
      final sessionId = await getSession();
      final kasirId = await getUser();
      final antrianId = widget.antrianId ?? '';
      if (domain == null || domain.isEmpty) {
        throw Exception('Invalid domain');
      }

      final response = await http.post(
        Uri.parse('$domain/api/cart/updateCart'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'product_id': productId,
          'session_pos': sessionId,
          'sub_branch': widget.subBranch,
          'quantity': newQty,
          'antrian': antrianId,
          'id_kasir': kasirId,
          'variant': variant,
        }),
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          final itemIndex =
              cartItems.indexWhere((item) => item['product_id'] == productId);
          if (itemIndex != -1) {
            cartItems[itemIndex]['quantity'] = newQty;
          }
          loadData();
          //resetData();
          //calculateTotals();
        });
      } else {
        throw Exception(responseData['message'] ?? 'Failed to update quantity');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update quantity: ${e.toString()}')),
      );
      loadData();
    }
  }

  Future<void> getDiscount() async {
    final token = await getToken();

    final domain = await getDomainFromLocalStorage();
    final response = await http.get(
      Uri.parse(
          '$domain/api/cart/getDiscount?code=$voucherCode&sub_branch=${widget.subBranch}&sub_total=$subtotal'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        // Pastikan discount bertipe double
        discount = double.tryParse(data['discount'].toString()) ?? 0.0;
        calculateTotals();
      });
    } else {
      print('Failed to fetch discount. Status Code: ${response.statusCode}');
      throw Exception('Failed to fetch discount');
    }
  }

  Future<void> getPoint() async {
    final token = await getToken();

    final domain = await getDomainFromLocalStorage();
    final phone = await getPhone();
    final response = await http.get(
      Uri.parse(
          '$domain/api/cart/getPoint?sub_branch=${widget.subBranch}&phone=$phone'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        isMember = data['is_member'] ?? false;
        if (!isMember) {
          kurangiDariPoint = false;
        }
        // Pastikan point bertipe double
        point = double.tryParse(data['total_point'].toString()) ?? 0.0;
        skemaMember = double.tryParse(data['type_member'].toString()) ?? 0.0;
        nominalPoint = double.tryParse(data['nominal_point'].toString()) ?? 0.0;
        tempDp =
            double.tryParse(data['temp_sales']?['dp']?.toString() ?? '0') ??
                0.0;
        tempSales = data['temp_sales'] != null
            ? {
                'name': data['temp_sales']['name'] ?? '',
                'sales_id': data['temp_sales']['sales_id'] ?? '',
                'agent_id': data['temp_sales']['agent_id'] ?? '',
                'agent_pic': data['temp_sales']['agent_pic'] ?? '',
                'dp': data['temp_sales']['dp'] ?? '',
                'paytype': data['temp_sales']['payment_type'] ?? '',
              }
            : null;

        calculateTotals();
      });
    } else {
      print('Failed to fetch point. Status Code: ${response.statusCode}');
      throw Exception('Failed to fetch point');
    }
  }

  Future<void> getTax() async {
    try {
      final token = await getToken();
      final domain = await getDomainFromLocalStorage();
      final device = await _getDeviceId();
      final response = await http.get(
        Uri.parse(
            '$domain/api/cart/getTax?sub_branch=${widget.subBranch}&device=${device}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final taxValue = (data['tax'] ?? 0).toDouble(); // Konversi ke double

        if (mounted) {
          setState(() {
            tax = taxValue;
            calculateTotals();
          });
        }
      } else {
        print('Failed to fetch tax. Status Code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching tax: $e');
    }
  }

  Future<void> getsvCharge() async {
    try {
      final token = await getToken();
      final domain = await getDomainFromLocalStorage();
      final device = await _getDeviceId();
      final response = await http.get(
        Uri.parse(
            '$domain/api/cart/getServiceCharge?sub_branch=${widget.subBranch}&device=${device}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final scvalue = (data['service_charge'] ?? 0).toDouble();

        if (mounted) {
          setState(() {
            svcharge = scvalue;
            calculateTotals();
          });
        }
      } else {
        print(
            'Failed to fetch service charge. Status Code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching service charge: $e');
    }
  }

  Future<void> fetchVoucher() async {
    final token = await getToken();
    final domain = await getDomainFromLocalStorage();
    final branch = await getBranchFromLocalStorage();

    setState(() {
      _isLoadingVoucher = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$domain/api/cart/data-voucher'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "branch": branch,
        }),
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);

        setState(() {
          _vouchers = List<Map<String, dynamic>>.from(data);

          // reset diskon
          resetData();
          calculateTotals();

          _isLoadingVoucher = false;
        });
      } else {
        print('Failed to fetch voucher. Status Code: ${response.statusCode}');
        throw Exception('Failed to fetch voucher');
      }
    } catch (e) {
      print("Error fetchVoucher: $e");
      setState(() {
        _isLoadingVoucher = false;
      });
    }
  }

  Map<String, List<Map<String, dynamic>>> get voucherCategories {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var v in _vouchers) {
      final kategori = (v['category'] ?? 'lainnya').toString();
      grouped.putIfAbsent(kategori, () => []);
      grouped[kategori]!.add(v);
    }
    return grouped;
  }

  Future<void> showVoucherDialog() async {
    final selectedVoucher = await showDialog<String>(
      context: context,
      builder: (context) {
        if (_isLoadingVoucher) {
          return const AlertDialog(
            title: Text("Voucher"),
            content: SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (_vouchers.isEmpty) {
          return const AlertDialog(
            title: Text("Voucher"),
            content: Text("Tidak ada voucher tersedia"),
          );
        }

        final categories = voucherCategories;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          titlePadding: const EdgeInsets.only(top: 12, left: 16, right: 16),
          title: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Pilih Voucher Diskon",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          content: DefaultTabController(
            length: categories.keys.length,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: Theme.of(context).primaryColor,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Theme.of(context).primaryColor,
                    tabs: categories.keys.map((kategori) {
                      return Tab(
                        child: Text(
                          kategori.toUpperCase(),
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: TabBarView(
                      children: categories.keys.map((kategori) {
                        final vouchers = categories[kategori] ?? [];
                        return ListView.separated(
                          itemCount: vouchers.length,
                          separatorBuilder: (context, index) => Divider(
                            color: Colors.grey.shade300,
                          ),
                          itemBuilder: (context, index) {
                            final voucher = vouchers[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.local_offer,
                                size: 18,
                                color: Theme.of(context).primaryColor,
                              ),
                              title: Text(
                                voucher['description'] ?? '',
                                style: const TextStyle(fontSize: 12),
                              ),
                              subtitle: Text(
                                voucher['code'] ?? '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context, voucher['code']);
                              },
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedVoucher != null) {
      setState(() {
        _voucherController.text = selectedVoucher;
        voucherCode = selectedVoucher;
        getDiscount();
      });
    }
  }

  void resetData() {
    setState(() {
      discount = 0.0;
      voucherCode = '';
      _voucherController.text = '';
      kurangiDariPoint = false;
    });
  }

  void calculateTotals() {
    // reset
    subtotal = 0.0;
    total = 0.0;
    svc1 = 0.0;
    gt = 0.0;
    tax1 = 0.0;
    grandtotal = 0.0;
    rounding = 0.0;
    totalQty = 0;

    totalQty = cartItems.fold(
      0,
      (sum, item) => sum + (item['quantity'] as int),
    );

    // cek apakah ada item yang mematikan tax / svc
    bool disableTax = cartItems.any((item) => item['tax'] == 1);
    bool disableSvc = cartItems.any((item) => item['svc'] == 1);

    subtotal = cartItems.fold(
      0.0,
      (sum, item) => sum + (item['price'] * item['quantity']),
    );
    total = subtotal - discount;
    svc1 = disableSvc ? 0 : (total * (svcharge / 100));
    discPoint = point * nominalPoint;
    gt = total + svc1;
    tax1 = disableTax ? 0 : (gt * (tax / 100));
    double rawGrandTotal = gt + tax1;
    double remainder = rawGrandTotal % 100;
    grandtotal = (remainder > 0 && remainder < 100)
        ? rawGrandTotal + (100 - remainder)
        : rawGrandTotal;

    rounding = grandtotal - rawGrandTotal;
    if (kurangiDariPoint == true) {
      grandtotal -= discPoint;
    }
    //grandtotal -= tempDp;
    // if (grandtotal < 0) {
    //   grandtotal = 0;
    // }
  }

  void _showPaymentMethodDialog() {
    bool isWajibSplit = skemaMember == 1 && tempDp > 0;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Metode Pembayaran",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  )
                ],
              ),
              const SizedBox(height: 10),
              if (isWajibSplit)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "DP terdeteksi. Silakan gunakan Split Payment.",
                          style: TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 15),

              // Opsi Pembayaran
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (skemaMember == 1) ...[
                        _buildPaymentCard(
                          title: "Cash",
                          icon: Icons.attach_money,
                          color: Colors.green,
                          enabled: !isWajibSplit,
                          onTap: () {
                            Navigator.pop(context);
                            _checkCustomerAndProceed("Cash");
                          },
                        ),
                        _buildPaymentCard(
                          title: "Non-Cash",
                          icon: Icons.credit_card,
                          color: Colors.blue,
                          enabled: !isWajibSplit,
                          onTap: () {
                            Navigator.pop(context);
                            _checkCustomerAndProceed("Non-Cash");
                          },
                        ),
                      ] else ...[
                        _buildPaymentCard(
                          title: "Cash",
                          icon: Icons.attach_money,
                          color: Colors.green,
                          onTap: () {
                            Navigator.pop(context);
                            _checkCustomerAndProceed("Cash");
                          },
                        ),
                        _buildPaymentCard(
                          title: "Non-Cash",
                          icon: Icons.credit_card,
                          color: Colors.blue,
                          onTap: () {
                            Navigator.pop(context);
                            _checkCustomerAndProceed("Non-Cash");
                          },
                        ),
                      ],
                      _buildPaymentCard(
                        title: "Split Payment",
                        icon: Icons.call_split,
                        color: Colors.purple,
                        isHighlighted: isWajibSplit,
                        onTap: () {
                          Navigator.pop(context);
                          _checkCustomerAndProceed("Split-pay");
                        },
                      ),
                      _buildPaymentCard(
                        title: "Compliment",
                        icon: Icons.card_giftcard,
                        color: Colors.orange,
                        enabled: !isWajibSplit,
                        onTap: () {
                          Navigator.pop(context);
                          _checkCustomerAndProceed("Compliment");
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

// Helper widget untuk membuat card metode pembayaran
  Widget _buildPaymentCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
    bool isHighlighted = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted ? color : Colors.grey.shade200,
          width: isHighlighted ? 2 : 1,
        ),
        color: enabled ? Colors.white : Colors.grey.shade50,
      ),
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                enabled ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: enabled ? color : Colors.grey),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.black87 : Colors.grey,
          ),
        ),
        trailing: isHighlighted
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Wajib",
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              )
            : const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }

  Future<void> _checkCustomerAndProceed(String paymentMethod) async {
    _navigateToPaymentScreen(
        paymentMethod, widget.isSelfService, widget.antrianId);
  }

  void _navigateToPaymentScreen(
      String paymentMethod, bool isSelfService, String? antrianId) {
    if (kurangiDariPoint) {
      if (point <= 0 || discPoint <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Poin atau Diskon Poin tidak boleh 0 jika opsi kurangi poin dipilih")),
        );
        return;
      }
    }
    int typePayment;

    switch (paymentMethod) {
      case "Cash":
        typePayment = 1;
        break;
      case "Non-Cash":
        typePayment = 2;
        break;
      case "Compliment":
        typePayment = 300;
        break;
      case "QRIS":
        typePayment = 3;
        break;
      case "Split-pay":
        typePayment = 4;
        break;
      default:
        typePayment = 0;
    }
    final cartItemsToSend =
        List<Map<String, dynamic>>.from(cartItems).map((item) {
      return {
        'id': item['id'], // atau product_id
        'name': item[
            'name'], // Penting untuk mengisi product_name di database reward nanti
        'price': double.tryParse(item['price'].toString()) ?? 0,
        'quantity': item['quantity'] ?? 0,
      };
    }).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentScreen(
          sessionId: getSession.toString(),
          subBranch: getBranchFromLocalStorage.toString(),
          typePayment: typePayment,
          subtotal: subtotal,
          grandtotal: grandtotal,
          discount: discount,
          tax: tax1,
          svc: svc1,
          rounding: rounding,
          total: total,
          totalQty: totalQty,
          voucherCode: voucherCode,
          isSelfService: isSelfService,
          cartItems: cartItemsToSend,
          tempSales: tempSales,
          antrianId: antrianId,
          kurangiDariPoint: kurangiDariPoint,
          pointUsed: point,
          pointDiscount: discPoint,
        ),
      ),
    );
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 12),
                Text("Update...", style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    String label,
    String? value, {
    Widget? valueWidget,
    VoidCallback? onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          valueWidget ??
              Text(
                value ?? '',
                style: const TextStyle(fontSize: 13),
              ),
        ],
      ),
    );
  }

  Future<void> assignQueueIfNeeded() async {
    if (isLoading) return;
    setState(() => isLoading = true);
    print(voucherCode);
    try {
      final domain = await getDomainFromLocalStorage();
      final branch = await getBranchFromLocalStorage();
      final sessionId = await getSession();
      final phone = await getPhone();
      final userId = await getUser();
      final antrianId = widget.antrianId ?? '';
      final mgTable = await getCrm();
      final prefs = await SharedPreferences.getInstance();
      int printCaptainQty = prefs.getInt('print_captain_qty') ?? 1;

      if (mgTable != true) {
        await prefs.remove('selected_table');
        await prefs.remove('selected_area');
      }

      if (branch == null || branch.isEmpty) {
        throw Exception('Branch tidak ditemukan.');
      }

      final token = await getToken();

      final response = await http.post(
        Uri.parse('$domain/api/cart/assignQueue'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'session_pos': sessionId,
          'sub_branch': widget.subBranch,
          'note': inputNote,
          'antrian': antrianId,
          'phone': phone,
          'user': userId,
          'voucher_code': voucherCode,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final order = responseData['order'];

        for (int i = 0; i < printCaptainQty; i++) {
          await _printCaptainOrder(order);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.statusCode == 200
                  ? 'Antrian berhasil dibuat.'
                  : 'Sudah berada dalam hold transactions.',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor:
                response.statusCode == 200 ? Colors.green : Colors.orange,
          ),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        print("Gagal assign antrian: ${response.body}");
      }
    } catch (e) {
      print("Error assignQueue: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> sendSplitToBackend({required String targetTable}) async {
    try {
      final token = await getToken();
      final domain = await getDomainFromLocalStorage();

      final uri = Uri.parse('$domain/api/split-bill');

      final body = {
        "antrian_id": widget.antrianId,
        "target_table": targetTable,
        "items": splitItems.map((item) {
          return {
            "id": item['id'],
            "qty": item['quantity'],
            "price": item['price']
          };
        }).toList(),
      };

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Split Bill berhasil!")),
      );

      GlobalState.isSplitMode.value = false;
      splitItems.clear();
      splitTotal = 0;

      setState(() {
        for (var item in cartItems) {
          item['isSplit'] = false;
        }
      });

      await loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  Future<void> showSplitTargetTableDialog(BuildContext context) async {
    try {
      final token = await getToken();
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();
      final sessionId = await getSession();

      // Ambil meja kosong
      final uri = Uri.parse('$domain/api/manage-table');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sub_branch_name': branch,
          'session_id': sessionId,
        }),
      );

      if (response.statusCode != 200) throw Exception('Failed to load tables');

      final data = jsonDecode(response.body);
      final areas = Map<String, dynamic>.from(data['areas'] ?? {});
      List<Map<String, dynamic>> allEmptyTables = [];

      // 🔥 Pastikan nomor meja disimpan sebagai INT
      areas.forEach((areaName, tables) {
        for (var t in tables) {
          if (t['occupied'] == false) {
            allEmptyTables.add({
              'no': t['no'].toString(),
              'area': areaName,
            });
          }
        }
      });

      String search = '';
      String? selectedTarget;

      await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              final filtered = allEmptyTables.where((t) {
                return t['no']
                        .toString()
                        .toLowerCase()
                        .contains(search.toLowerCase()) ||
                    t['area']
                        .toString()
                        .toLowerCase()
                        .contains(search.toLowerCase());
              }).toList();

              return AlertDialog(
                title: Text(
                    "Pilih Meja Tujuan Split\n(${formatRupiah(splitTotal)})"),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 350,
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: "Cari meja...",
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (val) => setState(() => search = val),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final table = filtered[index];
                            final tableNo = table['no'].toString() ?? '';

                            final selected = selectedTarget == tableNo;

                            return Card(
                              child: ListTile(
                                title: Text("Meja $tableNo"),
                                subtitle: Text("Area: ${table['area']}"),
                                trailing: selected
                                    ? Icon(Icons.check_circle,
                                        color: Colors.teal)
                                    : null,
                                tileColor: selected
                                    ? Colors.teal.withOpacity(0.15)
                                    : null,
                                onTap: () {
                                  setState(() => selectedTarget = tableNo);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: selectedTarget == null
                            ? null
                            : () async {
                                Navigator.pop(context);
                                await sendSplitToBackend(
                                  targetTable: selectedTarget!,
                                );
                              },
                        child: const Text("Konfirmasi"),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      print("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat data meja: $e')),
      );
    }
  }

  Future<void> showNoteDialog() async {
    TextEditingController noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Masukkan Catatan'),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context); // Tutup dialog

                inputNote = noteController.text;
                await assignQueueIfNeeded(); // Jalankan assignQueueIfNeeded
              },
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white, // Warna teks putih
              ),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _showVoidModal(BuildContext context, Map item) {
    final qtyController = TextEditingController();
    final noteController = TextEditingController();
    final userController = TextEditingController();
    final passController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Text(
            "Void ${item['name'].toUpperCase()}",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Qty Void
              TextField(
                controller: qtyController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                onChanged: (value) {
                  final maxQty = item['quantity'];
                  final qty = int.tryParse(value) ?? 0;

                  if (qty > maxQty) {
                    qtyController.text = maxQty.toString();
                    qtyController.selection = TextSelection.fromPosition(
                      TextPosition(offset: qtyController.text.length),
                    );
                  }
                },
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: "Qty Void (Max ${item['quantity']})",
                  labelStyle: const TextStyle(fontSize: 14),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  border: const OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 6),

              // Keterangan
              TextField(
                controller: noteController,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: "Keterangan Void",
                  labelStyle: TextStyle(fontSize: 14),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              // Header Otoritas
              Text(
                "OTORITAS",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink.shade700,
                ),
              ),

              const SizedBox(height: 6),

              // User ID
              TextField(
                controller: userController,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: "User ID",
                  labelStyle: TextStyle(fontSize: 14),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 6),

              // Password
              TextField(
                controller: passController,
                obscureText: true,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: "Password",
                  labelStyle: TextStyle(fontSize: 14),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: const Text("Simpan"),
              onPressed: () {
                final int qtyVoid = int.tryParse(qtyController.text) ?? 0;

                if (qtyVoid <= 0 ||
                    qtyVoid > item['quantity'] ||
                    noteController.text.isEmpty ||
                    userController.text.isEmpty ||
                    passController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Data tidak valid")),
                  );
                  return;
                }

                submitVoidItemqty(
                  tempId: item['id'],
                  productId: item['product_id'],
                  antrianId: item['antrian_id'],
                  qtyTemp: item['quantity'],
                  qty: qtyVoid,
                  note: noteController.text,
                  userId: userController.text,
                  password: passController.text,
                );

                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> submitVoidItemqty({
    required int tempId,
    required String productId,
    required String antrianId,
    required int qty,
    required int qtyTemp,
    required String note,
    required String userId,
    required String password,
  }) async {
    try {
      _showLoadingDialog(context);
      final token = await getToken();
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();
      final sessionId = await getSession();
      final cashierId = await getUser();
      final uri = Uri.parse('$domain/api/cart/void-item');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sub_branch': branch,
          'session_id': sessionId,
          'temp_id': tempId,
          'product_id': productId,
          'antrian_id': antrianId,
          'qty_temp': qtyTemp,
          'qty_void': qty,
          'note': note,
          'cashier_id': cashierId,
          'user_id': userId,
          'password': password,
        }),
      );

      Navigator.pop(context); // close loading

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Item berhasil di void")),
        );
        loadData();
        // 🔄 Refresh cart / temp data
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Gagal void item')),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Timer? debounce;
    String formattedTax = tax.toInt().toString();
    String formattedSvc = svcharge.toInt().toString();

    return RawKeyboardListener(
      focusNode: FocusNode()..requestFocus(), // biar selalu aktif
      autofocus: true,
      onKey: _onKey, // handler scan barcode
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text('Keranjang'),
          actions: [
            ValueListenableBuilder<bool>(
              valueListenable: GlobalState.isKasir,
              builder: (context, isKasir, _) {
                return FutureBuilder<bool?>(
                  future: getCrm(), // ambil aktif_table dari SharedPreferences
                  builder: (context, snapshot) {
                    final bool aktifTable = snapshot.data == true;

                    final bool showSplitButton = isKasir &&
                        aktifTable &&
                        widget.antrianId != null &&
                        widget.antrianId!.isNotEmpty;

                    return Row(
                      children: [
                        if (showSplitButton)
                          IconButton(
                            icon: const Icon(Icons.rule_rounded),
                            tooltip: 'Split Bill',
                            onPressed: () {
                              final newValue = !GlobalState.isSplitMode.value;

                              GlobalState.isSplitMode.value = newValue;

                              if (!newValue) {
                                setState(() {
                                  splitItems.clear();
                                  for (var item in cartItems) {
                                    item['isSplit'] = false;
                                  }
                                  splitTotal = 0;
                                });
                              }
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.note_add_outlined),
                          tooltip: 'Tambah Catatan & Open Bill',
                          onPressed: showNoteDialog,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),

        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Tentukan breakpoint tablet, misal 600 px
                  final bool isTablet = constraints.maxWidth >= 600;

                  if (isTablet) {
                    // Tablet: Row → kiri list item, kanan detail checkout
                    return Row(
                      children: [
                        // List item kiri
                        Expanded(
                          flex: 2,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8.0),
                            itemCount: cartItems.length,
                            itemBuilder: (context, index) {
                              final item = cartItems[index];
                              final String variantsJsonString =
                                  item['variant'] ?? '{}';

                              List<String> variantItems = [];
                              try {
                                final Map<String, dynamic> variantsMap =
                                    jsonDecode(variantsJsonString);
                                variantItems = variantsMap.values
                                    .map((v) =>
                                        v['variant_name']?.toString() ?? '')
                                    .where((v) => v.isNotEmpty)
                                    .toList();
                              } catch (e) {
                                variantItems = [];
                              }

                              List<String> bundleItems = [];
                              if (item['bundle_items'] != null &&
                                  item['bundle_items'] is List) {
                                bundleItems =
                                    List<String>.from(item['bundle_items']);
                              }

                              final bool isLocked = item['print_status'] == 1;

                              return Card(
                                color: item['print_status'] == 1
                                    ? Color.fromRGBO(217, 231, 247,
                                        1) // warna berbeda jika sudah di-print
                                    : Colors.white, // warna default
                                margin: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),

                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      //Ikon Produk
                                      Icon(Icons.shopping_bag_outlined,
                                          size: 20,
                                          color:
                                              Theme.of(context).primaryColor),
                                      const SizedBox(width: 8),
                                      //Info Produk
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Nama + Print Icon
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item['name']
                                                        .toString()
                                                        .toUpperCase(),
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ),
                                                ValueListenableBuilder<bool>(
                                                  valueListenable:
                                                      GlobalState.isSplitMode,
                                                  builder: (context,
                                                      isSplitMode, _) {
                                                    if (!isSplitMode)
                                                      return SizedBox();

                                                    return Checkbox(
                                                      value: item['isSplit'] ??
                                                          false,
                                                      onChanged: (val) {
                                                        setState(() {
                                                          item['isSplit'] =
                                                              val ?? false;

                                                          final double price =
                                                              item['price']
                                                                      ?.toDouble() ??
                                                                  0;
                                                          final int qty = item[
                                                                  'quantity'] ??
                                                              1;
                                                          final double
                                                              itemTotal =
                                                              price * qty;

                                                          if (val == true) {
                                                            splitItems
                                                                .add(item);
                                                            splitTotal +=
                                                                itemTotal;
                                                          } else {
                                                            splitItems
                                                                .remove(item);
                                                            splitTotal -=
                                                                itemTotal;
                                                            if (splitTotal < 0)
                                                              splitTotal = 0;
                                                          }
                                                        });
                                                      },
                                                    );
                                                  },
                                                ),
                                                if (item['print_status'] == 1)
                                                  const Icon(Icons.print,
                                                      color: Colors.teal,
                                                      size: 16),
                                              ],
                                            ),

                                            // Di dalam Column, tampilkan seperti bundle
                                            const SizedBox(height: 2),
                                            if (variantItems.isNotEmpty)
                                              ...variantItems.map((v) => Text(
                                                    '- ${v.toUpperCase()}',
                                                    style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.black),
                                                  )),
                                            if (item['bundle_items'] != null &&
                                                (item['bundle_items'] as List)
                                                    .isNotEmpty)
                                              ...((item['bundle_items'] as List)
                                                  .map((b) => Text(
                                                        '- ${b.toString().toUpperCase()}',
                                                        style: const TextStyle(
                                                            fontSize: 9,
                                                            color:
                                                                Colors.black),
                                                      ))),
                                            if (item['description'] != null &&
                                                item['description']
                                                    .toString()
                                                    .isNotEmpty)
                                              Text(
                                                'Note: ${item['description']}',
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black),
                                              ),
                                            const SizedBox(height: 2),
                                            // Harga
                                            Text(
                                              formatRupiah(item['price']),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.black),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // 🔹 Tombol Qty & Hapus
                                      Builder(
                                        builder: (context) {
                                          final bool isLocked =
                                              item['print_status'] == 1;

                                          return Row(
                                            children: [
                                              // ➖ Kurang
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                    Icons.remove_circle_outline,
                                                    size: 18,
                                                    color: Colors.grey),
                                                onPressed: isLocked
                                                    ? null
                                                    : () {
                                                        if (item['quantity'] >
                                                            1) {
                                                          final newQty =
                                                              item['quantity'] -
                                                                  1;

                                                          // Ambil variant JSON string
                                                          final String
                                                              variantJson =
                                                              item['variant'] ??
                                                                  '{}';

                                                          updateQuantity(
                                                            item['product_id'],
                                                            newQty,
                                                            variant:
                                                                variantJson, // kirim variant
                                                          );

                                                          qtyControllers[index]
                                                                  .text =
                                                              newQty.toString();
                                                        }
                                                      },
                                              ),

                                              // 🔢 Qty
                                              SizedBox(
                                                width: 36,
                                                height: 30,
                                                child: TextField(
                                                  enabled: !isLocked,
                                                  controller:
                                                      qtyControllers[index],
                                                  keyboardType:
                                                      TextInputType.number,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isLocked
                                                        ? Colors.grey
                                                        : Colors.black,
                                                  ),
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            vertical: 6,
                                                            horizontal: 6),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                  ),
                                                  onTap: () {
                                                    if (!isLocked) {
                                                      qtyControllers[index]
                                                              .selection =
                                                          TextSelection(
                                                        baseOffset: 0,
                                                        extentOffset:
                                                            qtyControllers[
                                                                    index]
                                                                .text
                                                                .length,
                                                      );
                                                    }
                                                  },
                                                  onChanged: (value) {
                                                    if (isLocked) return;
                                                    if (debounce?.isActive ??
                                                        false)
                                                      debounce!.cancel();

                                                    int newQty =
                                                        int.tryParse(value) ??
                                                            item['quantity'];
                                                    if (newQty != null) {
                                                      // ambil variant JSON string
                                                      final String variantJson =
                                                          item['variant'] ??
                                                              '{}';

                                                      debounce = Timer(
                                                          const Duration(
                                                              milliseconds:
                                                                  900), () {
                                                        _showLoadingDialog(
                                                            context);

                                                        updateQuantity(
                                                          item['product_id'],
                                                          newQty,
                                                          variant:
                                                              variantJson, // kirim variant
                                                        ).then((_) =>
                                                            Navigator.pop(
                                                                context));
                                                      });
                                                    } else {
                                                      qtyControllers[index]
                                                              .text =
                                                          item['quantity']
                                                              .toString();
                                                    }
                                                  },
                                                ),
                                              ),

                                              // Tambah
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                    Icons.add_circle_outline,
                                                    size: 18,
                                                    color: Colors.green),
                                                onPressed: isLocked
                                                    ? null
                                                    : () {
                                                        final newQty =
                                                            item['quantity'] +
                                                                1;

                                                        // ambil variant JSON string
                                                        final String
                                                            variantJson =
                                                            item['variant'] ??
                                                                '{}';

                                                        updateQuantity(
                                                          item['product_id'],
                                                          newQty,
                                                          variant:
                                                              variantJson, // kirim variant
                                                        );

                                                        qtyControllers[index]
                                                                .text =
                                                            newQty.toString();
                                                      },
                                              ),

                                              //  Hapus
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.redAccent,
                                                    size: 20),
                                                onPressed: () {
                                                  if (item['print_status'] ==
                                                      1) {
                                                    _showVoidModal(
                                                        context, item);
                                                  } else {
                                                    // item belum print → hapus normal
                                                    removeFromCart(
                                                      item['product_id'],
                                                      variant:
                                                          item['variant'] ??
                                                              '{}',
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Detail checkout kanan
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Tombol search voucher
                                    IconButton(
                                      icon: Icon(Icons.search,
                                          color:
                                              Theme.of(context).primaryColor),
                                      onPressed: () async {
                                        await fetchVoucher(); // ambil dari API
                                        await showVoucherDialog(); // tampilkan popup
                                      },
                                    ),
                                    const SizedBox(width: 4),

                                    // TextField voucher
                                    Expanded(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: TextField(
                                          controller: _voucherController,
                                          readOnly:
                                              true, // user tidak bisa mengetik
                                          style: const TextStyle(fontSize: 13),
                                          decoration: const InputDecoration(
                                            hintText:
                                                'Voucher code klik icon cari',
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 10),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 8),

                                    // Tombol gunakan voucher
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 24,
                                      ),
                                      tooltip: 'Hapus Voucher',
                                      onPressed: () async {
                                        try {
                                          _voucherController.clear();
                                          voucherCode = "";

                                          await getDiscount(); // backend reset diskon

                                          setState(() {});
                                        } catch (e) {
                                          print(e);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (skemaMember == 1 && isMember) ...[
                                  _buildRow(
                                    context,
                                    'Poin:',
                                    null,
                                    valueWidget: Text(
                                      '${point.toInt()} pts',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  _buildRow(
                                    context,
                                    'Nominal @1 Poin:',
                                    formatRupiah(nominalPoint),
                                  ),
                                  _buildRow(
                                    context,
                                    'Disc Poin:',
                                    formatRupiah(discPoint),
                                  ),
                                  // Checkbox untuk kurangi discPoint dari total
                                  Row(
                                    children: [
                                      Checkbox(
                                        value:
                                            kurangiDariPoint, // otomatis true/false dari state
                                        onChanged: (value) {
                                          setState(() {
                                            kurangiDariPoint =
                                                value ?? false; // update state
                                            calculateTotals(); // recalc total
                                          });
                                        },
                                      ),
                                      const Text(
                                        'Gunakan poin',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const Divider(thickness: 1),
                                    ],
                                  ),
                                  const Divider(thickness: 1),
                                ],

                                _buildRow(context, 'Subtotal:',
                                    formatRupiah(subtotal)),
                                _buildRow(context, 'Diskon (-):',
                                    formatRupiah(discount)),
                                _buildRow(
                                    context, 'Total:', formatRupiah(total)),

// SERVICE
                                _buildRow(
                                  context,
                                  'Service Charge $formattedSvc% (+):',
                                  formatRupiah(isServiceEnabled ? svc1 : 0),
                                  onDelete: () {
                                    setState(() {
                                      isServiceEnabled = false;
                                      calculateTotals();
                                    });
                                  },
                                ),
                                // TAX (PB1)
                                _buildRow(
                                  context,
                                  'PB1 $formattedTax% (+):',
                                  formatRupiah(isTaxEnabled ? tax1 : 0),
                                  onDelete: () {
                                    setState(() {
                                      isTaxEnabled = false;
                                      calculateTotals();
                                    });
                                  },
                                ),

                                _buildRow(context, 'Rounding (+):',
                                    formatRupiah(rounding)),

                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Grand Total:',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      formatRupiah(grandtotal),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),

                                if (tempSales != null && skemaMember == 1) ...[
                                  const Divider(thickness: 1),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Sales ID: ${tempSales!['sales_id']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'Agent ID: ${tempSales!['agent_id']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'PIC: ${tempSales!['agent_pic']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'Customer: ${tempSales!['name']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Payment: ${tempSales!['paytype']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  _buildRow(
                                    context,
                                    'DP:',
                                    formatRupiah(double.tryParse(
                                            tempSales!['dp'].toString()) ??
                                        0),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    //  : Column → list item di atas, detail di bawah
                    return Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8.0),
                            itemCount: cartItems.length,
                            itemBuilder: (context, index) {
                              final item = cartItems[index];
                              final String variantsJsonString =
                                  item['variant'] ?? '{}';

                              List<String> variantItems = [];
                              try {
                                final Map<String, dynamic> variantsMap =
                                    jsonDecode(variantsJsonString);
                                variantItems = variantsMap.values
                                    .map((v) =>
                                        v['variant_name']?.toString() ?? '')
                                    .where((v) => v.isNotEmpty)
                                    .toList();
                              } catch (e) {
                                variantItems = [];
                              }
                              return Card(
                                color: item['print_status'] == 1
                                    ? Color.fromRGBO(217, 231, 247,
                                        1) // warna berbeda jika sudah di-print
                                    : Colors.white, // warna default
                                margin: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),

                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      //Ikon Produk
                                      Icon(Icons.shopping_bag_outlined,
                                          size: 20,
                                          color:
                                              Theme.of(context).primaryColor),
                                      const SizedBox(width: 8),

                                      // Info Produk
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Nama + Print Icon
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item['name']
                                                        .toString()
                                                        .toUpperCase(),
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ),
                                                ValueListenableBuilder<bool>(
                                                  valueListenable:
                                                      GlobalState.isSplitMode,
                                                  builder: (context,
                                                      isSplitMode, _) {
                                                    if (!isSplitMode)
                                                      return SizedBox();

                                                    return Checkbox(
                                                      value: item['isSplit'] ??
                                                          false,
                                                      onChanged: (val) {
                                                        setState(() {
                                                          item['isSplit'] =
                                                              val ?? false;

                                                          final double price =
                                                              item['price']
                                                                      ?.toDouble() ??
                                                                  0;
                                                          final int qty = item[
                                                                  'quantity'] ??
                                                              1;
                                                          final double
                                                              itemTotal =
                                                              price * qty;

                                                          if (val == true) {
                                                            splitItems
                                                                .add(item);
                                                            splitTotal +=
                                                                itemTotal; // 🟢 Tambah total
                                                          } else {
                                                            splitItems
                                                                .remove(item);
                                                            splitTotal -=
                                                                itemTotal; // 🔴 Kurangi total
                                                            if (splitTotal < 0)
                                                              splitTotal = 0;
                                                          }
                                                        });
                                                      },
                                                    );
                                                  },
                                                ),
                                                if (item['print_status'] == 1)
                                                  const Icon(Icons.print,
                                                      color: Colors.teal,
                                                      size: 16),
                                              ],
                                            ),

                                            // Di dalam Column, tampilkan seperti bundle
                                            const SizedBox(height: 2),
                                            if (variantItems.isNotEmpty)
                                              ...variantItems.map((v) => Text(
                                                    '- ${v.toUpperCase()}',
                                                    style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.black),
                                                  )),
                                            if (item['bundle_items'] != null &&
                                                (item['bundle_items'] as List)
                                                    .isNotEmpty)
                                              ...((item['bundle_items'] as List)
                                                  .map((b) => Text(
                                                        '- ${b.toString().toUpperCase()}',
                                                        style: const TextStyle(
                                                            fontSize: 9,
                                                            color:
                                                                Colors.black),
                                                      ))),
                                            if (item['description'] != null &&
                                                item['description']
                                                    .toString()
                                                    .isNotEmpty)
                                              Text(
                                                'Note: ${item['description']}',
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black),
                                              ),
                                            const SizedBox(height: 2),
                                            // Harga
                                            Text(
                                              formatRupiah(item['price']),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.black),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // 🔹 Tombol Qty & Hapus
                                      Builder(
                                        builder: (context) {
                                          final bool isLocked =
                                              item['print_status'] == 1;

                                          return Row(
                                            children: [
                                              // ➖ Kurang
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                    Icons.remove_circle_outline,
                                                    size: 18,
                                                    color: Colors.grey),
                                                onPressed: isLocked
                                                    ? null
                                                    : () {
                                                        if (item['quantity'] >
                                                            1) {
                                                          final newQty =
                                                              item['quantity'] -
                                                                  1;

                                                          // Ambil variant JSON string
                                                          final String
                                                              variantJson =
                                                              item['variant'] ??
                                                                  '{}';

                                                          updateQuantity(
                                                            item['product_id'],
                                                            newQty,
                                                            variant:
                                                                variantJson, // kirim variant
                                                          );

                                                          qtyControllers[index]
                                                                  .text =
                                                              newQty.toString();
                                                        }
                                                      },
                                              ),

                                              // 🔢 Qty
                                              SizedBox(
                                                width: 36,
                                                height: 30,
                                                child: TextField(
                                                  enabled: !isLocked,
                                                  controller:
                                                      qtyControllers[index],
                                                  keyboardType:
                                                      TextInputType.number,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isLocked
                                                        ? Colors.grey
                                                        : Colors.black,
                                                  ),
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            vertical: 6,
                                                            horizontal: 6),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                  ),
                                                  onTap: () {
                                                    if (!isLocked) {
                                                      qtyControllers[index]
                                                              .selection =
                                                          TextSelection(
                                                        baseOffset: 0,
                                                        extentOffset:
                                                            qtyControllers[
                                                                    index]
                                                                .text
                                                                .length,
                                                      );
                                                    }
                                                  },
                                                  onChanged: (value) {
                                                    if (isLocked) return;
                                                    if (debounce?.isActive ??
                                                        false)
                                                      debounce!.cancel();

                                                    int newQty =
                                                        int.tryParse(value) ??
                                                            item['quantity'];
                                                    if (newQty != null) {
                                                      // ambil variant JSON string
                                                      final String variantJson =
                                                          item['variant'] ??
                                                              '{}';

                                                      debounce = Timer(
                                                          const Duration(
                                                              milliseconds:
                                                                  900), () {
                                                        _showLoadingDialog(
                                                            context);

                                                        updateQuantity(
                                                          item['product_id'],
                                                          newQty,
                                                          variant:
                                                              variantJson, // kirim variant
                                                        ).then((_) =>
                                                            Navigator.pop(
                                                                context));
                                                      });
                                                    } else {
                                                      qtyControllers[index]
                                                              .text =
                                                          item['quantity']
                                                              .toString();
                                                    }
                                                  },
                                                ),
                                              ),

                                              // Tambah
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                    Icons.add_circle_outline,
                                                    size: 18,
                                                    color: Colors.green),
                                                onPressed: isLocked
                                                    ? null
                                                    : () {
                                                        final newQty =
                                                            item['quantity'] +
                                                                1;

                                                        // ambil variant JSON string
                                                        final String
                                                            variantJson =
                                                            item['variant'] ??
                                                                '{}';

                                                        updateQuantity(
                                                          item['product_id'],
                                                          newQty,
                                                          variant:
                                                              variantJson, // kirim variant
                                                        );

                                                        qtyControllers[index]
                                                                .text =
                                                            newQty.toString();
                                                      },
                                              ),

                                              //  Hapus
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.redAccent,
                                                    size: 20),
                                                onPressed: () {
                                                  if (item['print_status'] ==
                                                      1) {
                                                    _showVoidModal(
                                                        context, item);
                                                  } else {
                                                    // item belum print → hapus normal
                                                    removeFromCart(
                                                      item['product_id'],
                                                      variant:
                                                          item['variant'] ??
                                                              '{}',
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Detail checkout tetap di bawah
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Tombol search voucher
                                  IconButton(
                                    icon: Icon(Icons.search,
                                        color: Theme.of(context).primaryColor),
                                    onPressed: () async {
                                      await fetchVoucher(); // ambil dari API
                                      await showVoucherDialog(); // tampilkan popup
                                    },
                                  ),
                                  const SizedBox(width: 4),

                                  // TextField voucher
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: TextField(
                                        controller: _voucherController,
                                        readOnly:
                                            true, // user tidak bisa mengetik
                                        style: const TextStyle(fontSize: 13),
                                        decoration: const InputDecoration(
                                          hintText:
                                              'Voucher code klik icon cari',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 10),
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  //mobile cart info
                                  const SizedBox(width: 8),

                                  // Tombol gunakan voucher
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 24,
                                    ),
                                    tooltip: 'Hapus Voucher',
                                    onPressed: () async {
                                      try {
                                        _voucherController.clear();
                                        voucherCode = "";

                                        await getDiscount(); // backend reset diskon

                                        setState(() {});
                                      } catch (e) {
                                        print(e);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (skemaMember == 1 && isMember) ...[
                                _buildRow(
                                  context,
                                  'Poin:',
                                  null,
                                  valueWidget: Text(
                                    '${point.toInt()} pts',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                _buildRow(
                                  context,
                                  'Nominal @1 Poin:',
                                  formatRupiah(nominalPoint),
                                ),
                                _buildRow(
                                  context,
                                  'Disc Poin:',
                                  formatRupiah(discPoint),
                                ),
                                // Checkbox untuk kurangi discPoint dari total
                                Row(
                                  children: [
                                    Checkbox(
                                      value:
                                          kurangiDariPoint, // otomatis true/false dari state
                                      onChanged: (value) {
                                        setState(() {
                                          kurangiDariPoint =
                                              value ?? false; // update state
                                          calculateTotals(); // recalc total
                                        });
                                      },
                                    ),
                                    const Text(
                                      'Gunakan poin',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    const Divider(thickness: 1),
                                  ],
                                ),
                                const Divider(thickness: 1),
                              ],

                              _buildRow(
                                  context, 'Subtotal:', formatRupiah(subtotal)),
                              _buildRow(context, 'Diskon (-):',
                                  formatRupiah(discount)),
                              _buildRow(context, 'Total:', formatRupiah(total)),

// SERVICE
                              _buildRow(
                                context,
                                'Service Charge $formattedSvc% (+):',
                                formatRupiah(isServiceEnabled ? svc1 : 0),
                                onDelete: () {
                                  setState(() {
                                    isServiceEnabled = false;
                                    calculateTotals();
                                  });
                                },
                              ),

// TAX (PB1)
                              _buildRow(
                                context,
                                'PB1 $formattedTax% (+):',
                                formatRupiah(isTaxEnabled ? tax1 : 0),
                                onDelete: () {
                                  setState(() {
                                    isTaxEnabled = false;
                                    calculateTotals();
                                  });
                                },
                              ),

                              _buildRow(context, 'Rounding (+):',
                                  formatRupiah(rounding)),

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Grand Total:',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    formatRupiah(grandtotal),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              if (tempSales != null && skemaMember == 1) ...[
                                const Divider(thickness: 1),
                                const SizedBox(height: 5),
                                Text(
                                  'Sales ID: ${tempSales!['sales_id']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Agent ID: ${tempSales!['agent_id']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'PIC: ${tempSales!['agent_pic']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Customer: ${tempSales!['name']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'Payment: ${tempSales!['paytype']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                _buildRow(
                                  context,
                                  'DP:',
                                  formatRupiah(double.tryParse(
                                          tempSales!['dp'].toString()) ??
                                      0),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),

        // Tombol Pembayaran Tetap di Bawah
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ValueListenableBuilder<bool>(
            valueListenable: GlobalState.isSplitMode,
            builder: (context, isSplitMode, _) {
              if (role == null) {
                return const SizedBox(
                  height: 50,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final isKasir = GlobalState.isKasir.value;

              final buttonLabel = isSplitMode
                  ? 'Pilih Meja Tujuan (${formatRupiah(splitTotal)})'
                  : (isKasir ? 'Lanjutkan' : 'Tambah Catatan & Open Bill');

              return ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (isSplitMode) {
                          if (splitItems.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Pilih minimal 1 item untuk split bill'),
                              ),
                            );
                            return;
                          }

                          await showSplitTargetTableDialog(context);
                          return;
                        }

                        if (isKasir) {
                          // 1. Cek apakah keranjang kosong
                          if (cartItems.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Tidak ada item di keranjang.')),
                            );
                            return; // Berhenti di sini
                          }

                          // 2. Cek apakah hasil akhir (grandtotal) bernilai minus
                          // Ini penting jika DP atau Poin > Tagihan
                          if (grandtotal < 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Total tagihan minus! Periksa kembali Poin atau DP.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          // 3. Jika grandtotal 0 atau lebih, baru boleh bayar
                          else if (subtotal > 0 ||
                              (cartItems.isNotEmpty && subtotal == 0)) {
                            _showPaymentMethodDialog();
                          }
                        } else {
                          showNoteDialog();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Theme.of(context).primaryColor,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(buttonLabel),
              );
            },
          ),
        ),
      ),
    );
  }
}
