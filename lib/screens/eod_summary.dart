import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import '../utils/printer_pref.dart';
import '../utils/printer_helper.dart';

/// ===============================
/// MODEL SESSION
/// ===============================
class EodSession {
  final String sessionId;
  final DateTime startedAt;
  final DateTime? endedAt;

  bool get isClosed => endedAt != null;

  EodSession({
    required this.sessionId,
    required this.startedAt,
    this.endedAt,
  });
}

/// ===============================
/// MODEL SUMMARY
/// ===============================
class BackendSummary {
  final int guest;
  final int invoice;
  final double subTotal;
  final double discount;
  final double total;
  final double service;
  final double tax;
  final double rounding;
  final double grandTotal;
  final double guestspd;
  final double qtyspd;
  final double invoicespd;
  final String deviceName;

  BackendSummary({
    required this.guest,
    required this.invoice,
    required this.subTotal,
    required this.total,
    required this.discount,
    required this.service,
    required this.tax,
    required this.rounding,
    required this.grandTotal,
    required this.guestspd,
    required this.qtyspd,
    required this.invoicespd,
    required this.deviceName,
  });

  factory BackendSummary.fromJson(Map<String, dynamic> json) {
    return BackendSummary(
      guest: int.tryParse(json['guest']?.toString() ?? '0') ?? 0,
      invoice: int.tryParse(json['invoice']?.toString() ?? '0') ?? 0,
      subTotal: double.tryParse(json['subTotal']?.toString() ?? '0') ?? 0,
      total: double.tryParse(json['total']?.toString() ?? '0') ?? 0,
      discount: double.tryParse(json['discount']?.toString() ?? '0') ?? 0,
      service: double.tryParse(json['service']?.toString() ?? '0') ?? 0,
      tax: double.tryParse(json['tax']?.toString() ?? '0') ?? 0,
      rounding: double.tryParse(json['rounding']?.toString() ?? '0') ?? 0,
      grandTotal: double.tryParse(json['grandTotal']?.toString() ?? '0') ?? 0,
      guestspd: double.tryParse(json['spending_guest']?.toString() ?? '0') ?? 0,
      qtyspd: double.tryParse(json['spending_qty']?.toString() ?? '0') ?? 0,
      invoicespd:
          double.tryParse(json['spending_invoice']?.toString() ?? '0') ?? 0,
      deviceName: json['device_name']?.toString() ?? '-',
    );
  }
}

class ItemDetail {
  final String name;
  final int qty;
  final double total;

  ItemDetail({
    required this.name,
    required this.qty,
    required this.total,
  });

  factory ItemDetail.fromJson(Map<String, dynamic> json) {
    return ItemDetail(
      name: json['name'],
      qty: int.tryParse(json['total_quantity'].toString()) ?? 0,
      total: double.tryParse(json['total'].toString()) ?? 0,
    );
  }
}

class ItemMinus {
  final String name;
  final int qty;
  final double total;

  ItemMinus({
    required this.name,
    required this.qty,
    required this.total,
  });

  factory ItemMinus.fromJson(Map<String, dynamic> json) {
    return ItemMinus(
      name: json['name'],
      qty: int.tryParse(json['total_quantity'].toString()) ?? 0,
      total: double.tryParse(json['total'].toString()) ?? 0,
    );
  }
}

class VoidSummary {
  final double grandTotal;
  final String idPos;

  VoidSummary({
    required this.grandTotal,
    required this.idPos,
  });

  factory VoidSummary.fromJson(Map<String, dynamic> json) {
    return VoidSummary(
      idPos: json['id_post_header']?.toString() ?? '-',
      grandTotal: double.tryParse(json['grand_total']?.toString() ?? '0') ?? 0,
    );
  }
}

class Discount {
  final double grandTotal;
  final int qty;
  final String voucher;

  Discount({
    required this.grandTotal,
    required this.qty,
    required this.voucher,
  });

  factory Discount.fromJson(Map<String, dynamic> json) {
    return Discount(
      voucher: json['voucher_code']?.toString() ?? '-',
      qty: int.tryParse(json['qtyDisc'].toString()) ?? 0,
      grandTotal: double.tryParse(json['grandTotal']?.toString() ?? '0') ?? 0,
    );
  }
}

class ComplimentSummary {
  final String name;
  final int qty;
  final double total;

