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

    _branchesFuture = _getBranches();
  }

  Future<String> _getBranches() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_branch_name') ?? 'No branches available';
  }

  Future<String> _getDeviceId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id') ?? 'No Device available';
  }

  Future<void> checkAndUpdateBackend(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final nextVersion = prefs.getString('next_version') ?? '';
    final currentVersion = prefs.getString('current_version') ?? '';

    if (nextVersion.isNotEmpty && currentVersion != nextVersion) {
      final device = await _getDeviceId();
      final branches = prefs.getString('sub_branch_name') ?? '';
      final domains = prefs.getString('domain') ?? '';

      try {
        final response = await Dio().post(
          "$domains/api/update-version",
          data: {
            "sub_branch": branches,
            "device": device,
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
        if (responseData['status'] == 'success') {
          final sessionData = responseData['data'];
          await prefs.setString('user_id', sessionData['user_id']);
          await prefs.setString('session_id', sessionData['session_id']);
          await prefs.setString('role', sessionData['role']);
          await prefs.setString('cashier', sessionData['name']);
          await prefs.setString('token', sessionData['token']);

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

    try {
      final serviceVersion = await fetchServiceVersion(
        ServiceVersionRequest(
          subBranch: branches,
          device: device,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1, // Lebih soft
        centerTitle: true,
        title: const Text(
          "", // Ganti jika kosong
          style: TextStyle(
            color: Colors.black,
            fontSize: 16.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Theme.of(context).primaryColor),
            padding: const EdgeInsets.only(right: 10),
            onSelected: (value) async {
              if (value == 'printer') {
                _showPrinterSettings();
              } else if (value == 'setup') {
                _showSetup();
              } else if (value == 'sync') {
                // 🔹 Tambahkan konfirmasi sebelum sinkronisasi
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Konfirmasi Sinkronisasi"),
                    content: const Text(
                      "Apakah Anda yakin ingin melakukan sinkronisasi?\n"
                      "Data cabang lama akan dihapus.",
                    ),
                    actions: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor:
                              Theme.of(context).primaryColor.withOpacity(0.8),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Batal"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Theme.of(context).primaryColor,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Lanjut"),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  _syncData();
                }
              } else if (value.startsWith('theme_')) {
                final colorKey = value.split('_')[1];
                final selectedColor = themeColors[colorKey];
                if (selectedColor != null) {
                  ThemeController.setThemeColor(selectedColor);
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'branchInfo',
                child: FutureBuilder<String>(
                  future: _branchesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text("Memuat...");
                    } else if (snapshot.hasError) {
                      return Text(
                        "Gagal: ${snapshot.error}",
                        style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontSize: 12),
                      );
                    } else {
                      return Text(
                        snapshot.data!,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w500),
                      );
                    }
                  },
                ),
              ),
              const PopupMenuItem(
                value: 'printer',
                child:
                    Text("Pengaturan Printer", style: TextStyle(fontSize: 13)),
              ),
              const PopupMenuItem(
                value: 'sync',
                child: Text("Sinkronisasi", style: TextStyle(fontSize: 13)),
              ),
              const PopupMenuItem(
                value: 'setup',
                child: Text("Setup Aplikasi", style: TextStyle(fontSize: 13)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                child: Text(
                  "Tema Warna",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              ...themeColors.entries.map((entry) {
                return PopupMenuItem(
                  value: 'theme_${entry.key}',
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: entry.value,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                      Text(entry.key.toUpperCase(),
                          style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Theme.of(context).primaryColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Image.asset(
                    'assets/mjn-logo.png',
                    height: 70,
                    width: 70,
                  ),
                  const SizedBox(height: 12),

                  // Form Card
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // User ID Field
                            TextField(
                              controller: _userIdController,
                              style: const TextStyle(fontSize: 13.5),
                              decoration: InputDecoration(
                                labelText: 'User ID',
                                labelStyle: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontSize: 13),
                                prefixIcon: Icon(Icons.person,
                                    color: Theme.of(context).primaryColor),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                      color: Theme.of(context).primaryColor,
                                      width: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Password Field
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              style: const TextStyle(fontSize: 13.5),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontSize: 13),
                                prefixIcon: Icon(Icons.lock,
                                    color: Theme.of(context).primaryColor),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                      color: Theme.of(context).primaryColor,
                                      width: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.login, size: 18),
                                label: const Text(
                                  "Login",
                                  style: TextStyle(fontSize: 14.5),
                                ),
                                onPressed: _checkNetworkAndLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
