import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi';
import 'package:wakelock/wakelock.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  _PrinterSettingsScreenState createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  BlueThermalPrinter printer = BlueThermalPrinter.instance;
  List<BluetoothDevice> devices = [];
  List<TextEditingController> dapurControllers = [];
  List<TextEditingController> barControllers = [];
  BluetoothDevice? selectedDevice;
  bool isConnected = false;
  bool isLoading = false;
  bool printCustomer = true;
  bool printCaptain = false;
  int printCaptainQty = 1;
  int printCustQty = 1;
  bool printLabelProd = false;
  int printLabelQty = 1;
  String fontType = "1";
  final lineSpacingController = TextEditingController();

  // Tambahan untuk printer LAN
  final TextEditingController ipDapurController = TextEditingController();
  final TextEditingController ipBarController = TextEditingController();
  final TextEditingController ipLabelController = TextEditingController();
  final TextEditingController widthController = TextEditingController();
  final TextEditingController heightController = TextEditingController();
  final TextEditingController topMarginController = TextEditingController();
  final TextEditingController maxCharsController = TextEditingController();
  final TextEditingController textController = TextEditingController();
  //printer usb
  final TextEditingController usbPrinterController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    _initializePrinter();
  }

  void addDapur() {
    setState(() {
      dapurControllers.add(TextEditingController());
    });
  }

  void addBar() {
    setState(() {
      barControllers.add(TextEditingController());
    });
  }

  Future<void> _initializePrinter() async {
    await _getDevices();
    await _loadSavedPrinter();
  }

  Future<void> _getDevices() async {
    try {
      List<BluetoothDevice> availableDevices = await printer.getBondedDevices();
      setState(() {
        devices = availableDevices;
      });
    } catch (e) {
      _showMessage("Failed to fetch paired devices: $e");
    }
  }

  Future<void> printCaptainToLAN(String ipAddress, String content,
      {int port = 9100}) async {
    try {
      final socket = await Socket.connect(ipAddress, port,
          timeout: const Duration(seconds: 5));

      final List<int> bytes = [];

      // Inisialisasi printer
      bytes.addAll([0x1B, 0x40]);

      // Center
      bytes.addAll([0x1B, 0x61, 0x01]);
      bytes.addAll(utf8.encode("CAPTAIN ORDER\n"));

      // Kiri
      bytes.addAll([0x1B, 0x61, 0x00]);
      bytes.addAll(utf8.encode("$content\n"));

      // Feed dan cut
      bytes.addAll([0x0A, 0x0A]);
      bytes.addAll([0x1D, 0x56, 0x00]); // Full cut

      socket.add(Uint8List.fromList(bytes));
      await socket.flush();
      await socket.close();

      print("Berhasil cetak ke $ipAddress");
    } catch (e) {
      print("Gagal cetak ke $ipAddress: $e");
    }
  }

  Future<void> printLabelXP4601B(
    String ipAddress,
    List<String> products, {
    int port = 9100,
  }) async {
    Socket? socket;
    try {
      final prefs = await SharedPreferences.getInstance();

      // ambil dari local storage
      final width = prefs.getString('labelWidth') ?? '35';
      final height = prefs.getString('labelHeight') ?? '15';
      final topMargin = prefs.getInt('label_top_margin') ?? 40;
      final maxCharsPerLine = prefs.getInt('label_max_chars') ?? 22;
      final lineSpacingPref = prefs.getInt('label_line_spacing') ?? 30;
      final fontType = prefs.getString('label_font_type') ?? "1";

      socket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 5),
      );

      // Inisialisasi label
      final initBuffer = StringBuffer()
        ..writeln("SIZE $width mm,$height mm")
        ..writeln("GAP 2 mm,0")
        ..writeln("DIRECTION 1"); // arah print normal
      socket.add(latin1.encode(initBuffer.toString()));
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 200));

      for (final product in products) {
        final wrappedLines =
            wrapTextFlexible(product.toUpperCase(), maxCharsPerLine);
        final totalLines = wrappedLines.length;

        // Kalau user set lineSpacing manual → pakai itu
        // kalau tidak → hitung otomatis
        final labelHeightPx = double.tryParse(height) ?? 100;
        final lineSpacing = lineSpacingPref > 0
            ? lineSpacingPref.toDouble()
            : ((labelHeightPx - topMargin) / totalLines).clamp(15, 25);

        final labelBuffer = StringBuffer();
        labelBuffer.writeln("CLS"); // Bersihkan label sebelum print

        double y = topMargin.toDouble();
        for (final line in wrappedLines) {
          if (line.trim().isEmpty) continue;
          // pakai fontType dari setting
          labelBuffer.writeln('TEXT 0,${y.toInt()},"$fontType",0,1,1,"$line"');
          y += lineSpacing;
        }

        labelBuffer.writeln("PRINT 1");

        // Kirim label ke printer
        socket.add(latin1.encode(labelBuffer.toString()));
        await socket.flush();

        // Delay untuk printer memproses
        await Future.delayed(Duration(milliseconds: 400 + totalLines * 30));
      }

      print("✅ Berhasil cetak ${products.length} label ke $ipAddress");
    } catch (e) {
      print("❌ Gagal cetak ke $ipAddress: $e");
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

  Future<bool> pingPrinter(String ip, {int port = 9100}) async {
    try {
      final socket =
          await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      await socket.close();
      print("✅ Printer bisa dihubungi di $ip:$port");
      return true;
    } catch (e) {
      print("❌ Tidak bisa konek ke $ip:$port → $e");
      return false;
    }
  }

  Future<void> testPrinterConnection(String ip, {int port = 9100}) async {
    try {
      final socket =
          await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      print("✅ Printer bisa dihubungi di $ip:$port");
      await socket.close();
    } catch (e) {
      print("❌ Tidak bisa konek ke $ip:$port → $e");
    }
  }

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();

    // Ambil data dari SharedPreferences
    String? address = prefs.getString('printer_address');
    String? usbPrinterName = prefs.getString('usb_printer_name');

    printCustomer = prefs.getBool('print_customer') ?? true;
    printCaptain = prefs.getBool('print_captain') ?? false;
    printCaptainQty = prefs.getInt('print_captain_qty') ?? 1;
    printCustQty = prefs.getInt('print_cust_qty') ?? 1;
    printLabelProd = prefs.getBool('print_label_prod') ?? false;
    printLabelQty = prefs.getInt('print_label_qty') ?? 1;
    _qtyController.text = printCustQty.toString();

    // Load IP LAN printer

    List<String> barSaved = prefs.getStringList('printer_bar_list') ?? [];
    List<String> dapurSaved = prefs.getStringList('printer_dapur_list') ?? [];

    setState(() {
      barControllers =
          barSaved.map((ip) => TextEditingController(text: ip)).toList();
      dapurControllers =
          dapurSaved.map((ip) => TextEditingController(text: ip)).toList();

      // Jika kosong, buat minimal 1 field
      if (barControllers.isEmpty) barControllers.add(TextEditingController());
      if (dapurControllers.isEmpty)
        dapurControllers.add(TextEditingController());
    });

    ipLabelController.text = prefs.getString('ip_label') ?? '';

    //seting ukuran label
    lineSpacingController.text =
        (prefs.getInt('label_line_spacing') ?? 30).toString();
    fontType = prefs.getString('label_font_type') ?? "1";
    widthController.text = prefs.getString('labelWidth') ?? '35';
    heightController.text = prefs.getString('labelHeight') ?? '15';
    topMarginController.text =
        (prefs.getInt('labelTopMargin') ?? 40).toString();
    maxCharsController.text = (prefs.getInt('labelMaxChars') ?? 22).toString();

    // Jika Windows, load USB printer saja
    if (Platform.isWindows) {
      if (usbPrinterName != null && usbPrinterName.isNotEmpty) {
        usbPrinterController.text = usbPrinterName;
      }
      return; // Stop di sini, jangan lanjutkan Bluetooth jika Windows
    }

    // Jika Android, lanjutkan untuk load Bluetooth
    if (Platform.isAndroid) {
      if (address != null && devices.isNotEmpty) {
        BluetoothDevice? savedDevice = devices.firstWhere(
          (device) => device.address == address,
          orElse: () => devices.first,
        );

        setState(() {
          selectedDevice = savedDevice;
        });

        bool connected = await printer.isConnected ?? false;
        if (!connected) {
          await _connect();
        } else {
          setState(() => isConnected = true);
        }
      }
    }
  }

  Future<void> _connect() async {
    setState(() => isLoading = true);

    try {
      bool connected = await printer.isConnected ?? false;
      if (!connected && selectedDevice != null) {
        await printer.connect(selectedDevice!);
        connected = await printer.isConnected ?? false;
      }

      setState(() {
        isConnected = connected;
        isLoading = false;
      });

      if (connected) {
        _showMessage("Connected to ${selectedDevice!.name}");
      } else {
        _showMessage("Failed to connect");
      }
    } catch (e) {
      setState(() {
        isConnected = false;
        isLoading = false;
      });

      if (e.toString().contains("already exist")) {
        _showMessage("Printer sudah terhubung.");
        isConnected = true;
      } else {
        _showMessage("Failed to connect: $e");
      }
    }
  }

  Future<void> _savePrinter() async {
    final prefs = await SharedPreferences.getInstance();

    // Hapus semua key lama
    await prefs.remove('print_customer');
    await prefs.remove('print_captain');
    await prefs.remove('print_captain_qty');
    await prefs.remove('print_label_prod');
    await prefs.remove('print_label_qty');
    await prefs.remove('print_cust_qty');
    await prefs.remove('printer_address');
    await prefs.remove('printer_connected');

    await prefs.remove('usb_printer_name');
    await prefs.remove('ip_label');
    await prefs.remove('label_font_type');
    await prefs.remove('label_line_spacing');

    await prefs.remove('labelWidth');
    await prefs.remove('labelHeight');
    await prefs.remove('labelTopMargin');
    await prefs.remove('labelMaxChars');

    //lan
    await prefs.remove('ip_printer_bar');
    await prefs.remove('ip_printer_dapur');

    await prefs.remove('printer_bar_list');
    await prefs.remove('printer_dapur_list');

    List<String> barList = barControllers
        .map((c) => c.text.trim())
        .where((ip) => ip.isNotEmpty)
        .toList();

    List<String> dapurList = dapurControllers
        .map((c) => c.text.trim())
        .where((ip) => ip.isNotEmpty)
        .toList();

    // Simpan list baru
    await prefs.setStringList('printer_bar_list', barList);
    await prefs.setStringList('printer_dapur_list', dapurList);

    // Simpan setting umum (berlaku untuk semua platform)
    await prefs.setBool('print_customer', printCustomer);
    await prefs.setBool('print_captain', printCaptain);
    await prefs.setInt('print_cust_qty', printCustQty);
    await prefs.setInt('print_captain_qty', printCaptainQty);
    await prefs.setBool('print_label_prod', printLabelProd);
    await prefs.setInt('print_label_qty', printLabelQty);
    await prefs.setString('ip_label', ipLabelController.text.trim());

    await prefs.setString('labelWidth', widthController.text);
    await prefs.setString('labelHeight', heightController.text);
    await prefs.setInt(
        'labelTopMargin', int.tryParse(topMarginController.text) ?? 40);
    await prefs.setInt(
        'labelMaxChars', int.tryParse(maxCharsController.text) ?? 22);
    await prefs.setString('label_font_type', fontType);
    await prefs.setInt(
        'label_line_spacing', int.tryParse(lineSpacingController.text) ?? 30);
    // Platform khusus: Windows (USB printer)
    if (Platform.isWindows) {
      final usbName = usbPrinterController.text.trim();
      if (usbName.isNotEmpty) {
        await prefs.setString('usb_printer_name', usbName);
      }
    }

    // Platform khusus: Android (Bluetooth printer)
    if (Platform.isAndroid) {
      if (selectedDevice != null && selectedDevice!.address != null) {
        await prefs.setString('printer_address', selectedDevice!.address!);
        await prefs.setBool('printer_connected', isConnected);
      }
    }

    // Tampilkan pesan sukses
    _showMessage("Pengaturan printer berhasil disimpan");
  }

  Future<void> _testPrintBluetooth() async {
    try {
      // 🔹 Aktifkan wakelock (biar screen tidak tidur saat print)
      await Wakelock.enable();

      bool isActuallyConnected = await printer.isConnected ?? false;

      if (isActuallyConnected) {
        // 🔹 Print teks uji
        printer.printNewLine();
        printer.printCustom("=== TEST PRINT BLUETOOTH ===", 3, 1);
        printer.printNewLine();
        printer.printCustom("Hello from Multipos!", 1, 1);
        printer.printCustom("--------------------------", 1, 1);
        printer.printNewLine();
        sendRawCutCommand();
        _showMessage("✅ Test print & cut success!");
      } else {
        _showMessage("❌ Bluetooth printer not connected");
      }
    } catch (e) {
      _showMessage("Print failed: $e");
    } finally {
      await Wakelock.disable();
    }
  }

  void sendRawCutCommand() async {
    final List<int> commands = [
      0x1D,
      0x56,
      0x42,
      0x00,
    ];

    final Uint8List bytes = Uint8List.fromList(commands);
    await BlueThermalPrinter.instance.writeBytes(bytes);
  }

  Future<void> _openDrawer() async {
    try {
      // 🔹 Aktifkan wakelock (biar screen tidak tidur saat print)
      await Wakelock.enable();

      bool isActuallyConnected = await printer.isConnected ?? false;

      if (isActuallyConnected) {
        _sendRawDrawerCommand();
        _showMessage("✅ Open cash drawer success!");
      } else {
        _showMessage("❌ Bluetooth printer not connected");
      }
    } catch (e) {
      _showMessage("Print failed: $e");
    } finally {
      // 🔹 Nonaktifkan wakelock setelah selesai
      await Wakelock.disable();
    }
  }

  void _sendRawDrawerCommand() async {
    final List<int> commands = [
      0x1B,
      0x70,
      0x00,
      0x19,
      0xFA,
    ];

    final Uint8List bytes = Uint8List.fromList(commands);
    await BlueThermalPrinter.instance.writeBytes(bytes);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _openBluetoothSettings() {
    final intent = const AndroidIntent(
      action: 'android.settings.BLUETOOTH_SETTINGS',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    intent.launch();
  }

  Future<void> _testPrintUsb() async {
    if (!Platform.isWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Test print hanya tersedia di Windows")),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final printerName = prefs.getString('usb_printer_name');

    if (printerName == null || printerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nama printer belum diatur")),
      );
      return;
    }

    final docName = 'Test Print';
    final utf16Doc = docName.toNativeUtf16();
    final utf16PrinterName = printerName.toNativeUtf16();
    final hPrinter = calloc<HANDLE>();
    final jobInfo = calloc<DOC_INFO_1>()
      ..ref.pDocName = utf16Doc
      ..ref.pOutputFile = nullptr
      ..ref.pDatatype = TEXT('RAW');

    Pointer<Uint8>? dataPtr;
    Pointer<Uint32>? bytesWrittenPtr;

    try {
      final openResult = OpenPrinter(utf16PrinterName, hPrinter, nullptr);
      if (openResult == 0) {
        final err = GetLastError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text("Gagal membuka printer ($printerName), Error: $err")),
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

      // Data struk dummy
      final bytes = <int>[
        27, 64, // ESC @ - initialize
        ...utf8.encode('===== TEST PRINT =====\n'),
        ...utf8.encode('Nama Printer: $printerName\n'),
        ...utf8.encode('Oke Sukses connect\n\n\n'),
        29, 86, 1, // Cut paper
      ];

      dataPtr = calloc<Uint8>(bytes.length);
      bytesWrittenPtr = calloc<Uint32>();

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

        await Future.delayed(
            const Duration(milliseconds: 500)); // delay to flush

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Test print berhasil dikirim")),
        );
      }
    } finally {
      if (hPrinter.value != 0) {
        ClosePrinter(hPrinter.value);
      }

      // Free memory
      calloc.free(hPrinter);
      calloc.free(jobInfo);
      calloc.free(utf16Doc);
      calloc.free(utf16PrinterName);

      if (dataPtr != null) calloc.free(dataPtr);
      if (bytesWrittenPtr != null) calloc.free(bytesWrittenPtr);
    }
  }

  Widget buildPrinterTestButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dapurControllers.isNotEmpty) ...[
          const Text("Test Printer Dapur",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
        ],
        ...dapurControllers.asMap().entries.map((e) {
          int index = e.key;
          String ip = e.value.text.trim();

          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final content =
                        "2x Test Dapur ${index + 1}\n1x Contoh Item";
                    await printCaptainToLAN(ip, content);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  child: Text("Test Dapur ${index + 1}  ($ip)"),
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        }),
        if (barControllers.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text("Test Printer Bar",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
        ],
        ...barControllers.asMap().entries.map((e) {
          int index = e.key;
          String ip = e.value.text.trim();

          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final content =
                        "3x Test Bar ${index + 1}\n1x Contoh Minuman";
                    await printCaptainToLAN(ip, content);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  child: Text("Test Bar ${index + 1}  ($ip)"),
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Printer Settings"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openBluetoothSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text("Bluetooth Printer",
                style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<BluetoothDevice>(
              isExpanded: true,
              hint: const Text("Select Printer"),
              value: selectedDevice,
              onChanged: (device) async {
                if (isConnected) await printer.disconnect();
                setState(() {
                  selectedDevice = device;
                  isConnected = false;
                });
              },
              items: devices.map((device) {
                return DropdownMenuItem(
                  value: device,
                  child: Text(device.name ?? 'Unknown'),
                );
              }).toList(),
            ),
            CheckboxListTile(
              value: printCustomer,
              onChanged: (value) {
                setState(() {
                  printCustomer = value ?? false;
                });
              },
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Cetak Struk Customer"),
                  if (printCustomer)
                    SizedBox(
                      width: 60,
                      child: TextField(
                        textAlign: TextAlign.center,
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                        ),
                        onChanged: (val) async {
                          final qty = int.tryParse(val) ?? 1;
                          setState(() => printCustQty = qty < 1 ? 1 : qty);
                          await _savePrinter();
                        },
                      ),
                    ),
                ],
              ),
              activeColor: Theme.of(context).primaryColor,
              checkColor: Colors.white,
            ),
            CheckboxListTile(
              value: printCaptain,
              onChanged: (value) =>
                  setState(() => printCaptain = value ?? false),
              title: const Text("Cetak Captain Order"),
              activeColor: Theme.of(context).primaryColor,
              checkColor: Colors.white,
            ),
            CheckboxListTile(
              value: printLabelProd,
              onChanged: (value) =>
                  setState(() => printLabelProd = value ?? false),
              title: const Text("Cetak Label"),
              activeColor: Theme.of(context).primaryColor,
              checkColor: Colors.white,
            ),
            if (printCaptain)
              Row(
                children: [
                  const Text("Jumlah Cetak Captain: "),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: printCaptainQty,
                      items: [1, 2, 3, 4, 5].map((e) {
                        return DropdownMenuItem<int>(
                          value: e,
                          child: Text("$e"),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => printCaptainQty = val ?? 1),
                    ),
                  ),
                ],
              ),
            if (printLabelProd) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widthController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Lebar Label (mm)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: heightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tinggi Label (mm)',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: topMarginController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Top Margin (px)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: maxCharsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max Chars per Line',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: lineSpacingController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Line Spacing (px)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Dropdown pilih font type
              DropdownButtonFormField<String>(
                value: fontType,
                decoration: const InputDecoration(labelText: "Font Type"),
                items: const [
                  DropdownMenuItem(value: "1", child: Text("Font 1")),
                  DropdownMenuItem(value: "2", child: Text("Font 2")),
                  DropdownMenuItem(value: "3", child: Text("Font 3")),
                ],
                onChanged: (value) async {
                  final prefs = await SharedPreferences.getInstance();
                  setState(() => fontType = value ?? "1");
                  await prefs.setString('label_font_type', fontType);
                },
              ),
              // Row(
              //   children: [
              //     const Text("Jumlah Cetak Label: "),
              //     Expanded(
              //       child: DropdownButton<int>(
              //         isExpanded: true,
              //         value: printLabelQty,
              //         items: [1, 2, 3, 4, 5].map((e) {
              //           return DropdownMenuItem<int>(
              //             value: e,
              //             child: Text("$e"),
              //           );
              //         }).toList(),
              //         onChanged: (val) =>
              //             setState(() => printLabelQty = val ?? 1),
              //       ),
              //     ),
              //   ],
              // ),
            ],
            const Divider(height: 16),
            const Text("Printer Label",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                // TextField isi IP
                Expanded(
                  child: TextField(
                    controller: ipLabelController,
                    decoration: const InputDecoration(
                      labelText: "IP Printer Label",
                      hintText: "Contoh: 192.168.1.100",
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),

                const SizedBox(width: 8),
                SizedBox(
                  height: 40, // samain tinggi dengan TextField
                  child: ElevatedButton(
                    onPressed: () async {
                      final ip = ipLabelController.text.trim();

                      if (ip.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("IP Printer belum diisi")),
                        );
                        return;
                      }

                      final ok = await pingPrinter(ip, port: 9100);

                      if (ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text("Printer $ip dapat dihubungi ✅")),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text("Printer $ip tidak bisa dihubungi ❌")),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 34, 159, 255),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text("Ping"),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            const Text("LAN Printer",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Column(
              children: [
                for (int i = 0; i < barControllers.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Label: Bar 1, Bar 2, ...
                        SizedBox(
                          width: 70,
                          child: Text(
                            "Bar ${i + 1}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),

                        // Input IP Printer
                        Expanded(
                          child: TextField(
                            controller: barControllers[i],
                            decoration: const InputDecoration(
                              labelText: "IP Printer",
                              hintText: "192.168.x.x",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Tombol Ping
                        ElevatedButton(
                          onPressed: () async {
                            final ip = barControllers[i].text.trim();
                            if (ip.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("IP Bar ${i + 1} belum diisi"),
                                ),
                              );
                              return;
                            }

                            final ok = await pingPrinter(ip, port: 9100);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? "Printer $ip OK ✓"
                                    : "Printer $ip tidak dapat dihubungi ❌"),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text("Ping"),
                        ),

                        const SizedBox(width: 8),

                        // Tombol Hapus Field
                        IconButton(
                          icon: const Icon(Icons.delete_forever,
                              color: Colors.red),
                          onPressed: () {
                            setState(() {
                              barControllers.removeAt(i);
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Tambah Printer Dapur
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      barControllers.add(TextEditingController());
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text("Tambah Printer Bar"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Column(
              children: [
                for (int i = 0; i < dapurControllers.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Label: Dapur 1, Dapur 2, ...
                        SizedBox(
                          width: 70,
                          child: Text(
                            "Dapur ${i + 1}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),

                        // Input IP Printer
                        Expanded(
                          child: TextField(
                            controller: dapurControllers[i],
                            decoration: const InputDecoration(
                              labelText: "IP Printer",
                              hintText: "192.168.x.x",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Tombol Ping
                        ElevatedButton(
                          onPressed: () async {
                            final ip = dapurControllers[i].text.trim();
                            if (ip.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text("IP Dapur ${i + 1} belum diisi"),
                                ),
                              );
                              return;
                            }

                            final ok = await pingPrinter(ip, port: 9100);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? "Printer $ip OK ✓"
                                    : "Printer $ip tidak dapat dihubungi ❌"),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text("Ping"),
                        ),

                        const SizedBox(width: 8),

                        // Tombol Hapus Field
                        IconButton(
                          icon: const Icon(Icons.delete_forever,
                              color: Colors.red),
                          onPressed: () {
                            setState(() {
                              dapurControllers.removeAt(i);
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Tambah Printer Dapur
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      dapurControllers.add(TextEditingController());
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text("Tambah Printer Dapur"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            const Text("USB Printer For Windows",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TextField(
              controller: usbPrinterController,
              decoration: const InputDecoration(
                labelText: "Nama Printer USB Windows",
                hintText: "Contoh: POS58 Printer",
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  setState(() => isLoading = true);
                  await _connect();
                  await _savePrinter();
                  setState(() => isLoading = false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text("Connect dan Simpan"),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openDrawer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Open Drawer"),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _testPrintBluetooth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Test Print Bluetooth"),
              ),
            ),
            const SizedBox(height: 10),
            buildPrinterTestButtons(),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _testPrintUsb,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Tes Print Windows USB"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