  ComplimentSummary({
    required this.name,
    required this.qty,
    required this.total,
  });

  factory ComplimentSummary.fromJson(Map<String, dynamic> json) {
    return ComplimentSummary(
      name: json['compliment'],
      qty: int.tryParse(json['qtyCompli'].toString()) ?? 0,
      total: double.tryParse(json['grandTotal'].toString()) ?? 0,
    );
  }
}

class salestype {
  final String name;
  final int qty;
  final double total;

  salestype({
    required this.name,
    required this.qty,
    required this.total,
  });

  factory salestype.fromJson(Map<String, dynamic> json) {
    return salestype(
      name: json['order_type'],
      qty: int.tryParse(json['qtyType'].toString()) ?? 0,
      total: double.tryParse(json['grandTotal'].toString()) ?? 0,
    );
  }
}

class Outstanding {
  final double grandTotal;
  final String antrian;
  final String table;

  Outstanding({
    required this.grandTotal,
    required this.table,
    required this.antrian,
  });

  factory Outstanding.fromJson(Map<String, dynamic> json) {
    return Outstanding(
      antrian: json['antrian_id']?.toString() ?? '-',
      table: json['table_id']?.toString() ?? '-',
      grandTotal: double.tryParse(json['grand_total']?.toString() ?? '0') ?? 0,
    );
  }
}

class PaymentSummary {
  final String type;
  final double amount;
  final double subTotal;
  final double discount;
  final double tax;
  final double service;
  final double rounding;

  PaymentSummary({
    required this.type,
    required this.amount,
    this.subTotal = 0,
    this.discount = 0,
    this.tax = 0,
    this.service = 0,
    this.rounding = 0,
  });

  factory PaymentSummary.fromJson(String key, dynamic value) {
    final Map<String, dynamic> json =
        value is Map<String, dynamic> ? value : {};

    double _num(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

    return PaymentSummary(
      type: key.toUpperCase(),
      amount: _num(json['amount']),
      subTotal: _num(json['sub_total']),
      discount: _num(json['discount']),
      tax: _num(json['tax']),
      service: _num(json['service']),
      rounding: _num(json['rounding']),
    );
  }

  bool get isDP => type.contains('DP');
}

/// ===============================
/// PAGE EOD SUMMARY
/// ===============================
class EodSummary extends StatefulWidget {
  const EodSummary({super.key});

  @override
  State<EodSummary> createState() => _EodSummaryState();
}

class _EodSummaryState extends State<EodSummary> {
  DateTime selectedDate = DateTime.now();

  List<EodSession> sessions = [];
  EodSession? selectedSession;
  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  bool isLoadingSession = false;
  bool isLoadingSummary = false;
  bool is58mm = false;

  /// ===============================
  /// INIT
  /// ===============================
  @override
  void initState() {
    super.initState();
    _loadSessionsFromApi();
    _loadPaperSize();
  }

  Future<void> _loadPaperSize() async {
    final size = await PrinterPref.getPaperSize();
    setState(() {
      is58mm = size == PaperSize.mm58;
    });
  }

  /// ===============================
  /// UTIL
  /// ===============================
  String rupiah(double amount) {
    final f =
        NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0);
    return f.format(amount);
  }

  String formatRupiah(double amount) {
    final format =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return format.format(amount);
  }

  String getFormattedDate() {
    final now = DateTime.now();
    final formatter = DateFormat('dd-MM-yy HH:mm');
    return formatter.format(now);
  }

  String formatNumber(double value) {
    if (value % 1 == 0) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<String?> getDomain() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('domain');
  }

  Future<String?> getBranch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_branch_name');
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

  /// ===============================
  /// DATE PICKER
  /// ===============================
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
        selectedSession = null;

