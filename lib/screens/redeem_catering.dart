import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // For JSON decoding
import 'package:http/http.dart' as http;
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';

class RedeemCateringScreen extends StatefulWidget {
  const RedeemCateringScreen({super.key});

  @override
  State<RedeemCateringScreen> createState() => _RedeemCateringScreenState();
}

class _RedeemCateringScreenState extends State<RedeemCateringScreen> {
  final TextEditingController codeController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool isMemberLoaded = false;
  Map<String, dynamic>? memberData;
  Map<String, int> selectedProducts = {};
  List<Map<String, dynamic>> products = [];
  bool isLoading = false;

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<String?> getBranchFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_branch_name');
  }

  Future<String?> getDomainFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('domain');
  }

  Future<String?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('session_id');
  }

  Future<String?> getDeviceId() async {
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

  Future<String?> getCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('customer_name');
  }

  Future<void> _searchMemberAndProducts() async {
    FocusScope.of(context).unfocus();
    final code = codeController.text.trim();

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Masukkan kode atau scan terlebih dahulu"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
      isMemberLoaded = false;
      memberData = null;
      products = [];
    });

    try {
      final token = await getToken();
      final branch = await getBranchFromLocalStorage();
      final domain = await getDomainFromLocalStorage();
      final onUser = await getDeviceId();

      if (branch == null || branch.isEmpty) {
        throw Exception('Branch tidak ditemukan di local storage');
      }
      if (domain == null || domain.isEmpty) {
        throw Exception('Domain tidak ditemukan di local storage');
      }

      final uri = Uri.parse('$domain/api/catering/customer-product');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sub_branch_name': branch,
          'onuser': onUser,
          'order_id': code,
        }),
      );

      final body = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (body is Map<String, dynamic>) {
          setState(() {
            memberData = body['customer'] ??
                {
                  'name': '-',
                  'order_id': code,
                  'remainingQuota': 0,
                  'phone': '-',
                };

            final productList = (body['products'] ?? body['product']) as List?;
            products = productList != null
                ? List<Map<String, dynamic>>.from(
                    productList.map((e) => {
                          'idprod': e['idprod'].toString(),
                          'name': e['name']?.toString() ?? '-',
                        }),
                  )
                : [];

            isMemberLoaded = true;
          });
        } else {
          throw Exception('Format respons tidak valid.');
        }
      } else {
        final errorMessage = body['error'] ?? 'Gagal memuat data.';
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildMemberInfo() {
    if (!isMemberLoaded || memberData == null) return const SizedBox.shrink();

    return Card(
      color: Theme.of(context).primaryColor,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.person,
              size: 32,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memberData!['name'],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildInfoRow("Catering ID", memberData!['order_id'],
                      isBold: true),
                  _buildInfoRow(
                    "Periode Aktif",
                    "${memberData!['periode']['start_date']} s/d ${memberData!['periode']['end_date']} ",
                  ),
                  _buildInfoRow("Paket", memberData!['paket']),
                  _buildInfoRow("Telp", memberData!['phone']),
                  _buildInfoRow(
                    "Sisa Kuota",
                    "${memberData!['remainingQuota']}",
                    isBold: true,
                  ),
                  _buildInfoRow(
                    "Expired",
                    "${memberData!['periode']['expire_date']}",
                    isBold: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              "$label",
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList() {
    if (!isMemberLoaded) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            "Silakan scan atau masukkan kode terlebih dahulu",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      physics: const BouncingScrollPhysics(),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final id = (product['idprod'] ?? '').toString();
        final name = (product['name'] ?? '').toString().toUpperCase();
        final isSelected = selectedProducts.containsKey(id);
        final qty = selectedProducts[id] ?? 0;

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return AnimatedContainer(
          key: ValueKey(id),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withOpacity(0.08)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withOpacity(0.4)
                  : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: ListTile(
            leading: Checkbox(
              value: isSelected,
              activeColor: colorScheme.primary,
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    // Jika belum ada, tambahkan dengan qty = 1
                    selectedProducts[id] = 1;
                  } else {
                    // Jika di-uncheck, hapus item dari map
                    selectedProducts.remove(id);
                  }
                });
              },
            ),
            title: Text(
              name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: isSelected
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          setState(() {
                            final newQty = qty - 1;
                            if (newQty <= 0) {
                              selectedProducts.remove(id);
                            } else {
                              selectedProducts[id] = newQty;
                            }
                          });
                        },
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                          scale: animation,
                          child: child,
                        ),
                        child: Text(
                          qty.toString(),
                          key: ValueKey(qty),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          setState(() {
                            selectedProducts[id] = qty + 1;
                          });
                        },
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  void _confirmRedeem() async {
    if (!isMemberLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Silakan cari member terlebih dahulu")),
      );
      return;
    }

    if (selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Belum ada produk yang dipilih",
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
      return;
    }

    final totalRedeem = selectedProducts.values.fold<int>(0, (a, b) => a + b);
    final remainingQuota = memberData!['remainingQuota'] ?? 0;
    final domain = await getDomainFromLocalStorage();
    final device = await getDeviceId();
    final branch = await getBranchFromLocalStorage();
    final kasirId = await getUser();
    final kasirName = await getCashier();
    final token = await getToken();

    if (totalRedeem > remainingQuota) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Total redeem ($totalRedeem) melebihi sisa kuota ($remainingQuota)",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
      return;
    }

    // ✅ Konfirmasi dialog
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Konfirmasi Redeem"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Customer   : ${memberData!['name']}"),
            Text("Phone        : ${memberData!['phone']}"),
            Text("Catering ID: ${memberData!['order_id']}"),
            const Divider(),
            ...selectedProducts.entries.map((e) {
              final product =
                  products.firstWhere((p) => p['idprod'].toString() == e.key);
              return Text(
                  "• ${(product['name'] ?? '').toString().toUpperCase()} (${e.value}x)");
            }),
            const Divider(),
            Text("Total Redeem : $totalRedeem / $remainingQuota"),
            if (noteController.text.isNotEmpty) ...[
              const Divider(),
              Text("Catatan: ${noteController.text}")
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: isLoading
                ? null // disable tombol saat loading
                : () async {
                    Navigator.pop(context);
                    setState(() => isLoading = true);

                    try {
                      final uri = Uri.parse(
                          '$domain/api/catering/redeem-customer-product');
                      final response = await http.post(
                        uri,
                        headers: {
                          'Authorization': 'Bearer $token',
                          'Content-Type': 'application/json',
                        },
                        body: jsonEncode({
                          'sub_branch': branch,
                          'device': device,
                          'kasir_name': kasirName,
                          'kasir_id': kasirId,
                          'order_id': memberData!['order_id'],
                          'member_name': memberData!['name'],
                          'customer_phone': memberData!['phone'],
                          'products': selectedProducts.entries.map((e) {
                            final product = products.firstWhere(
                              (p) => p['idprod'].toString() == e.key.toString(),
                              orElse: () => {'name': 'UNKNOWN'},
                            );
                            return {
                              'idprod': e.key,
                              'product_name': product['name'],
                              'qty': e.value,
                            };
                          }).toList(),
                          'note': noteController.text,
                          'total_redeem': totalRedeem,
                        }),
                      );

                      if (response.statusCode == 200) {
                        final resBody = jsonDecode(response.body);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              resBody['message'] ?? "Redeem berhasil!",
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: Theme.of(context).primaryColor,
                          ),
                        );

                        setState(() {
                          selectedProducts.clear();
                          isMemberLoaded = false;
                        });
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Gagal redeem (${response.statusCode})",
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Terjadi kesalahan: $e",
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    } finally {
                      setState(() => isLoading = false);
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text("Konfirmasi"),
          )
        ],
      ),
    );
  }

  void _resetForm() {
    setState(() {
      codeController.clear();
      noteController.clear();
      isMemberLoaded = false;
      memberData = null;
      selectedProducts.clear();
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  void _scanCode() async {
    try {
      // Memanggil scanner fullscreen
      final barcodeScanRes = await FlutterBarcodeScanner.scanBarcode(
        '#FF6666', // warna garis scanner
        'Batal', // teks tombol batal
        true, // apakah menyalakan flash
        ScanMode.QR, // bisa juga ScanMode.BARCODE
      );

      if (barcodeScanRes != '-1') {
        // '-1' artinya user batal
        setState(() {
          codeController.text = barcodeScanRes; // masukkan ke TextField
        });
        _searchMemberAndProducts(); // langsung search
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal scan: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Redeem Catering", style: TextStyle(fontSize: 16)),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextField(
              controller: codeController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: "Scan atau masukkan kode catering",
                labelStyle: const TextStyle(fontSize: 13),
                prefixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  onPressed: _scanCode, // panggil scanner
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchMemberAndProducts,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onSubmitted: (_) => _searchMemberAndProducts(),
            ),
            _buildMemberInfo(),
            const SizedBox(height: 4),
            const Divider(height: 10),
            Expanded(child: _buildProductList()),
          ],
        ),
      ),

      // Area bawah (note + redeem button)
      bottomNavigationBar: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: isTablet ? 32 : 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMemberLoaded)
              TextField(
                controller: noteController,
                decoration: InputDecoration(
                  hintText: "Catatan (Opsional)",
                  hintStyle: const TextStyle(fontSize: 13),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.card_giftcard,
                  size: 18, color: Colors.white),
              label: const Text(
                "Redeem Sekarang",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white, // teks putih
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    Theme.of(context).primaryColor, // warna utama dari tema
                minimumSize: Size(
                    double.infinity, 44), // full lebar, tinggi proporsional
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 3,
              ),
              onPressed: _confirmRedeem,
            ),
          ],
        ),
      ),
    );
  }
}
