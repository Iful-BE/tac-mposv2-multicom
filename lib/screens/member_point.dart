import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mposv2/screens/home_screen.dart';
import 'package:mposv2/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

Future<bool?> showMemberPointDialog(BuildContext context, bool after) async {
  final data = await _fetchCrmData();

  return await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true, // ✅ muncul di atas loading
    builder: (BuildContext context) {
      return AlertDialog(
        content: data != null
            ? _MemberPointContent(data: data)
            : const Padding(padding: EdgeInsets.all(20)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              // ✅ Kembalikan nilai, jangan navigate di sini
              Navigator.of(context, rootNavigator: true).pop(true);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                "Tutup",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

Future<Map<String, dynamic>?> _fetchCrmData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final domain = prefs.getString('domain');
    final nowa = prefs.getString('user_phone');
    final token = prefs.getString('token');

    if (domain == null || nowa == null || token == null) return null;

    final url = Uri.parse('$domain/api/update-point');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'nowa': nowa}),
    );

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      if (jsonData['success'] == true && jsonData['data'] != null) {
        return jsonData['data'];
      }
    }
    return null;
  } catch (e) {
    debugPrint("Error fetch CRM data: $e");
    return null;
  }
}

//kembali ke awal
Future<bool?> afterTrx() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('after_transaction');
}

/// 🔹 Widget isi dialog dengan data langsung ditampilkan
class _MemberPointContent extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MemberPointContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] ?? 'Member';
    final trx = data['trx']?.toString() ?? '-';
    final point = int.tryParse(data['total_point']?.toString() ?? '0') ?? 0;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.card_giftcard, color: Colors.orange, size: 60),
          const SizedBox(height: 10),
          Text(
            "Hi $name !",
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Transaksi ke-$trx hari ini",
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Text(
            "Total Poin: $point",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (point == 10)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE6FFFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF38B2AC)),
              ),
              child: Text(
                "🎉 Selamat $name, Berhak mendapatkan free 1 Product 🎁, karena sudah mengumpulkan 10 poin!",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF285E61),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