        sessions.clear();
      });
      _loadSessionsFromApi();
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('printer_address');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// ===============================
  /// FETCH SESSION LIST
  /// ===============================
  Future<void> _loadSessionsFromApi() async {
    final token = await getToken();
    final domain = await getDomain();
    final branch = await getBranch();
    final device = await getDevice();

    if (domain == null) return;

    try {
      setState(() => isLoadingSession = true);

      final response = await http.post(
        Uri.parse('$domain/api/fetch-session-pos'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sub_branch': branch,
          'device': device,
          'date': DateFormat('yyyy-MM-dd').format(selectedDate),
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        setState(() {
          sessions = (json['data'] as List).map((e) {
            return EodSession(
              sessionId: e['session_id'],
              startedAt: DateTime.parse(e['started_at']).toLocal(),
              endedAt: e['ended_at'] != null
                  ? DateTime.parse(e['ended_at']).toLocal()
                  : null,
            );
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("Load session error: $e");
    } finally {
      setState(() => isLoadingSession = false);
    }
  }

  /// ===============================
  /// FETCH SUMMARY BY SESSION
  /// ===============================
  Future<void> fetchSummaryBySession(EodSession session) async {
    final token = await getToken();
    final domain = await getDomain();
    final branch = await getBranch();

    if (domain == null) return;

    bool dialogShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http.post(
        Uri.parse('$domain/api/mobile-summary-order'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'session_id': session.sessionId,
          'sub_branch': branch,
        }),
      );

      if (dialogShown) {
        Navigator.pop(context);
        dialogShown = false;
      }

      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}");
      }

      final Map<String, dynamic> json = jsonDecode(response.body);

      final revenueList = json['revenue'] as List? ?? [];
      if (revenueList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Session tidak memiliki transaksi")),
        );
        return;
      }

      final summary = BackendSummary.fromJson(revenueList.first);

      final items = (json['detail'] as List? ?? [])
          .map((e) => ItemDetail.fromJson(e))
          .toList();

      final itemMinus = (json['minus'] as List? ?? [])
          .map((e) => ItemMinus.fromJson(e))
          .toList();

      final double totalItemMinus = itemMinus.fold(
        0.0,
        (sum, item) => sum + item.total,
      );

      final voidList = (json['void'] as List? ?? [])
          .map((e) => VoidSummary.fromJson(e))
          .toList();

      final double totalVoid = voidList.fold(
        0.0,
        (sum, item) => sum + item.grandTotal,
      );

      final complimentList = (json['compliment'] as List? ?? [])
          .map((e) => ComplimentSummary.fromJson(e))
          .toList();

      final double totalCompliment = complimentList.fold(
        0.0,
        (sum, item) => sum + item.total,
      );

      //salestype
      final salestypeList = (json['salesType'] as List? ?? [])
          .map((e) => salestype.fromJson(e))
          .toList();

      final double totalSalesType = salestypeList.fold(
        0.0,
        (sum, item) => sum + item.total,
      );

      final discount = (json['discount'] as List? ?? [])
          .map((e) => Discount.fromJson(e))
          .toList();

      final double totalDiscount = discount.fold(
        0.0,
        (sum, item) => sum + item.grandTotal,
      );

      //outstanding
      final outstanding = (json['dataHold'] as List? ?? [])
          .map((o) => Outstanding.fromJson(o))
          .toList();

      final double totalOutstanding = outstanding.fold(
        0.0,
        (sum, item) => sum + item.grandTotal,
      );

      final Map<String, dynamic> combinedTotals =
          json['combinedTotals'] as Map<String, dynamic>? ?? {};

      final payments = combinedTotals.entries
          .map((e) => PaymentSummary.fromJson(e.key, e.value))
          .toList();

      _showBackendPreview(
        context,
        summary,
        session: session,
        canPrint: session.isClosed,
        items: items,
        itemMinus: itemMinus,
        totalItemMinus: totalItemMinus,
        totalCompliment: totalCompliment,
        totalDiscount: totalDiscount,
        totalSalesType: totalSalesType,
        totalOutstanding: totalOutstanding,
        voids: voidList,
        totalVoid: totalVoid,
        compliments: complimentList,
        salesType: salestypeList,
        outstanding: outstanding,
        payments: payments,
        discount: discount,
      );
    } catch (e) {
      if (dialogShown) Navigator.pop(context);
      debugPrint("Fetch summary error: $e");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Gagal mengambil summary")),
      );
    }
  }

  Future<void> _printSummary({
    required BackendSummary summary,
    required EodSession session,
    required List<ItemDetail> items,
    required List<ItemMinus> itemMinus,
    required double totalItemMinus,
    required double totalVoid,
    required double totalCompliment,
    required double totalDiscount,
    required double totalOutstanding,
    required double totalSalesType,
    required List<VoidSummary> voids,
    required List<ComplimentSummary> compliments,
    required List<salestype> salestype,
    required List<Outstanding> outstanding,
    required List<Discount> discount,
    required List<PaymentSummary> payments,
    required PaperSize paperSize,
  }) async {
    Navigator.pop(context); // tutup modal preview

    // 🔥 PRINT PAKAI DATA INI (bukan fetch ulang)
    await printEodReceipt(
      summary: summary,
      session: session,
      items: items,
      itemMinus: itemMinus,
      totalItemMinus: totalItemMinus,
      totalVoid: totalVoid,
      totalCompliment: totalCompliment,
      totalDiscount: totalDiscount,
      totalOutstanding: totalOutstanding,
      totalSalesType: totalSalesType,
      voids: voids,
      compliments: compliments,
      salesType: salestype,
      outstanding: outstanding,
      discount: discount,
      payments: payments,
      paperSize: paperSize,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Print EOD berhasil"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> printEodReceipt({
    required BackendSummary summary,
    required EodSession session,
    required List<ItemDetail> items,
    required List<ItemMinus> itemMinus,
    required double totalItemMinus,
    required List<PaymentSummary> payments,
    required double totalVoid,
    required double totalCompliment,
    required double totalSalesType,
    required double totalDiscount,
    required double totalOutstanding,
    required List<VoidSummary> voids,
    required List<ComplimentSummary> compliments,
    required List<salestype> salesType,
    required List<Outstanding> outstanding,
    required List<Discount> discount,
    PaperSize paperSize = PaperSize.mm58,
  }) async {
    bool? isConnected = await printer.isConnected;
    if (isConnected != true) {
      await _connectToPrinter();
    }
    final prefs = await SharedPreferences.getInstance();
    final nameCashier = prefs.getString('cashier') ?? "-";
    final currentTime = getFormattedDate();

    final f = getFormat(paperSize);

    printer.printCustom("SESSION SUMMARY", 1, 1);
    printer.printNewLine();

    printer.printCustom(
      lr(
        "Location",
        summary.deviceName.isNotEmpty ? summary.deviceName.toUpperCase() : "-",
        f,
      ),
      1,
      0,
    );

    printer.printCustom(lr("Cashier", nameCashier, f), 1, 0);
    printer.printCustom(lr("Print On", currentTime, f), 1, 0);

    printer.printCustom("-" * f.paper, 1, 0);

    printer.printCustom(lr("Session", session.sessionId, f), 1, 0);
    printer.printCustom(
        lr("Total Sales", formatRupiah(summary.grandTotal), f), 1, 0);
    printer.printCustom(lr("Guest", summary.guest.toString(), f), 1, 0);
    printer.printCustom(lr("Invoice", summary.invoice.toString(), f), 1, 0);
    printer.printCustom(
        lr("Invoice Average", formatRupiah(summary.invoicespd), f), 1, 0);
    printer.printCustom(
        lr("Guest Average", formatRupiah(summary.guestspd), f), 1, 0);
    printer.printCustom(
        lr("Qty Average", formatRupiah(summary.qtyspd), f), 1, 0);

    // =========================
    // REVENUE
    // =========================
    printer.printNewLine();
    printer.printCustom("REVENUE", 1, 0);

    printer.printCustom(
        lr("Sub Total", formatRupiah(summary.subTotal), f), 1, 0);
    printer.printCustom(
        lr("Discount", formatRupiah(summary.discount), f), 1, 0);
    printer.printCustom(lr("Net Sales", formatRupiah(summary.total), f), 1, 0);
    printer.printCustom(lr("Service", formatRupiah(summary.service), f), 1, 0);
    printer.printCustom(lr("Tax", formatRupiah(summary.tax), f), 1, 0);
    printer.printCustom(
        lr("Rounding", formatRupiah(summary.rounding), f), 1, 0);

    printer.printCustom("-" * f.paper, 1, 0);
    printer.printCustom(
        lr("GRAND TOTAL", formatRupiah(summary.grandTotal), f), 1, 0);

    // =========================
    // DETAIL ITEM
    // =========================
    if (items.isNotEmpty) {
      printer.printNewLine();
      printer.printCustom("DETAIL ITEM", 1, 0);

      for (final i in items) {
        printer.printCustom(
          lr(
            "${i.qty} x ${i.name.toUpperCase()}",
            formatRupiah(i.total),
            f,
          ),
          1,
          0,
        );
      }
    }

    printer.printCustom("-" * f.paper, 1, 0);
    printer.printCustom(
        lr("SUB TOTAL", formatRupiah(summary.subTotal), f), 1, 0);

    // =========================
    // VOID ITEM
    // =========================
    if (itemMinus.isNotEmpty) {
      printer.printNewLine();
      printer.printCustom("VOID ITEM", 1, 1);

      for (final m in itemMinus) {
        printer.printCustom(
          lr(
            "${m.qty} x ${m.name.toUpperCase()}",
            formatRupiah(m.total),
            f,
          ),
          1,
          0,
        );
      }

      printer.printCustom("-" * f.paper, 1, 0);
      printer.printCustom(
          lr("TOTAL VOID", formatRupiah(totalItemMinus), f), 1, 0);
    }

    // =========================
    // PAYMENT SUMMARY
    // =========================
    if (payments.isNotEmpty) {
      printer.printNewLine();
      printer.printCustom("PAYMENT SUMMARY", 1, 0);

      for (final p in payments) {
        printer.printCustom(
          lr(
            p.isDP ? "${p.type}" : p.type,
            formatRupiah(p.amount),
            f,
          ),
          1,
          0,
        );
      }
    }

    // =========================
    // COMPLIMENT
    // =========================
    if (compliments.isNotEmpty) {
      printer.printNewLine();
      printer.printCustom("COMPLIMENT", 1, 1);

      for (final c in compliments) {
        printer.printCustom(
          lr(
            "${c.qty} x ${c.name.toUpperCase()}",
            formatRupiah(c.total),
            f,
          ),
          1,
          0,
        );
      }

      printer.printCustom("-" * f.paper, 1, 0);
      printer.printCustom(
          lr("TOTAL COMPLIMENT", formatRupiah(totalCompliment), f), 1, 0);
    }

    // =========================
    // DISCOUNT
    // =========================
    if (discount.isNotEmpty) {
      printer.printNewLine();
      printer.printCustom("DISCOUNT", 1, 0);

      for (final d in discount) {
        printer.printCustom(
          lr(
            "${d.qty} x ${d.voucher.toUpperCase()}",
            formatRupiah(d.grandTotal),
            f,
          ),
          1,
          0,
        );
      }

      printer.printCustom("-" * f.paper, 1, 0);
      printer.printCustom(
          lr("TOTAL DISCOUNT", formatRupiah(totalDiscount), f), 1, 0);
    }

    // =========================
    // SALES TYPE
    // =========================
    if (salesType.isNotEmpty) {
      printer.printNewLine();
      printer.printCustom("SALES TYPE", 1, 0);

      for (final st in salesType) {
        printer.printCustom(
          lr(
            "${st.qty} x ${st.name.toUpperCase()}",
            formatRupiah(st.total),
            f,
          ),
          1,
          0,
        );
      }

      printer.printCustom("-" * f.paper, 1, 0);
      printer.printCustom(
          lr("TOTAL SALES TYPE", formatRupiah(totalSalesType), f), 1, 0);
    }

    // =========================
    // OUTSTANDING
    // =========================
    if (outstanding.isNotEmpty) {
      printer.printNewLine();
      printer.printCustom("OUTSTANDING", 1, 0);

      for (final o in outstanding) {
        final label = (o.table != null && o.table.toString().isNotEmpty)
            ? "${o.antrian} / ${o.table}"
            : o.antrian;

        printer.printCustom(
          lr(label, formatRupiah(o.grandTotal), f),
          1,
          0,
        );
      }

      printer.printCustom("-" * f.paper, 1, 0);
      printer.printCustom(
          lr("TOTAL OUTSTANDING", formatRupiah(totalOutstanding), f), 1, 0);
    }

    printer.printNewLine();
    printer.printNewLine();

    sendRawCutCommand();
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

  /// ===============================
  /// UI
  /// ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Summary"),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoadingSession
            ? const Center(child: CircularProgressIndicator())
            : sessions.isEmpty
                ? const Center(child: Text("Tidak ada session"))
                : ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (_, i) {
                      final s = sessions[i];
                      final isOpen = s.endedAt == null;

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 3,
                        child: ListTile(
                          leading: Icon(
                            isOpen ? Icons.lock_open : Icons.lock,
                            color: isOpen ? Colors.orange : Colors.green,
                          ),
                          title: Text(
                            s.sessionId,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            isOpen
                                ? "${DateFormat('HH:mm').format(s.startedAt)} - OPEN"
                                : "${DateFormat('HH:mm').format(s.startedAt)} - "
                                    "${DateFormat('HH:mm').format(s.endedAt!)}",
                          ),

                          trailing: isOpen
                              ? const Chip(
                                  label: Text("OPEN"),
                                  backgroundColor: Colors.orangeAccent,
                                )
                              : const Icon(Icons.chevron_right),

                          /// OPEN & CLOSED bisa preview
                          onTap: () {
                            setState(() => selectedSession = s);
                            fetchSummaryBySession(s);
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  /// ===============================
  /// PREVIEW DIALOG
  /// ===============================
  Future<void> _showBackendPreview(
    BuildContext context,
    BackendSummary summary, {
    required EodSession session,
    required bool canPrint,
    required double totalItemMinus,
    required double totalVoid,
    required double totalCompliment,
    required double totalSalesType,
    required double totalDiscount,
    required double totalOutstanding,
    required List<ItemDetail> items,
    required List<ItemMinus> itemMinus,
    required List<VoidSummary> voids,
    required List<ComplimentSummary> compliments,
    required List<salestype> salesType,
    required List<Outstanding> outstanding,
    required List<Discount> discount,
    required List<PaymentSummary> payments,
  }) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8, // ⬅️ Batas tinggi
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                /// 🔹 CONTENT SCROLLABLE
                Expanded(
                  child: SingleChildScrollView(
                    child: _backendSummaryCard(summary, session,
                        items: items,
                        itemMinus: itemMinus,
                        totalItemMinus: totalItemMinus,
                        voids: voids,
                        totalVoid: totalVoid,
                        totalCompliment: totalCompliment,
                        totalSalesType: totalSalesType,
                        totalDiscount: totalDiscount,
                        totalOutstanding: totalOutstanding,
                        compliments: compliments,
                        outstanding: outstanding,
                        salestype: salesType,
                        discount: discount,
                        payments: payments),
                  ),
                ),

                const SizedBox(height: 16),

                /// 🔹 BUTTON (FIXED)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // =========================
                    // PAPER SIZE TOGGLE
                    // =========================
                    StatefulBuilder(
                      builder: (context, setLocalState) {
                        bool localIs58mm = is58mm;

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Paper Size",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Row(
                              children: [
                                const Text("80mm"),
                                Switch(
                                  value: localIs58mm,
                                  onChanged: (value) async {
                                    // UI modal saja
                                    setLocalState(() => localIs58mm = value);

                                    // simpan preference
                                    await PrinterPref.setPaperSize(
                                      value ? PaperSize.mm58 : PaperSize.mm80,
                                    );

                                    // sinkron ke parent (tanpa rebuild modal)
                                    if (mounted) {
                                      setState(() => is58mm = value);
                                    }
                                  },
                                ),
                                const Text("58mm"),
                              ],
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),

                    // =========================
                    // ACTION BUTTON
                    // =========================
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Tutup"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              // 🔥 AMBIL LANGSUNG DARI PREF (PALING AMAN)
                              final paperSize =
                                  await PrinterPref.getPaperSize();

                              _printSummary(
                                summary: summary,
                                session: session,
                                items: items,
                                itemMinus: itemMinus,
                                totalItemMinus: totalItemMinus,
                                totalVoid: totalVoid,
                                totalCompliment: totalCompliment,
                                totalDiscount: totalDiscount,
                                totalOutstanding: totalOutstanding,
                                totalSalesType: totalSalesType,
                                voids: voids,
                                compliments: compliments,
                                salestype: salesType,
                                outstanding: outstanding,
                                discount: discount,
                                payments: payments,
                                paperSize: paperSize,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("Print"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    String left,
    String right, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            left,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            right,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF6C63FF),
        ),
      ),
    );
  }

  Widget _backendSummaryCard(
    BackendSummary s,
    EodSession session, {
    required List<ItemDetail> items,
    required List<ItemMinus> itemMinus,
    required double totalItemMinus,
    required double totalVoid,
    required double totalCompliment,
    required double totalDiscount,
    required double totalOutstanding,
    required double totalSalesType,
    required List<VoidSummary> voids,
    required List<ComplimentSummary> compliments,
    required List<salestype> salestype,
    required List<Outstanding> outstanding,
    required List<Discount> discount,
    required List<PaymentSummary> payments,
  }) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle("SESSION SUMMARY"),
          _row(
            "Location",
            s.deviceName.toUpperCase(),
            bold: true,
          ),
          _row(
            "Session",
            session.sessionId,
            bold: true,
          ),
          _row(
            "Total Sales",
            rupiah(s.grandTotal),
            bold: true,
            color: Colors.green,
          ),
          _row(
            "Guest",
            s.guest.toString(),
            bold: true,
          ),
          _row(
            "Invoice",
            s.invoice.toString(),
            bold: true,
          ),
          _row(
            "Invoice Average",
            rupiah(s.invoicespd),
            bold: true,
          ),
          _row(
            "Guest Average",
            rupiah(s.guestspd),
            bold: true,
          ),
          _row(
            "Qty Average",
            rupiah(s.qtyspd),
            bold: true,
          ),
          const Divider(),
          _sectionTitle("REVENUE"),
          _row("Sub Total", rupiah(s.subTotal)),
          _row("Discount", rupiah(s.discount)),
          _row("Net Sales", rupiah(s.total)),
          _row("Service", rupiah(s.service)),
          _row("Tax", rupiah(s.tax)),
          _row("Rounding", rupiah(s.rounding)),
          const Divider(),
          _row("Total Revenue", bold: true, rupiah(s.grandTotal)),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle("DETAIL ITEM"),
            ...items.map(
              (i) => _row(
                "${i.qty} x ${(i.name ?? '').toUpperCase()} ",
                rupiah(i.total),
              ),
            ),
            const Divider(),
            _row("Sub Total", bold: true, rupiah(s.subTotal)),
          ],
          if (itemMinus.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle("VOID ITEM "),
            ...itemMinus.map(
              (m) => _row(
                "${m.qty} x ${(m.name ?? '').toUpperCase()} ",
                rupiah(m.total),
              ),
            ),
            const Divider(),
            // TOTAL
            _row(
              "TOTAL VOID ITEM",
              rupiah(totalItemMinus),
              bold: true,
            ),
          ],
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle("PAYMENT SUMMARY"),
            ...payments.map(
              (p) => _row(
                p.type,
                rupiah(p.amount),
                color: p.isDP ? Colors.red : null,
                bold: p.isDP,
              ),
            ),
          ],
          if (voids.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle("VOID TRX"),
            ...voids.map(
              (v) => _row(
                "${v.idPos}",
                rupiah(v.grandTotal),
                color: Colors.red,
              ),
            ),
            const Divider(),
            _row(
              "TOTAL VOID",
              rupiah(totalVoid),
              bold: true,
            ),
          ],
          if (compliments.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle("COMPLIMENT"),
            ...compliments.map(
              (c) => _row(
                "${c.qty} x ${c.name}",
                rupiah(c.total),
                color: Colors.black,
              ),
            ),
            const Divider(),
            _row(
              "TOTAL COMPLIMENT",
              rupiah(totalCompliment),
              bold: true,
            ),
          ],
          if (discount.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle("DISCOUNT"),
            ...discount.map(
              (g) => _row(
                "${g.qty} x ${g.voucher}",
                rupiah(g.grandTotal),
                color: Colors.black,
              ),
            ),
            const Divider(),
            _row(
              "TOTAL DISC",
              rupiah(totalDiscount),
              bold: true,
            ),
          ],
          if (salestype.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle("SALES TYPE"),
            ...salestype.map(
              (h) => _row(
                "${h.qty} x ${h.name}",
                rupiah(h.total),
                color: Colors.black,
              ),
            ),
            const Divider(),
            _row(
              "TOTAL Sales Type",
              rupiah(totalSalesType),
              bold: true,
            ),
          ],
          if (outstanding.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle("Outstanding"),
            ...outstanding.map(
              (o) => _row(
                o.table != null && o.table.toString().isNotEmpty
                    ? "${o.antrian} / ${o.table}"
                    : o.antrian,
                rupiah(o.grandTotal),
                color: Colors.black,
              ),
            ),
            const Divider(),
            _row(
              "TOTAL Outstanding",
              rupiah(totalOutstanding),
              bold: true,
            ),
          ],
        ],
      ),
    );
  }
}
