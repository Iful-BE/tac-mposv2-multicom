import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_custom_clippers/flutter_custom_clippers.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'sales_screen.dart';

class MemberScreen extends StatefulWidget {
  final String name;
  final int trx;
  final int point;
  final String lastRedeem;
  final String redeemLoc;
  final int rewardsCount;
  final Map<String, dynamic>? lastPts;

  const MemberScreen({
    super.key,
    required this.name,
    required this.trx,
    this.lastPts,
    required this.point,
    required this.lastRedeem, // Tambahkan ini
    required this.redeemLoc, // Tambahkan ini
    required this.rewardsCount,
  });

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  List<Map<String, dynamic>> topProducts = [];

  int skemaPoin = 0;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _skema() async {
    final prefs = await SharedPreferences.getInstance();
    // Ambil sebagai int. Jika gagal/null, beri nilai 0
    int skema = prefs.getInt('skema') ?? 0;
    if (skema == 0) {
      String? skemaString = prefs.getString('skema');
      if (skemaString != null) {
        skema = int.tryParse(skemaString) ?? 0;
      }
    }

    // debugPrint("Skema Poin (Integer): $skema");

    if (mounted) {
      setState(() {
        skemaPoin = skema;
      });
    }
  }

  Future<void> _initData() async {
    await _skema();
    _fetchCrmData();
  }

  String formatRupiah(dynamic amount) {
    if (amount == null) return "Rp 0";
    double value = double.tryParse(amount.toString()) ?? 0.0;

    final format = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return format.format(value);
  }

  String _getGreetingMessage() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) {
      return "Selamat Pagi";
    } else if (hour >= 11 && hour < 15) {
      return "Selamat Siang";
    } else if (hour >= 15 && hour < 18) {
      return "Selamat Sore";
    } else {
      return "Selamat Malam";
    }
  }

  String formatTanggalIndo(String tanggal) {
    if (tanggal == "-" || tanggal.isEmpty) return "-";

    try {
      DateTime date = DateTime.parse(tanggal);
      var bulanIndo = [
        "",
        "Januari",
        "Februari",
        "Maret",
        "April",
        "Mei",
        "Juni",
        "Juli",
        "Agustus",
        "September",
        "Oktober",
        "November",
        "Desember"
      ];

      return "${date.day} ${bulanIndo[date.month]} ${date.year}";
    } catch (e) {
      return tanggal; // Jika error balikkan tanggal asli
    }
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

  Future<String?> getPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_phone');
  }

  Future<void> _fetchCrmData() async {
    try {
      final domain = await getDomainFromLocalStorage();
      final nowa = await getPhone();
      final branch = await getBranchFromLocalStorage();
      final token = await getToken();

      if (domain == null || nowa == null) {
        print('Missing required parameters for API request.');
        return;
      }

      final url = Uri.parse('$domain/api/crm-produk');
      final body = jsonEncode({
        'nowa': nowa,
        'branch': branch,
      });

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        try {
          final jsonData = jsonDecode(response.body);

          if (jsonData['success'] == true &&
              jsonData['data'] != null &&
              jsonData['data'] is List) {
            final List data = jsonData['data'];

            setState(() {
              topProducts = data.map<Map<String, dynamic>>((item) {
                return {
                  'name': item['name']?.toString() ?? '',
                  'qty': item['qty']?.toString() ?? '0',
                };
              }).toList();
            });
          } else {
            print('Data kosong, tidak berhasil, atau bukan list.');
          }
        } catch (e) {
          print('Gagal decode JSON: $e');
        }
      } else {
        print('Gagal mengambil data CRM: ${response.statusCode}');
      }
    } catch (e) {
      print('Error saat mengambil data CRM: $e');
    }
  }

  String toTitleCase(String text) {
    if (text.isEmpty) return text;

    return text
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }

  Widget _buildInfoRow(IconData icon, String text, {Color? textColor}) {
    return Row(
      children: [
        Icon(icon,
            size: 18,
            color: textColor ?? Colors.blue[600]), // Ikon ikut berubah warna
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 16,
            color: textColor ??
                Colors.blue[700], // Jika tidak diisi, default abu-abu
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow2(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            "$label:",
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _getGreetingMessage();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      body: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipPath(
              clipper: WaveClipperOne(reverse: true),
              child: Container(
                height: 160,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  // Bagian atas: Info Poin & Transaksi
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Halo, $greeting ${toTitleCase(widget.name)} 👋",
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A202C),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF2F7),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Color(0xFFF6AD55)),
                              const SizedBox(width: 8),
                              Text(
                                "Total Poin  ${widget.point}",
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D3748),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (skemaPoin == 0) ...[
                          const SizedBox(height: 8), // Jarak antar baris
                          // BAGIAN DATA REDEEM (Data Baru)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 0), // Diperbaiki: Menggunakan .only
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                _buildInfoRow(
                                  Icons.card_giftcard,
                                  "Rewards Tersedia: ${widget.rewardsCount}",
                                  textColor: Colors.green[
                                      700], // Berikan warna hijau di sini
                                ),
                                // Baris Last Redeem (Tetap Abu-abu)
                                _buildInfoRow(
                                  Icons.history,
                                  "Last Redeem: ${formatTanggalIndo(widget.lastRedeem)}", // Gunakan formatter di sini
                                ),

                                _buildInfoRow(Icons.location_on_outlined,
                                    "Lokasi: ${widget.redeemLoc.toUpperCase()}"),
                                const SizedBox(height: 4),
                              ],
                            ),
                          ),
                        ] else if (skemaPoin == 1) ...[
                          const SizedBox(height: 8),
                          if (widget.lastPts != null)
                            Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                    color: Colors.green.shade100, width: 1),
                              ),
                              color: Colors.green.shade50.withOpacity(0.5),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.stars_rounded,
                                                color: Colors.green.shade700),
                                            const SizedBox(width: 8),
                                            const Text(
                                              "Point Terakhir Digunakan",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade700,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            "+${widget.lastPts!['point']} pts",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 24, thickness: 1),
                                    _buildInfoRow2(
                                        Icons.calendar_today_outlined,
                                        "Tanggal",
                                        formatTanggalIndo(
                                            widget.lastPts!['date'])),
                                    _buildInfoRow2(
                                      Icons.confirmation_number_outlined,
                                      "Diskon",
                                      formatRupiah(widget.lastPts?['disc']),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Text(
                                  "Belum ada transaksi point",
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          "Senang bisa bertemu denganmu lagi. Aku tau produk favoritmu.",
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF4A5568),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Column(
                          children: topProducts.map((item) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.star,
                                      color: Colors.redAccent, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "${toTitleCase(item['name'] ?? '')} (${item['qty']}x)",
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: Color(0xFF4A5568),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  // Bagian tengah: Greeting & Produk
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Produk favorit
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: 40,
                left: 24,
                right: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Yuk mulai pesan sekarang!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const SalesScreen(isSelfService: false),
                        ),
                      );
                    },
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text(
                      "Lanjutkan",
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 241, 128, 8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
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
