import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mposv2/force_update_dialog.dart';
import 'package:mposv2/screens/branch_form.dart';
import 'package:mposv2/screens/printer_settings_screen.dart';
import 'package:mposv2/screens/setup.dart';
import 'package:mposv2/service_version.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'home_screen.dart';
import 'dart:convert'; // For JSON encoding/decoding
import 'package:http/http.dart' as http;
import '../theme_controller.dart'; // atau sesuaikan path-nya
import 'package:wakelock/wakelock.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
//import 'package:install_plugin/install_plugin.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isCheckingVersion = true;
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  Future<String>? _branchesFuture;
  String _savedSubDevice = '';
  String? _logoUrl;
  int? _logoWidth;
  int? _logoHeight;
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  static const String noInternetMessage =
      "No internet connection. Please check your network.";
  static const String invalidCredentialsMessage = "Invalid Credentials";

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await checkAndUpdateBackend(context);
      await _checkVersionOnAppStart();

      if (mounted) {
        setState(() => isCheckingVersion = false);
      }
    });
    _loadSubDevice();

    _branchesFuture = _getBranches();
  }

  void _loadSubDevice() async {
    final result = await _getSubDevice();
    setState(() {
      _savedSubDevice = result.trim();
    });
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      // load logo url
      _logoUrl = prefs.getString("logo_url");
      _logoWidth = prefs.getInt("logo_width") ?? 200; // default 200 px
      _logoHeight = prefs.getInt("logo_height"); // null = auto
      _widthController.text = _logoWidth.toString();
      _heightController.text = _logoHeight?.toString() ?? "";
    });
  }

  /// --- Set Logo (hanya simpan URL, caching otomatis diatur library) ---

  /// --- Widget Logo ---
  Widget _buildLogo() {
    // Mengambil warna utama yang sedang aktif (Blue, Green, Red, dll)
    final primaryColor = Theme.of(context).primaryColor;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // LOGO 1: Logo MJN (Selalu dari Assets)
        Image.asset(
          'assets/mjn-logo.png',
          height: 45,
          width: 45,
          // Jika asset tidak ketemu, tampilkan icon dengan warna tema
          errorBuilder: (c, e, s) =>
              Icon(Icons.flash_on, size: 40, color: primaryColor),
        ),

        // Tanda "x" di tengah
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            "x",
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // LOGO 2: Logo dari Setup (Cached Network Image)
        SizedBox(
          width: 45,
          height: 45,
          child: (_logoUrl == null || _logoUrl!.isEmpty)
              ? Icon(
                  Icons.business,
                  size: 40,
                  color: primaryColor, // Warna icon gedung sesuai tema
                )
              : CachedNetworkImage(
                  imageUrl: _logoUrl!,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            primaryColor), // Warna loading sesuai tema
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) {
                    return Icon(Icons.business,
                        size: 40,
                        color: primaryColor); // Warna icon error sesuai tema
                  },
                ),
        ),
      ],
    );
  }

  Future<String> _getBranches() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_branch_name') ?? 'No branches available';
  }

  Future<String> _getDeviceId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id') ?? 'No Device available';
  }

  Future<String> _getSubDevice() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_device') ?? '';
  }

  Future<void> checkAndUpdateBackend(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final nextVersion = prefs.getString('next_version') ?? '';
    final currentVersion = prefs.getString('current_version') ?? '';

    if (nextVersion.isNotEmpty && currentVersion != nextVersion) {
      final device = await _getDeviceId();
      final subDevice = await _getSubDevice();
      final branches = prefs.getString('sub_branch_name') ?? '';
      final domains = prefs.getString('domain') ?? '';

      try {
        final response = await Dio().post(
          "$domains/api/update-version",
          data: {
            "sub_branch": branches,
            "device": device,
            "sub_device": subDevice,
            "version": nextVersion,
          },
        );

        if (response.statusCode == 200) {
          //debugPrint("Backend update sukses.");
          await prefs.setString('current_version', nextVersion);
          prefs.remove('next_version');

          if (context.mounted) {
            // Tampilkan popup dengan changelog
            final changelog =
                response.data['changelog'] ?? 'Tidak ada catatan perubahan.';
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(
                  "Aplikasi berhasil diupdate ke versi $nextVersion",
                  style: const TextStyle(
                    fontSize: 14, // ukuran title lebih kecil
                    fontWeight: FontWeight.w600,
                  ),
                ),
                content: SingleChildScrollView(
                  child: Text(changelog),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Tutup"),
                  ),
                ],
              ),
            );
          }
        } else {
          //debugPrint("Backend update gagal, status: ${response.statusCode}");
        }
      } catch (e) {
        //debugPrint("Error update backend: $e");
      }
    }
  }

  Future<void> _checkNetworkAndLogin() async {
    FocusScope.of(context).unfocus();
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      _showError(noInternetMessage);
      return;
    }
    await _login();
  }

  Future<void> _login() async {
    final userId = _userIdController.text.trim();
    final password = _passwordController.text.trim();
    final device = await _getDeviceId();

    if (userId.isEmpty || password.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final branches = prefs.getString('sub_branch_name') ?? '';
    final domains = prefs.getString('domain') ?? '';

    try {
      final uri = Uri.parse('$domains/api/login');
      final response = await http.post(uri, body: {
        "id_user": userId,
        "password": password,
        "sub_branch": branches.toLowerCase(),
        "device": device.toLowerCase(),
      });

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        //debugPrint(responseData.toString());
        if (responseData['status'] == 'success') {
          final sessionData = responseData['data'];
          await prefs.setString('user_id', sessionData['user_id']);
          await prefs.setString('session_id', sessionData['session_id']);
          await prefs.setString('role', sessionData['role']);
          await prefs.setString('cashier', sessionData['name']);
          await prefs.setString('token', sessionData['token']);
          await prefs.setInt('skema', sessionData['skema']);

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          _showError(responseData['message'] ?? invalidCredentialsMessage);
        }
      } else {
        _showError(invalidCredentialsMessage);
      }
    } catch (e) {
      _showError("Terjadi kesalahan. Coba lagi.");
    }
  }

  Future<void> _checkVersionOnAppStart() async {
    final prefs = await SharedPreferences.getInstance();
    final branches = prefs.getString('sub_branch_name') ?? '';
    final device = await _getDeviceId();
    final subDevice = await _getSubDevice();

    try {
      final serviceVersion = await fetchServiceVersion(
        ServiceVersionRequest(
          subBranch: branches,
          device: device,
          subDevice: subDevice,
        ),
      );

      if (serviceVersion != null) {
        await prefs.setString('latest_version', serviceVersion.latestVersion);

        if (serviceVersion.upToDate == false && mounted) {
          // 🚨 Jika ada update → blokir sampai update
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => ForceUpdateDialog(
              downloadUrl: serviceVersion.apkUrl,
              latestVersion: serviceVersion.latestVersion,
              currentVersion: serviceVersion.currentVersion,
            ),
          );
        }
      }
    } catch (e) {
      // bisa diamkan agar tidak ganggu saat startup
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  void _showPrinterSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PrinterSettingsScreen()),
    );
  }

  void _showSetup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SetupPage()),
    );
  }

  void _syncData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('sub_branch_name');
    await prefs.remove('branch_name');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Sinkronisasi selesai. Data cabang telah dihapus."),
      ),
    );

    // Reload halaman dengan pushReplacement
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => BranchFormScreen()),
    );
  }

  final Map<String, Color> themeColors = {
    'Red': Colors.red,
    'Blue': Colors.blue,
    'Sky': const Color(0xFF4CB5F5),
    'Navy': const Color(0xFF375E97),
    'Ocean': const Color(0xFF4897D8),
    'Stone': const Color(0xFF336B87),
    'Teal': Colors.teal,
    'Green1': Colors.green,
    'Green2': const Color(0xffa438210),
    'Green3': const Color.fromARGB(255, 8, 76, 10),
    'Gold': const Color.fromARGB(255, 194, 175, 3),
    'Bubblegum': const Color(0xFFF18D9E),
    'Seeds': const Color(0xFFBA5536),
    'Seeds1': const Color(0xFFDE7A22),
    'Seeds2': const Color(0xFFF69454),
    'Palm': const Color(0xFFEE693F),
    'Orange': Colors.orange,
    'Yellow': const Color(0xFFC9A66B),
    'Coffee': const Color(0xFF46211A),
    'Ceramic': const Color(0xFF505160),
    'Blueberry': const Color(0xFF07575B),
    'Basil': const Color(0xFF2E4600),
    'Steal Blue': const Color(0xFF063852),
    'Mist': const Color(0xFF8593AE),
    'Blush': const Color(0xFF7E675E),
    'Pink': Colors.pink,
  };
  void _showModernActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar (Indikator Geser)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10)),
            ),

            // Informasi Cabang (Header)
            _buildBranchHeader(),

            const Divider(height: 1),

            // List Menu Utama
            _buildMenuTile(
                icon: Icons.print_rounded,
                title: "Pengaturan Printer",
                onTap: () {
                  Navigator.pop(context);
                  _showPrinterSettings();
                }),
            _buildMenuTile(
                icon: Icons.sync_rounded,
                title: "Sinkronisasi Data",
                color: Colors.blueAccent,
                onTap: () {
                  Navigator.pop(context);
                  _handleSyncAction(context);
                }),
            _buildMenuTile(
                icon: Icons.settings_suggest_rounded,
                title: "Setup Aplikasi",
                onTap: () {
                  Navigator.pop(context);
                  _showSetup();
                }),

            const Divider(),

            // Pemilih Tema (Horizontal Scroll agar lebih compact)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Tema Warna",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.grey))),
            ),
            SizedBox(
              height: 70,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: themeColors.entries
                    .map((entry) => _buildThemeCircle(entry.key, entry.value))
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile(
      {required IconData icon,
      required String title,
      required VoidCallback onTap,
      Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.black87),
      title: Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildThemeCircle(String name, Color color) {
    return InkWell(
      onTap: () => ThemeController.setThemeColor(color),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12)),
            ),
            const SizedBox(height: 4),
            Text(name.toUpperCase(), style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchHeader() {
    return FutureBuilder<String>(
      future: _branchesFuture,
      builder: (context, snapshot) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const CircleAvatar(child: Icon(Icons.storefront_rounded)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  snapshot.data ?? "Memuat info cabang...",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSyncAction(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text("Sinkronisasi"),
          ],
        ),
        content: const Text(
            "Apakah Anda yakin? Data cabang lama akan digantikan dengan data terbaru dari server."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Batal", style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sinkronkan Sekarang"),
          ),
        ],
      ),
    );

    if (confirm == true) _syncData();
  }

  @override
  Widget build(BuildContext context) {
    // Mengambil warna utama dari tema yang aktif
    bool isTablet = MediaQuery.of(context).size.width > 600;
    double bottomPadding = MediaQuery.of(context).padding.bottom;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      // 1. Tambahkan ini agar body naik ke atas melewati AppBar
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        title: const Text(
          "",
          style: TextStyle(
              color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded,
                color: Colors.white), // Icon lebih modern
            onPressed: () => _showModernActionMenu(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          // HEADER BACKGROUND DENGAN GAMBAR
          Container(
            height:
                MediaQuery.of(context).size.height * (isTablet ? 0.60 : 0.65),
            width: double.infinity,
            decoration: BoxDecoration(
              color: primaryColor,
              image: DecorationImage(
                image: const AssetImage('assets/bg-pattern.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  primaryColor.withOpacity(0.55),
                  BlendMode.dstATop,
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // --- HEADER DENGAN LOGO DI SEBELAH KIRI TEKS ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment
                        .center, // Logo dan Teks sejajar tengah secara vertikal
                    children: [
                      // LOGO 1: MJN (Selalu dari Assets)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.asset(
                          'assets/mjn-logo.png',
                          height: 45,
                          width: 45,
                          errorBuilder: (c, e, s) => const Icon(Icons.flash_on,
                              color: Colors.white, size: 40),
                        ),
                      ),

                      const SizedBox(width: 15), // Jarak antara logo dan teks

                      // GRUP TEKS (MULTIPOS & Slogan)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "MULTIPOS",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize:
                                    34, // Sedikit disesuaikan agar pas dengan logo
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.0,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              "Smart Solutions for Modern Trade",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize:
                                    14, // Ukuran font sub-judul lebih proporsional
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      children: [
                        const SizedBox(width: 6),
                        // Container(
                        //   height: 4,
                        //   width: 10,
                        //   decoration: BoxDecoration(
                        //     color: Colors.white.withOpacity(0.4),
                        //     borderRadius: BorderRadius.circular(10),
                        //   ),
                        // ),
                        Text(
                          "Make every transaction effortless.",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 18,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isTablet ? 40 : 140),
                  Align(
                    alignment:
                        isTablet ? Alignment.center : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 500,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          // Agar isi di dalam card tetap konsisten rata kiri
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Status SubDevice
                            if (_savedSubDevice.isNotEmpty) ...[
                              Text(
                                _savedSubDevice,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],

                            // INPUT USER ID
                            TextField(
                              controller: _userIdController,
                              decoration: InputDecoration(
                                hintText: 'User ID',
                                prefixIcon: Icon(Icons.person_outline,
                                    color: primaryColor),
                                filled: true,
                                fillColor: Colors.grey[100],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // INPUT PASSWORD
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                hintText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline,
                                    color: primaryColor),
                                filled: true,
                                fillColor: Colors.grey[100],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),

                            const SizedBox(height: 25),

                            // TOMBOL LOGIN
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton(
                                onPressed: _checkNetworkAndLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: const Text(
                                  "Login",
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(
                      height: isTablet
                          ? 20
                          : 50), // Jarak yang cukup agar tampilan "napas"

                  // --- FOOTER SECTION ---
                  SizedBox(height: isTablet ? 40 : 20),

                  // --- FOOTER SECTION ---
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Garis halus pembatas

                        Text(
                          "© 2024 MULTIPOS",
                          style: TextStyle(
                            // Tips: Gunakan putih jika background gelap, hitam jika terang
                            color: Colors.black.withOpacity(0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),

                        Text(
                          "Powered by MJM Digital Solution. All rights reserved.",
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 0.5,
                          ),
                        ),

                        SizedBox(height: 30 + bottomPadding),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
