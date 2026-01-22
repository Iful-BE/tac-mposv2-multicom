import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:mposv2/screens/end_of_day_screen.dart';
import 'package:mposv2/screens/eod_summary.dart';
import 'package:mposv2/screens/login_screen.dart';
import 'package:mposv2/screens/member.dart';
import 'package:mposv2/screens/CartItemScreen.dart';
import 'package:mposv2/screens/order_online.dart';
import 'package:mposv2/screens/payment_screen.dart';
import 'package:mposv2/screens/redeem_catering.dart';
import 'package:mposv2/screens/sold_screen.dart';
import 'package:mposv2/screens/transaction_queue.dart';
import 'package:mposv2/screens/transaction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mposv2/screens/sales_screen.dart';
import 'package:mposv2/screens/printer_settings_screen.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_custom_clippers/flutter_custom_clippers.dart';
import 'package:wakelock/wakelock.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import 'package:flutter/services.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class GlobalState {
  static ValueNotifier<bool> isKasir = ValueNotifier<bool>(false);
  static ValueNotifier<bool> isSplitMode = ValueNotifier(false);
}

class _HomeScreenState extends State<HomeScreen> {
  String? userId;
  String? deviceId;
  String? cashier;
  String? sessionId;
  String totalCash = "Rp 0";
  String totalNonCash = "Rp 0";
  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  bool isLoading = false;
  String? phoneError;
  String _latestVersion = "1.0.0"; // default
  String? role;
  final TextEditingController phoneController = TextEditingController();
  bool isRegisterMember = false;

  bool _isPhoneValid() {
    return phoneController.text.length >= 9;
  }

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    loadRole();
    _loadSavedPrinter();
    _loadUserData();
    _loadLatestVersion();
  }

  void loadRole() async {
    role = await getRole();
    bool isKasir = (role == 'kasir');
    GlobalState.isKasir.value = isKasir;

    // Hanya fetch revenue jika role adalah kasir
    if (isKasir) {
      _fetchRevenue();
    }

    if (mounted) {
      setState(() {});
    }
  }

  // Fungsi untuk mengambil data dari SharedPreferences
  void _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      userId = prefs.getString('user_id');
      cashier = prefs.getString('cashier');
      deviceId = prefs.getString('device_id');
      sessionId = prefs.getString('session_id');
    });
  }

  Future<void> _loadLatestVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString('latest_version') ?? "1.0.0";
    if (mounted) {
      setState(() {
        _latestVersion = version;
      });
    }
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role');
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<bool?> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('mode'); // true = resto, false = retail
  }

  Future<bool?> getCrm() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('aktif_table'); // true = resto, false = retail
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

  Future<String?> getDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id');
  }

  Future<String?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  Future<String?> getCashier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cashier');
  }

  String formatRupiah(double amount) {
    final format =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return format.format(amount);
  }

  //

//status whatsapp
  Future<bool> checkWhatsappStatus() async {
    final token = await getToken();

    try {
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();

      final uri = Uri.parse('$domain/api/catering-check-whatsapp');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sub_branch_name': branch}),
      );

      final data = jsonDecode(response.body);
      bool isConnected = data['connected'] == true;
      return isConnected;
    } catch (e) {
      return false;
    }
  }

