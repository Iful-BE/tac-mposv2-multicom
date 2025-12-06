import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TransactionDetailPage extends StatefulWidget {
  final String noStruk;

  const TransactionDetailPage({super.key, required this.noStruk});

  @override
  _TransactionDetailPageState createState() => _TransactionDetailPageState();
}

class _TransactionDetailPageState extends State<TransactionDetailPage> {
  List<Map<String, dynamic>> transactions = [];

  @override
  void initState() {
    super.initState();
    _fetchTransactionDetail();
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<String?> getDomainFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('domain');
  }

  Future<String?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('session_id');
  }

  String formatRupiah(double amount) {
    final format =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return format.format(amount);
  }

  Future<void> _fetchTransactionDetail() async {
    final token = await getToken();

    try {
      final domain = await getDomainFromLocalStorage();
      final sessionId = await getSession();

      if (domain == null || domain.isEmpty) {
        throw Exception('Domain not found in local storage');
      }

      final uri = Uri.parse('$domain/api/transaction-detail');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'struk_no': widget.noStruk, 'session_id': sessionId}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (data['data'] != null && data['data'] is List) {
          setState(() {
            transactions = List<Map<String, dynamic>>.from(data['data']);
          });
        } else {
          print("Data tidak ditemukan atau format tidak sesuai");
        }
      } else {
        print("Failed to load transactions: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching transaction: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Detail')),
      body: transactions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'No Struk: ${widget.noStruk}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: MediaQuery.of(context).size.height *
                          0.6, // Batasi tinggi agar scroll berfungsi
                      child: ListView.builder(
                        shrinkWrap: true, // Agar sesuai dengan konten
                        physics:
                            const BouncingScrollPhysics(), // Efek scrolling yang lebih natural
                        itemCount: transactions.length,
                        itemBuilder: (context, index) {
                          var transaction = transactions[index];
                          return Card(
                            child: ListTile(
                              title: Text(
                                transaction['item'].toString().toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                ' ${transaction['jumlah']} X ${transaction['harga']}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal),
                              ),
                              trailing: Text(
                                formatRupiah(
                                    transaction['sub_total'].toDouble()),
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
