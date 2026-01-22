import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SetupPage(),
    );
  }
}

/// --- ENUM ---
enum Mode { retail, resto }

enum AfterTransaction { login, home }

/// --- HALAMAN SETUP ---
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  Mode? _selectedMode;
  AfterTransaction? _afterTransaction;
  bool _aktifTabel = false;
  bool _loading = false;
  String? _logoUrl; // simpan URL logo
  int? _logoWidth;
  int? _logoHeight;
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  /// --- Helper convert ---
  bool modeToBool(Mode mode) => mode == Mode.resto;
  Mode boolToMode(bool value) => value ? Mode.resto : Mode.retail;

  bool afterToBool(AfterTransaction after) => after == AfterTransaction.home;
  AfterTransaction boolToAfter(bool value) =>
      value ? AfterTransaction.home : AfterTransaction.login;

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      final modeBool = prefs.getBool("mode");
      if (modeBool != null) {
        _selectedMode = boolToMode(modeBool);
      } else {
        _selectedMode = Mode.resto; // default
      }

      final afterBool = prefs.getBool("after_transaction");
      if (afterBool != null) {
        _afterTransaction = boolToAfter(afterBool);
      } else {
        _afterTransaction = AfterTransaction.login; // default
      }

      _aktifTabel = prefs.getBool("aktif_table") ?? true;

      // load logo url
      _logoUrl = prefs.getString("logo_url");
      _logoWidth = prefs.getInt("logo_width") ?? 200; // default 200 px
      _logoHeight = prefs.getInt("logo_height"); // null = auto
      _widthController.text = _logoWidth.toString();
      _heightController.text = _logoHeight?.toString() ?? "";
    });
  }

  /// --- Save Config ---
  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // Hapus config lama
    await prefs.remove("mode");
    await prefs.remove("after_transaction");
    await prefs.remove("aktif_table");
    await prefs.remove("logo_url");
    await prefs.remove("logo_width");
    await prefs.remove("logo_height");

    // Simpan config baru
    if (_selectedMode != null) {
      await prefs.setBool("mode", modeToBool(_selectedMode!));
    }
    if (_afterTransaction != null) {
      await prefs.setBool("after_transaction", afterToBool(_afterTransaction!));
    }
    await prefs.setBool("aktif_table", _aktifTabel);

    if (_logoUrl != null && _logoUrl!.isNotEmpty) {
      await prefs.setString("logo_url", _logoUrl!);
    }

    if (_widthController.text.isNotEmpty) {
      await prefs.setInt("logo_width", int.parse(_widthController.text));
    }
    if (_heightController.text.isNotEmpty) {
      await prefs.setInt("logo_height", int.parse(_heightController.text));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Konfigurasi tersimpan")),
    );
  }

  /// --- Set Logo (hanya simpan URL, caching otomatis diatur library) ---
  Future<void> _setLogoUrl(String url) async {
    setState(() {
      _loading = true;
      _logoUrl = url;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("logo_url", url);

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        String base64Logo = base64Encode(response.bodyBytes);
        await prefs.setString("logo_base64", base64Logo);
      }
    } catch (e) {
      print("Gagal download logo untuk cache: $e");
    }

    setState(() {
      _loading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Logo URL berhasil disimpan")),
    );
  }

  /// --- Widget Logo ---
  Widget _buildLogo() {
    if (_logoUrl == null) {
      return const Text("Belum ada logo diset");
    }

    return CachedNetworkImage(
      imageUrl: _logoUrl!,
      placeholder: (context, url) =>
          const CircularProgressIndicator(strokeWidth: 2),
      errorWidget: (context, url, error) => const Icon(Icons.error),
      width: 100,
      height: 100,
      fit: BoxFit.contain,
    );
  }

  Future<String?> getDomainFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('domain');
  }

  Future<String> _getBranches() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_branch_name') ?? 'No branches available';
  }

  Future<Map<String, dynamic>?> fetchLogo() async {
    final domain = await getDomainFromLocalStorage();
    final subBranch = await _getBranches();
    final url = Uri.parse("$domain/api/app-logo");

    try {
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "sub_branch": subBranch,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == true) {
          return data['data'];
        }
      }
    } catch (e) {
      //debugPrint("Error fetchLogo: $e");
    }

    return null;
  }

  /// --- Build UI ---
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final contentWidth = isTablet ? (screenWidth / 2) - 32 : screenWidth;

    return Scaffold(
      appBar: AppBar(title: const Text("Pengaturan POS")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Flex(
          direction: isTablet ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            /// --- KIRI ---
            SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Pilih Mode:",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  RadioListTile<Mode>(
                    title: const Text("Retail"),
                    value: Mode.retail,
                    groupValue: _selectedMode,
                    onChanged: (value) => setState(() => _selectedMode = value),
                  ),
                  RadioListTile<Mode>(
                    title: const Text("Resto"),
                    value: Mode.resto,
                    groupValue: _selectedMode,
                    onChanged: (value) => setState(() => _selectedMode = value),
                  ),
                  CheckboxListTile(
                    title: const Text("Manage Table"),
                    value: _aktifTabel,
                    onChanged: (value) =>
                        setState(() => _aktifTabel = value ?? false),
                  ),
                ],
              ),
            ),

            if (isTablet) const SizedBox(width: 32, height: 16),

            /// --- KANAN ---
            SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center, // <- tengah
                children: [
                  const Text(
                    "Setelah Transaksi:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  RadioListTile<AfterTransaction>(
                    title: const Text("Kembali ke Login"),
                    value: AfterTransaction.login,
                    groupValue: _afterTransaction,
                    onChanged: (value) =>
                        setState(() => _afterTransaction = value),
                  ),
                  RadioListTile<AfterTransaction>(
                    title: const Text("Kembali ke Home"),
                    value: AfterTransaction.home,
                    groupValue: _afterTransaction,
                    onChanged: (value) =>
                        setState(() => _afterTransaction = value),
                  ),
                  const SizedBox(height: 24),

                  /// --- LOGO SECTION ---
                  Column(
                    children: [
                      _buildLogo(), // tampilkan logo terakhir yang tersimpan
                      const SizedBox(height: 12),

                      // Input width
                      TextField(
                        controller: _widthController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Lebar Logo (px)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Input height
                      TextField(
                        controller: _heightController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Tinggi Logo (px) - kosongkan biar auto",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      ElevatedButton.icon(
                        onPressed: _loading
                            ? null
                            : () async {
                                setState(() => _loading = true);

                                final logoData = await fetchLogo();
                                final logoUrl = logoData?['logo'];

                                if (logoUrl != null &&
                                    logoUrl is String &&
                                    logoUrl.isNotEmpty) {
                                  await _setLogoUrl(logoUrl); // update + simpan
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Logo tidak ditemukan di response')),
                                  );
                                }

                                setState(() => _loading = false);
                              },
                        icon: const Icon(Icons.image, color: Colors.white),
                        label: Text(
                          _loading ? "Menyimpan..." : "Set Logo",
                          style: const TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  /// --- SIMPAN CONFIG BUTTON ---
                  ElevatedButton.icon(
                    onPressed: _saveConfig,
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text(
                      "Simpan Konfigurasi",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