// Fetch revenue from API
  Future<void> _fetchRevenue() async {
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

      final uri = Uri.parse('$domain/api/revenue');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sub_branch': branch, 'session_id': sessionId}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['data'] != null) {
          // Handling null or invalid values gracefully
          setState(() {
            totalCash = formatRupiah(_parseToDouble(data['data']['totalCash']));
            totalNonCash =
                formatRupiah(_parseToDouble(data['data']['totalNoncash']));
          });
        } else {
          print("Data tidak ditemukan");
        }
      } else {
        print("Failed to load revenue: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching revenue: $e");
    }
  }

  Future<bool> _changeTable(String fromTable, String targetTable) async {
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

      final uri = Uri.parse('$domain/api/change-table');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'idTable': fromTable,
          'targetTable': targetTable,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print("Failed to change table: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("Error change table: $e");
      return false;
    }
  }

  Future<bool> _mergeTable(String fromTable, String targetTable) async {
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

      final uri = Uri.parse('$domain/api/merge-table');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'idTable': fromTable,
          'targetTable': targetTable,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print("Failed to change table: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("Error change table: $e");
      return false;
    }
  }

  Future<bool> guestCount(String idTable, int count) async {
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

      final uri = Uri.parse('$domain/api/change-guest');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'idTable': idTable,
          'count': count,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print("Failed to change guest: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("Error change guest: $e");
      return false;
    }
  }

  Future<bool> customerChange(String idTable, String custEdit) async {
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

      final uri = Uri.parse('$domain/api/change-customer');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'idTable': idTable,
          'customer': custEdit,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print("Failed to change customer: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("Error change customer: $e");
      return false;
    }
  }

  Future<void> _loadSavedPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString('printer_address');

      if (address != null) {
        try {
          final devices = await printer.getBondedDevices();
          selectedDevice =
              devices.firstWhereOrNull((d) => d.address == address);

          if (selectedDevice != null) {
            final bool? alreadyConnected = await printer.isConnected;
            if (alreadyConnected == true) {
              if (mounted) setState(() => isConnected = true);
            } else {
              await _connectToPrinter();
            }
          } else {
            await _clearSavedPrinter();
            _showMessage("Printer tersimpan tidak ditemukan.");
          }
        } catch (e) {
          _showError("Gagal mendapatkan daftar perangkat: $e");
        }
      } else {
        _showMessage("Alamat printer belum disimpan.");
      }
    } catch (e) {
      _showError("Error memuat printer: $e");
    }
  }

  Future<void> _connectToPrinter() async {
    if (selectedDevice != null) {
      try {
        final bool? alreadyConnected = await printer.isConnected;
        if (alreadyConnected == true) {
          await printer.disconnect(); // Pastikan tidak ada koneksi lama
        }

        await printer.connect(selectedDevice!);
        setState(() => isConnected = true);
        _showMessage("Terhubung ke ${selectedDevice!.name}");
      } catch (e) {
        setState(() => isConnected = false);
        _showError("Gagal terhubung ke printer: $e");
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

// Helper function to safely parse values to double
  double _parseToDouble(dynamic value) {
    if (value == null) {
      return 0.0; // Default value if null
    }
    try {
      return double.parse(value.toString());
    } catch (e) {
      print("Error parsing value: $e");
      return 0.0; // Return a default value if parsing fails
    }
  }

//updateenddate
  Future<void> _updateEndDate() async {
    final token = await getToken();

    try {
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();
      final sessionId = await getSession();
      final device = await getDevice();

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
        body: jsonEncode(
            {'sub_branch': branch, 'session_id': sessionId, 'device': device}),
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          if (data != null && data is Map<String, dynamic>) {
            _printReceipt(data);

            Future.delayed(const Duration(seconds: 0), () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const EndOfDayScreen()),
                (route) => false,
              );
            });
            //print(data);
          } else if (response.statusCode == 404) {
            _showError(" Masih ada product di keranjang.");
          } else {
            _showError("Response data tidak valid.");
          }
        } catch (e) {
          _showError("Gagal memproses respons: $e");
        }
      } else {
        _showError(
            "Gagal menutup sesi: ${response.statusCode} | Pastikan tidak ada product di keranjang dan on hold trx ya!");
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
      printer.printCustom("Grand Total : ${formatRupiah(grandTotal)}", 1, 0);
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

      sendRawCutCommand();
    } else {
      _showError("Printer belum terhubung!");
    }
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

  //EndOfDay
  void _handleLogout() async {
    await _updateEndDate();
  }

  //popup confirm
  Future<bool?> _showEndOfDayDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("End of Day"),
          content: const Text("Yakin menutup sesi hari ini?"),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // User canceled
              },
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // User confirmed
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<Map<String, dynamic>> checkIsMember(String phone) async {
    final token = await getToken();

    try {
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();

      if (branch == null || branch.isEmpty) throw Exception('Branch not found');
      if (domain == null || domain.isEmpty) throw Exception('Domain not found');

      final uri = Uri.parse('$domain/api/index-members');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'phone': phone}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        //print("API Response: $data");
        if (data['data'] != null && data['data']['name'] != null) {
          return {
            'status': true,
            'name': data['data']['name'],
            'trx': data['data']['trx'] ?? 0,
            'total_point': (data['data']['total_point'] == 10)
                ? 0
                : (data['data']['total_point'] ?? 0),
            // Tangkap data tambahan
            'last_redeem': data['last_redeem_date'] ?? '-',
            'redeem_loc': data['last_redeem_loc'] ?? '-',
            'rewards_count': data['rewards_count'] ?? 0,
          };
        }
      }
    } catch (e) {
      print("checkIsMember error: $e");
    }

    return {'status': false};
  }

  Future<int?> showGuestCountDialog(
      BuildContext context, String tableNo) async {
    TextEditingController countCtrl = TextEditingController();

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text("Ubah Guest Count (Meja $tableNo)"),
          content: TextField(
            controller: countCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Jumlah Tamu",
              border: OutlineInputBorder(),
            ),
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
              onPressed: () {
                final int? count = int.tryParse(countCtrl.text);
                if (count != null) {
                  Navigator.pop(context, count);
                }
              },
              child: const Text("Update"),
            )
          ],
        );
      },
    );
  }

  Future<String?> showCustomerEditDialog(
    BuildContext context,
    String tableNo,
  ) async {
    final TextEditingController controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Ubah Nama Customer (Meja $tableNo)"),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: "Nama Customer",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () {
                final custEdit = controller.text.trim();
                if (custEdit.isEmpty) return;
                Navigator.pop(context, custEdit);
              },
              child: const Text('update'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, String>?> showGuestPhoneModal(BuildContext context) async {
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController guestController = TextEditingController();

    String? guestError;
    String? phoneError;
    final modeBool = await getMode() ?? false;

    String orderType =
        modeBool ? "DINE IN" : "RETAIL"; // default: false = retail

    return await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🔹 Tombol Order Type , "CATERING"
                if (modeBool) ...[
                  SizedBox(
                    width: double.infinity,
                    child: Row(
                      children: [
                        for (final type in ["DINE IN", "TAKE AWAY", "CATERING"])
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  orderType = type;
                                  phoneError =
                                      null; // reset error kalau ganti tipe
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: orderType == type
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey[800],
                                  borderRadius: BorderRadius.horizontal(
                                    left: type == "DINE IN"
                                        ? const Radius.circular(4)
                                        : Radius.zero,
                                    right: type == "CATERING"
                                        ? const Radius.circular(4)
                                        : Radius.zero,
                                  ),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                child: Text(
                                  type,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: guestController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    // 1. Membatasi input maksimal 3 karakter
                    maxLength: 3,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: "Jumlah Tamu",
                      errorText: guestError,
                      // 2. Menyembunyikan label penghitung (0/3) di bawah field
                      counterText: "",
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                // 🔹 Nomor WhatsApp (Wajib hanya jika Catering)
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(13),
                  ],
                  decoration: InputDecoration(
                    labelText: "No Whatsapp",
                    errorText: phoneError,
                    prefixText: "+62 ",
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text(
                  "Batal",
                  style: TextStyle(fontSize: 16, color: Colors.red),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final guest = guestController.text.trim();
                  final phone = phoneController.text.trim();
                  bool hasError = false;

                  if (guest.isEmpty && modeBool) {
                    guestError = "Jumlah tamu tidak boleh kosong";
                    hasError = true;
                  } else {
                    guestError = null;
                  }

                  if (orderType == "CATERING" && phone.isEmpty) {
                    phoneError = "Nomor WhatsApp wajib untuk catering";
                    hasError = true;
                  } else if (phone.length < 10 && phone.isNotEmpty) {
                    phoneError = "Nomor WhatsApp minimal 10 digit";
                    hasError = true;
                  } else {
                    phoneError = null;
                  }

                  setState(() {});

                  if (hasError) return;
                  if (orderType == "CATERING") {
                    bool isConnected = await checkWhatsappStatus();

                    if (!isConnected) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              "WhatsApp belum terhubung. Silahkan hubungkan dulu."),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return; // stop tidak lanjut
                    }
                  }
                  Navigator.pop(context, {
                    "guest": guest,
                    "phone": phone,
                    "orderType": orderType,
                  });
                },
                icon: const Icon(Icons.arrow_forward, size: 20),
                label: const Text("Lanjutkan", style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void handlePhoneInput() async {
    final prefs = await SharedPreferences.getInstance();
    final modeBool = await getMode() ?? false; // default: false = retail
    final manageTable = await getCrm() ?? false;

    if (modeBool) {
      // === RESTO ===
      final resultModal = await showGuestPhoneModal(context);
      if (resultModal == null) return;

      final phone = resultModal['phone'] ?? '';
      final guest = resultModal['guest'] ?? '0';
      final orderType = resultModal['orderType'] ?? 'DINE IN';

      await prefs.setString('user_phone', phone);
      await prefs.setString('total_guest', guest);
      await prefs.setString('orderType', orderType);

      if (orderType.toUpperCase() == 'DINE IN' && manageTable) {
        final tableResult = await showManageTableDialog(context);
        if (tableResult == null) return;

        await prefs.setString('selected_area', tableResult['area'] ?? '');
        await prefs.setString('selected_table', tableResult['table'] ?? '');
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('selected_table');
        await prefs.remove('selected_area');
      }

      final result = await checkIsMember(phone);
      if (!mounted) return;

      if (result['status'] == true) {
        final name = result['name'] ?? '';
        await prefs.setString('customer_name', name);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MemberScreen(
              name: name,
              trx: result['trx'],
              point: result['total_point'],
              lastRedeem: result['last_redeem'],
              redeemLoc: result['redeem_loc'],
              rewardsCount: result['rewards_count'],
            ),
          ),
        );
      } else {
        final inputName = await showNameModal(context);
        if (!mounted) return;

        await prefs.setString('customer_name', inputName ?? '');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const SalesScreen(isSelfService: true),
          ),
        );
      }
    } else {
      final resultModal = await showGuestPhoneModal(context);
      if (resultModal == null) return;
      final phone = resultModal['phone'] ?? '';
      await prefs.setString('user_phone', phone);
      final result = await checkIsMember(phone);
      if (!mounted) return;

      if (result['status'] == true) {
        final name = result['name'] ?? '';
        await prefs.setString('customer_name', name);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MemberScreen(
              name: name,
              trx: result['trx'],
              point: result['total_point'],
              lastRedeem: result['last_redeem'], // Data dari API
              redeemLoc: result['redeem_loc'], // Data dari API
              rewardsCount: result['rewards_count'],
            ),
          ),
        );
      } else {
        final inputName = await showNameModal(context);
        if (!mounted) return;

        await prefs.setString('customer_name', inputName ?? '');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const SalesScreen(isSelfService: true),
          ),
        );
      }
    }
    //else {
    //   // === RETAIL ===
    //   await prefs.setString('customer_name', 'UMUM');
    //   await prefs.setString('total_guest', '1');
    //   await prefs.setString('orderType', 'RETAIL');

    //   final sessionId = await getDevice() ?? "";
    //   final subBranch = await getBranchFromLocalStorage() ?? "";

    //   Navigator.pushReplacement(
    //     context,
    //     MaterialPageRoute(
    //       builder: (_) => CartItemScreen(
    //         sessionId: sessionId,
    //         subBranch: subBranch,
    //         antrianId: null,
    //         isSelfService: false,
    //       ),
    //     ),
    //   );
    // }
  }

  Future<String?> showNameModal(BuildContext context) async {
    final modeCrm = await getCrm() ?? true;
    final nameController = TextEditingController();

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Masukan Nama Customer"),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Nama Customer",
            hintText: "Boleh dikosongkan, minimal 3 karakter jika diisi",
          ),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty && name.length < 3) {
              // tampilkan pesan error
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Nama minimal 3 karakter atau kosongkan."),
                  backgroundColor: Colors.red,
                ),
              );
            } else {
              Navigator.pop(context, name);
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 8),
            child: ElevatedButton.icon(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty && name.length < 3) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Nama minimal 3 karakter atau kosongkan."),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else {
                  Navigator.pop(context, name);
                }
              },
              icon: const Icon(Icons.arrow_forward),
              label: const Text("Lanjutkan"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String getDuration(dynamic createdAt) {
    if (createdAt == null || createdAt.toString().isEmpty) return "-";

    try {
      final date = DateTime.parse(createdAt.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      final hours = diff.inHours;
      final mins = diff.inMinutes.remainder(60);

      if (hours == 0) return "${mins}m";
      if (mins == 0) return "${hours}j";
      return "${hours}j ${mins}m";
    } catch (e) {
      return "-";
    }
  }

  Future<Map<String, String>?> showManageTableDialog(
      BuildContext context) async {
    final token = await getToken();
    final branch = await getBranchFromLocalStorage();
    final domain = await getDomainFromLocalStorage();
    final sessionId = await getSession();

    if (branch == null || branch.isEmpty) {
      throw Exception('Branch not found in local storage');
    }
    if (domain == null || domain.isEmpty) {
      throw Exception('Domain not found in local storage');
    }

    // 🔹 Fetch data dari API
    final uri = Uri.parse('$domain/api/manage-table');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'sub_branch_name': branch, 'session_id': sessionId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load tables');
    }

    final data = jsonDecode(response.body);
    if (data['connected'] != true) {
      throw Exception('Server not connected');
    }

    final Map<String, dynamic> areasData =
        Map<String, dynamic>.from(data['areas'] ?? {});
    if (areasData.isEmpty) throw Exception('No table data found');

    final List<String> areas = areasData.keys.toList();
    final Map<String, List<Map<String, dynamic>>> tables = {};

    // 🔹 Format data
    for (var area in areas) {
      tables[area] = List<Map<String, dynamic>>.from(
        areasData[area].map((t) => {
              'no': t['no'] ?? '',
              'occupied': t['occupied'] ?? false,
              'guestCount': t['guest_count'] ?? 0,
              'phone': t['phone'] ?? '',
              'name': t['name'] ?? '',
              'created_at': t['created_at'] ?? '',
              'transactions':
                  List<Map<String, dynamic>>.from(t['transactions'] ?? []),
            }),
      );
    }

    String selectedArea = areas.first;
    String? selectedTable;

    Future<void> refreshTables() async {
      final token = await getToken();
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();
      final sessionId = await getSession();

      if (branch == null || branch.isEmpty) {
        throw Exception('Branch not found in local storage');
      }
      if (domain == null || domain.isEmpty) {
        throw Exception('Domain not found in local storage');
      }

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

      if (response.statusCode != 200) {
        throw Exception('Failed to load tables');
      }

      final data = jsonDecode(response.body);

      if (data['connected'] != true) {
        throw Exception('Server not connected');
      }

      final Map<String, dynamic> areasData =
          Map<String, dynamic>.from(data['areas'] ?? {});
      if (areasData.isEmpty) throw Exception('No table data found');

      final Map<String, List<Map<String, dynamic>>> updatedTables = {};

      // 🔹 Format data agar konsisten dengan fetch awal
      areasData.forEach((area, tablesList) {
        updatedTables[area] = List<Map<String, dynamic>>.from(
          (tablesList as List).map((t) => {
                'no': t['no'] ?? '',
                'occupied': t['occupied'] ?? false,
                'guestCount': t['guest_count'] ?? 0,
                'phone': t['phone'] ?? '',
                'name': t['name'] ?? '',
                'created_at': t['created_at'] ?? '',
                'transactions':
                    List<Map<String, dynamic>>.from(t['transactions'] ?? []),
              }),
        );
      });

      setState(() {
        tables.clear();
        tables.addAll(updatedTables);

        // Reset selectedTable jika meja sebelumnya sudah dipindahkan
        final areaTables = tables[selectedArea] ?? [];
        if (!areaTables.any((t) => t['no'] == selectedTable)) {
          selectedTable = null;
        }
      });
    }

    await refreshTables();

    // 🔹 Dialog transaksi
    void showTransactionDialog(
        BuildContext context, Map<String, dynamic> table) {
      final transactions = table['transactions'] as List<Map<String, dynamic>>;
      final served =
          transactions.where((t) => t['status'] == 'served').toList();
      final cooking =
          transactions.where((t) => t['status'] == 'cooking').toList();

      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Transaksi Meja ${table['no']}',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal)),
                const SizedBox(height: 16),
                if (served.isNotEmpty) ...[
                  const Text('Menu Sudah Sampai:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green)),
                  ...served.map((item) => ListTile(
                        leading:
                            const Icon(Icons.check_circle, color: Colors.green),
                        title: Text(item['item']),
                        subtitle: Text('Jumlah: ${item['quantity']}'),
                      )),
                  const SizedBox(height: 16),
                ],
                if (cooking.isNotEmpty) ...[
                  const Text('Menu Masih Dimasak:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.orange)),
                  ...cooking.map((item) => ListTile(
                        leading: const Icon(Icons.hourglass_top,
                            color: Colors.orange),
                        title: Text(item['item']),
                        subtitle: Text('Jumlah: ${item['quantity']}'),
                      )),
                ],
                if (served.isEmpty && cooking.isEmpty)
                  const Text('Tidak ada transaksi.'),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 🔹 Dialog pindah meja (REAL dari API)
    Future<String?> showMoveTableDialog(
        BuildContext context, Map<String, dynamic> fromTable) async {
      List<Map<String, dynamic>> allEmptyTables = [];

      // Ambil semua meja kosong dari global tables
      tables.forEach((areaName, areaTables) {
        final emptyTables = areaTables
            .where((t) => t['occupied'] == false)
            .map((t) => {...t, 'area': areaName})
            .toList();
        allEmptyTables.addAll(emptyTables);
      });

      List<Map<String, dynamic>> filteredTables = List.from(allEmptyTables);
      TextEditingController searchController = TextEditingController();
      String? targetTable;
      bool showSuccess = false;
      bool isLoading = false;

      return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Pindah dari Meja ${fromTable['no']} ke...',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: Column(
                  children: [
                    if (showSuccess)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Meja ${fromTable['no']} berhasil dipindah ke $targetTable",
                                style: const TextStyle(color: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: "Cari meja atau area...",
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        final keyword = value.toLowerCase();
                        setState(() {
                          filteredTables = allEmptyTables.where((t) {
                            final no = t['no'].toString().toLowerCase();
                            final area = t['area'].toString().toLowerCase();
                            return no.contains(keyword) ||
                                area.contains(keyword);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredTables.length,
                        itemBuilder: (context, index) {
                          final table = filteredTables[index];
                          final isSelected = targetTable == table['no'];
                          return Card(
                            child: ListTile(
                              tileColor: isSelected
                                  ? Colors.teal.withOpacity(0.15)
                                  : null,
                              title: Text("Meja ${table['no']}"),
                              subtitle: Text("Area: ${table['area']}"),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.teal)
                                  : null,
                              onTap: () {
                                setState(() => targetTable = table['no']);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: targetTable == null || isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          final success = await _changeTable(
                              fromTable['no'].toString(), targetTable!);

                          if (success) {
                            setState(() {
                              showSuccess = true;
                              isLoading = false;
                            });
                            await Future.delayed(const Duration(seconds: 1));
                            Navigator.pop(context, targetTable);
                          } else {
                            setState(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Gagal memindahkan meja!")),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white, // Warna teks putih
                  ),
                  child: const Text('Pindahkan'),
                ),
              ],
            );
          },
        ),
      );
    }

    Future<String?> showMergeTableDialog(
        BuildContext context, Map<String, dynamic> fromTable) async {
      List<Map<String, dynamic>> allEmptyTables = [];

      // Ambil semua meja yang aktif dari global tables jangan tampilkan meja yang dipilih
      tables.forEach((areaName, areaTables) {
        final emptyTables = areaTables
            .where((t) =>
                    t['occupied'] == true &&
                    t['no'] != fromTable['no'] // ⬅ exclude meja yg dipilih
                )
            .map((t) => {...t, 'area': areaName})
            .toList();

        allEmptyTables.addAll(emptyTables);
      });

      List<Map<String, dynamic>> filteredTables = List.from(allEmptyTables);
      TextEditingController searchController = TextEditingController();
      String? targetTable;
      bool showSuccess = false;
      bool isLoading = false;

      return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Gabung Meja ${fromTable['no']} ke...',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: Column(
                  children: [
                    if (showSuccess)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Meja ${fromTable['no']} berhasil menggabungkan ke $targetTable",
                                style: const TextStyle(color: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: "Cari meja atau area...",
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        final keyword = value.toLowerCase();
                        setState(() {
                          filteredTables = allEmptyTables.where((t) {
                            final no = t['no'].toString().toLowerCase();
                            final area = t['area'].toString().toLowerCase();
                            return no.contains(keyword) ||
                                area.contains(keyword);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredTables.length,
                        itemBuilder: (context, index) {
                          final table = filteredTables[index];
                          final isSelected = targetTable == table['no'];
                          return Card(
                            child: ListTile(
                              tileColor: isSelected
                                  ? Colors.teal.withOpacity(0.15)
                                  : null,
                              title: Text("Meja ${table['no']}"),
                              subtitle: Text("Area: ${table['area']}"),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.teal)
                                  : null,
                              onTap: () {
                                setState(() => targetTable = table['no']);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: targetTable == null || isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          final success = await _mergeTable(
                              fromTable['no'].toString(), targetTable!);

                          if (success) {
                            setState(() {
                              showSuccess = true;
                              isLoading = false;
                            });
                            await Future.delayed(const Duration(seconds: 1));
                            Navigator.pop(context, targetTable);
                          } else {
                            setState(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Gagal menggabungkan meja!")),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white, // Warna teks putih
                  ),
                  child: const Text('Gabungkan'),
                ),
              ],
            );
          },
        ),
      );
    }

    // 🔹 Dialog opsi meja
    void showTableOptionsDialog(
        BuildContext context, Map<String, dynamic> table) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Opsi untuk Meja ${table['no']}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.teal)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ElevatedButton.icon(
              //   style: ElevatedButton.styleFrom(
              //     backgroundColor: Colors.orange,
              //     foregroundColor: Colors.white,
              //   ),
              //   icon: const Icon(Icons.swap_horiz),
              //   label: const Text('To Cart'),
              //   onPressed: () {
              //     Navigator.pop(context); // Tutup dialog opsi meja
              //     Navigator.push(
              //       context,
              //       MaterialPageRoute(
              //         builder: (context) => CartScreen(
              //           table: table, // Kirim data meja ke CartScreen
              //         ),
              //       ),
              //     );
              //   },
              // ),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.pending_actions),
                label: const Text('Hold Transaksi'),
                onPressed: () {
                  Navigator.pop(context); // Tutup dialog dulu
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TransactionQue(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.receipt),
                label: const Text('Lihat Transaksi'),
                onPressed: () {
                  Navigator.pop(context);
                  showTransactionDialog(context, table);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
          ],
        ),
      );
    }

    // 🔹 Tampilkan dialog utama
    return await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          final areaTables = tables[selectedArea] ?? [];
          return Dialog(
            insetPadding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            child: SafeArea(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.teal, Colors.tealAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Manage Table',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              Navigator.of(context, rootNavigator: true)
                                  .popUntil((route) => route.isFirst);
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    //buton area
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: areas.map((area) {
                          final isSelected = area == selectedArea;
                          final areaTables = tables[area] ?? [];
                          final occupied =
                              areaTables.where((t) => t['occupied']).length;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Stack(
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isSelected
                                        ? Colors.teal
                                        : Colors.grey.shade300,
                                    foregroundColor: isSelected
                                        ? Colors.white
                                        : Colors.black,
                                    elevation:
                                        4, // Tambahkan elevation untuk efek elegan
                                    shadowColor: Colors.black26,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          12), // Lebih rounded untuk elegan
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      selectedArea = area;
                                      selectedTable = null;
                                    });
                                  },
                                  child: Text(area),
                                ),
                                if (occupied > 0)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors
                                            .red, // Warna orange seperti diminta
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black12,
                                            blurRadius: 4,
                                            offset: Offset(0, 2),
                                          ),
                                        ], // Shadow untuk efek elegan
                                      ),
                                      child: Text(
                                        '$occupied',
                                        style: const TextStyle(
                                          color: Colors.white, // Text putih
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 10),
                    //breadcump info
                    Builder(builder: (_) {
                      final areaTables = tables[selectedArea] ?? [];
                      final total = areaTables.length;
                      final occupied =
                          areaTables.where((t) => t['occupied']).length;
                      final empty = total - occupied;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.teal.shade100,
                                Colors.teal.shade200
                              ], // Gradient soft untuk elegan
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(
                                16), // Lebih rounded untuk kesan modern
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ], // Shadow halus untuk depth
                            border: Border.all(
                              color: Colors.teal.shade300,
                              width: 1,
                            ), // Border tipis untuk aksen
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.dashboard,
                                color: Colors.teal.shade700,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontFamily:
                                          'Roboto', // Atau gunakan font custom jika ada
                                    ),
                                    children: [
                                      TextSpan(
                                        text: "Area: ",
                                        style: TextStyle(
                                            color: Colors.teal
                                                .shade800), // Warna teal gelap
                                      ),
                                      TextSpan(
                                        text: "$selectedArea • ",
                                        style: TextStyle(
                                            color: Colors.purple
                                                .shade600), // Warna ungu untuk nama area
                                      ),
                                      TextSpan(
                                        text: "Total: ",
                                        style: TextStyle(
                                            color: Colors
                                                .blue.shade700), // Warna biru
                                      ),
                                      TextSpan(
                                        text: "$total | ",
                                        style: TextStyle(
                                            color: Colors.blue
                                                .shade500), // Biru lebih terang
                                      ),
                                      TextSpan(
                                        text: "Terpakai: ",
                                        style: TextStyle(
                                            color: Colors.red
                                                .shade700), // Warna orange untuk terpakai
                                      ),
                                      TextSpan(
                                        text: "$occupied | ",
                                        style: TextStyle(
                                            color: Colors.red
                                                .shade500), // Orange lebih terang
                                      ),
                                      TextSpan(
                                        text: "Kosong: ",
                                        style: TextStyle(
                                            color: Colors.green
                                                .shade700), // Warna hijau untuk kosong
                                      ),
                                      TextSpan(
                                        text: "$empty",
                                        style: TextStyle(
                                            color: Colors.green
                                                .shade500), // Hijau lebih terang
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 12),
                    //grid meja list kosong isi
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            List<Map<String, dynamic>> areaTables =
                                tables[selectedArea] ?? [];
                            int crossAxisCount = constraints.maxWidth < 600
                                ? 2
                                : constraints.maxWidth < 1200
                                    ? 4
                                    : 6;

                            return GridView.builder(
                              itemCount: areaTables.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio:
                                    1, // agar tinggi dan lebar proporsional
                              ),
                              itemBuilder: (context, index) {
                                final table = areaTables[index];
                                final isOccupied = table['occupied'] ?? false;
                                final isSelected = selectedTable == table['no'];

                                Color bgColor = isOccupied
                                    ? Colors.redAccent
                                    : isSelected
                                        ? Colors.teal
                                        : Colors.grey.shade100;

                                return GestureDetector(
                                  onTap: () {
                                    if (isOccupied) {
                                      showTableOptionsDialog(context, table);
                                    } else {
                                      setState(() {
                                        selectedTable = table['no'];
                                      });
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.black12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      children: [
                                        // Konten meja dengan scroll jika overflow
                                        Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: isOccupied
                                              ? SingleChildScrollView(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Center(
                                                        child: Text(
                                                          table['no'] ??
                                                              'Unknown',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 24,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      buildInfoRow(
                                                          Icons.people,
                                                          'Guest',
                                                          table['guestCount'] ??
                                                              0),
                                                      buildInfoRow(
                                                          Icons.person,
                                                          'Name',
                                                          table['name'] ??
                                                              'N/A'),
                                                      buildInfoRow(
                                                          Icons
                                                              .smartphone_outlined,
                                                          'Phone',
                                                          table['phone'] ??
                                                              'N/A'),
                                                      buildInfoRow(
                                                          Icons.access_time,
                                                          'Waktu',
                                                          table['created_at'] !=
                                                                  null
                                                              ? getDuration(table[
                                                                  'created_at'])
                                                              : '-'),
                                                    ],
                                                  ),
                                                )
                                              : Center(
                                                  child: Text(
                                                    table['no'] ?? 'Unknown',
                                                    style: TextStyle(
                                                      fontSize: 24,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isSelected
                                                          ? Colors.white
                                                          : Colors.black,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                        // Icon pindah meja di pojok kanan atas jika terisi
                                        if (isOccupied) ...[
                                          // --- Tombol Change Table ---
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: GestureDetector(
                                              onTap: () async {
                                                final movedTable =
                                                    await showMoveTableDialog(
                                                        context, table);
                                                if (movedTable != null) {
                                                  await refreshTables();
                                                  setState(() {});
                                                }
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.swap_horiz,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                          // tombol ubah nama
                                          Positioned(
                                            top: 40,
                                            right: 4,
                                            child: GestureDetector(
                                              onTap: () async {
                                                final updatedCust =
                                                    await showCustomerEditDialog(
                                                  context,
                                                  table['no'],
                                                );

                                                if (updatedCust != null) {
                                                  await customerChange(
                                                      table['no'].toString(),
                                                      updatedCust);
                                                  await refreshTables();
                                                  setState(() {});
                                                }
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.badge_outlined,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),

                                          // --- Tombol Ubah Jumlah Tamu (di bawahnya) ---
                                          Positioned(
                                            top: 80,
                                            right: 4,
                                            child: GestureDetector(
                                              onTap: () async {
                                                final updatedCount =
                                                    await showGuestCountDialog(
                                                  context,
                                                  table['no'],
                                                );

                                                if (updatedCount != null) {
                                                  await guestCount(
                                                      table['no'].toString(),
                                                      updatedCount);
                                                  await refreshTables();
                                                  setState(() {});
                                                }
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.people_alt,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                          //gabung Meja
                                          // --- Tombol Change Table ---
                                          Positioned(
                                            top: 120,
                                            right: 4,
                                            child: GestureDetector(
                                              onTap: () async {
                                                final movedTable =
                                                    await showMergeTableDialog(
                                                        context, table);
                                                if (movedTable != null) {
                                                  await refreshTables();
                                                  setState(() {});
                                                }
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.change_circle_outlined,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),

                    // Footer

                    //aksi button
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context, rootNavigator: true)
                                  .popUntil((route) => route.isFirst);
                            },
                            child: const Text(
                              'Batal',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Pilih Meja'),
                            onPressed: selectedTable == null
                                ? null
                                : () async {
                                    final prefs =
                                        await SharedPreferences.getInstance();

                                    await prefs.remove('selected_table');
                                    await prefs.remove('selected_area');

                                    await prefs.setString(
                                        'selected_table', selectedTable!);
                                    await prefs.setString(
                                        'selected_area', selectedArea);

                                    Navigator.pop(context, {
                                      'area': selectedArea,
                                      'table': selectedTable!,
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                  ]),
            ),
          );
        });
      },
    );
  }

  Widget buildInfoRow(IconData icon, String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$label: $value',
              style: const TextStyle(fontSize: 12, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(IconData icon, String label, String? value) {
    return TableRow(
      children: [
        Icon(icon, size: 20, color: Colors.white),
        Padding(
          padding: const EdgeInsets.only(left: 8.0, top: 4, bottom: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(
            ": ${value ?? "-"}",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(dynamic totalCash, dynamic totalNonCash) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Bagian Cash
            Expanded(
              child: _buildSummaryItem(
                icon: Icons.payments,
                label: "Total Cash",
                value: totalCash.toString(),
                color: Colors.green,
              ),
            ),

            // Garis Pemisah Tengah
            VerticalDivider(
              color: Colors.grey.shade300,
              thickness: 1,
              width: 1,
              indent: 12,
              endIndent: 12,
            ),

            // Bagian Non-Cash
            Expanded(
              child: _buildSummaryItem(
                icon: Icons.account_balance_wallet,
                label: "Total Non Cash",
                value: totalNonCash.toString(),
                color: Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

// Sub-widget untuk item di dalam card
  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            // Agar teks angka tidak pecah jika sangat panjang
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      // Menggunakan InkWell agar ada efek klik yang rapi
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1), // Warna latar lembut
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount;
    if (screenWidth >= 1200) {
      crossAxisCount = 10; // Desktop
    } else if (screenWidth >= 600) {
      crossAxisCount = 7; // Tablet
    } else {
      crossAxisCount = 4; // Phone
    }
    return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          // Menghilangkan bayangan agar menyatu dengan Wave di bawahnya
          elevation: 0,
          // Menggunakan flexibleSpace untuk menerapkan Gradient
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).primaryColor,
                  // Transisi lembut ke warna yang lebih terang (Soft)
                  Color.alphaBlend(Colors.white.withOpacity(0.2),
                      Theme.of(context).primaryColor),
                ],
              ),
            ),
          ),
          title: const Text(
            "MULTIPOS",
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2, // Membuat teks lebih modern
            ),
          ),
          actions: [
            // Ikon Notifikasi di sebelah kanan
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () {
                    // Logika ketika notifikasi diklik
                  },
                ),
                // Badge Merah jika ada notifikasi baru (Opsional)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 12, minHeight: 12),
                  ),
                )
              ],
            ),
            const SizedBox(width: 8), // Memberi sedikit jarak di ujung kanan
          ],
        ),
        body: Stack(
          children: [
            // Wave Background
            // Wave ATAS
            ClipPath(
              clipper: WaveClipperOne(),
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    // Tips Modern: Gunakan warna yang berdekatan di roda warna
                    colors: [
                      Theme.of(context).primaryColor, // Warna primary utama
                      Theme.of(context)
                          .primaryColor
                          .withOpacity(0.8), // Transisi ke warna lebih lembut
                    ],
                  ),
                ),
              ),
            ),
            // Wave BAWAH
            Align(
              alignment: Alignment.bottomCenter,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Wave Bawah
                  ClipPath(
                    clipper: WaveClipperOne(reverse: true),
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment
                              .bottomRight, // Gradient dimulai dari sudut bawah
                          end: Alignment.topLeft,
                          colors: [
                            Theme.of(context)
                                .primaryColor, // Warna primary utama
                            Theme.of(context).primaryColor.withOpacity(
                                0.8), // Transisi ke warna lebih lembut
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Tulisan di atas Wave
                  Positioned(
                      bottom: 16, // jarak dari bawah Wave
                      child: FutureBuilder<String?>(
                        future:
                            getDomainFromLocalStorage(), // tipe Future<String?>
                        builder: (context, snapshot) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Version $_latestVersion",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "Connect to : multipos.id",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          );
                        },
                      )),
                ],
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // BAGIAN ATAS (STATIS)

                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Table(
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        columnWidths: const {
                          0: IntrinsicColumnWidth(),
                          1: IntrinsicColumnWidth(),
                          2: FlexColumnWidth(),
                        },
                        children: [
                          _buildTableRow(Icons.person, "Cashier", cashier),
                          _buildTableRow(
                              Icons.phone_android, "Device", deviceId),
                          _buildTableRow(
                              Icons.lock, "Active Session", sessionId),
                        ],
                      ),
                      if (GlobalState.isKasir.value) ...[
                        const SizedBox(height: 20.0),
                        _buildSummaryCard(totalCash, totalNonCash),
                      ] else ...[
                        const SizedBox(height: 45.0),
                      ],
                    ],
                  ),
                ),

                // BAGIAN MENU (SCROLLABLE & RESPONSIVE)
                Expanded(
                  child: ConstrainedBox(
                    // Membatasi lebar grid agar tidak "gepeng" di layar desktop
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: GridView(
                        padding: const EdgeInsets.only(top: 8, bottom: 20),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 100, // Lebar tombol konsisten
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent:
                              100, // Tinggi tombol dikunci (Fixed Height)
                        ),
                        children: [
                          _buildMenuItem(
                            icon: Icons.monitor,
                            label: "POS",
                            color: Colors.blue,
                            onTap: handlePhoneInput,
                          ),
                          _buildMenuItem(
                            icon: Icons.table_restaurant,
                            label: "Hold TRX",
                            color: Colors.orange,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => TransactionQue())),
                          ),
                          _buildMenuItem(
                            icon: Icons.analytics,
                            label: "Product Sold",
                            color: Colors.red,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SoldScreen())),
                          ),
                          if (GlobalState.isKasir.value) ...[
                            _buildMenuItem(
                              icon: Icons.restaurant_menu,
                              label: "Catering",
                              color: Colors.green,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          RedeemCateringScreen())),
                            ),
                            _buildMenuItem(
                              icon: Icons.screenshot_monitor,
                              label: "Order Online",
                              color: Colors.purple,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => OrderOnline())),
                            ),
                            _buildMenuItem(
                              icon: Icons.file_copy,
                              label: "Summary",
                              color: Colors.teal,
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const EodSummary())),
                            ),
                            _buildMenuItem(
                              icon: Icons.inventory,
                              label: "TRX",
                              color: Colors.indigo,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          TransactionScreen())),
                            ),
                            _buildMenuItem(
                              icon: isLoading
                                  ? Icons.hourglass_empty
                                  : Icons.file_download,
                              label: "End of Day",
                              color: Colors.blueGrey,
                              onTap: () async {
                                bool? shouldLogout =
                                    await _showEndOfDayDialog(context);
                                if (shouldLogout == true) {
                                  setState(() => isLoading = true);
                                  _handleLogout();
                                  setState(() => isLoading = false);
                                }
                              },
                            ),
                          ],
                          _buildMenuItem(
                            icon: Icons.settings,
                            label: "Setup",
                            color: Colors.brown,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const PrinterSettingsScreen())),
                          ),
                          _buildMenuItem(
                            icon: Icons.logout_rounded,
                            label: "Logout",
                            color: Colors.redAccent,
                            onTap: () => Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => const LoginScreen()),
                                (route) => false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          ],
        ));
  }

  Widget _buildCard(String title, IconData icon, String value, Color color) {
    return Card(
      elevation: 4.0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                  fontSize: 14.0, color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8.0),
                Text(
                  value,
                  style: TextStyle(
                      fontSize: 20.0,
                      color: color,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final primaryColor = Theme.of(context).primaryColor;

    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: primaryColor),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BottomCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    // Mulai dari titik kiri atas
    path.lineTo(0.0, 0.0);

    // Garis lurus ke bawah sampai sebelum lengkungan dimulai
    // Menggunakan persentase (90%) agar lebih fleksibel dibanding angka statis 10.0
    double heightPoint = size.height * 0.9;
    path.lineTo(0.0, heightPoint);

    // Membuat lengkungan halus ke kanan bawah
    // Control point berada tepat di tengah bawah (size.width / 2, size.height)
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      heightPoint,
    );

    // Garis kembali ke titik kanan atas
    path.lineTo(size.width, 0.0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) =>
      true; // Ubah ke true jika konten dinamis
}
