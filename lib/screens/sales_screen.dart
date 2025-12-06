import 'dart:ui';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:mposv2/screens/CartItemScreen.dart';
import 'package:mposv2/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item_test.dart';
import 'dart:convert'; // For JSON decoding
import 'package:http/http.dart' as http; // For API requests

class SalesScreen extends StatefulWidget {
  final String? antrianId;
  const SalesScreen({
    super.key,
    this.isSelfService = false,
    this.antrianId,
  });
  final bool isSelfService;

  @override
  _SalesScreenState createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<CartItem> availableProducts = [];
  List<CartItem> cartItems = [];
  List<String> categories = ["ALL"];
  String searchQuery = '';
  String selectedCategory = "ALL";
  String _orderType = '';
  bool isLoading = false;
  int totalQuantity = 0;
  final TextEditingController _searchController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _longPressTimer;
  final PageController _pageController = PageController();
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadOrderType();
    _fetchCategory();
    _fetchProducts();
    fetchTotalQuantity();
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _longPressTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOrderType() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _orderType = prefs.getString('orderType')?.toLowerCase() ?? 'dine in';
    });
  }

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

  Future<String?> getTable() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_table');
  }

  Future<String?> getArea() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_Area');
  }

  Future<String?> TotalGuest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('total_guest');
  }

  Future<bool?> getCrm() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('aktif_table'); // true = resto, false = retail
  }

  Future<String?> getorderType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('orderType');
  }

// Fetch categories from API
  Future<void> _fetchCategory() async {
    final prefs = await SharedPreferences.getInstance();

    // 🔹 Ambil orderType dari local storage
    final orderType = prefs.getString('orderType') ?? 'DINE IN';

    setState(() {
      isLoading = true;
    });

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

      final uri = Uri.parse('$domain/api/category');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sub_branch_name': branch}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body)['data'];

        List<String> filteredCategories;

        if (orderType.toLowerCase() == 'catering') {
          // 🔸 Jika CATERING → tampilkan hanya kategori yang mengandung "catering"
          filteredCategories = data
              .where((item) => item['category_name']
                  .toString()
                  .toLowerCase()
                  .contains('catering'))
              .map((item) => item['category_name'].toString().toUpperCase())
              .toList();
        } else {
          // 🔸 Jika bukan catering → tampilkan semua kecuali yang mengandung "catering"
          filteredCategories = ["ALL"] +
              data
                  .where((item) => !item['category_name']
                      .toString()
                      .toLowerCase()
                      .contains('catering'))
                  .map((item) => item['category_name'].toString().toUpperCase())
                  .toList();
        }

        setState(() {
          categories = filteredCategories;
        });
      } else {
        print("Failed to load categories: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching categories: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _fetchProducts() async {
    setState(() {
      isLoading = true;
    });

    const String token =
        '6XCkiyLZUFFxomPkxyeliAedIrvMvFoNibXRlinY73710468'; // Ambil token user dari storage
    final branch = await getBranchFromLocalStorage();
    final domain = await getDomainFromLocalStorage();
    final onUser = await getDeviceId();

    if (branch == null || branch.isEmpty) {
      throw Exception('Branch not found in local storage');
    }
    if (domain == null || domain.isEmpty) {
      throw Exception('Domain not found in local storage');
    }

    final uri = Uri.parse('$domain/api/product');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sub_branch_name': branch, 'onuser': onUser}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          availableProducts = data.map((item) {
            return CartItem(
              name: item['name'].toString().toUpperCase(),
              initial_product: item['initial_product'].toString().toLowerCase(),
              quantity: 1,
              price: (item['price'] as num).toDouble(),
              category_name: item['category_name'] ?? '',
              picture: item['picture'] ?? '',
              princo: item['print_co'] ?? '',
              category: item['category'] ?? '',
              is_sold: item['is_sold'] ?? 0,
              is_variant: item['is_variant'] ?? 0,
            );
          }).toList();
        });
      } else {
        print("Failed to load products: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching products: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Fetch total quantity from API
  Future<void> fetchTotalQuantity() async {
    final branch = await getBranchFromLocalStorage();
    final domain = await getDomainFromLocalStorage();
    final sessionId = await getSession();
    final kasirId = await getUser();
    final antrianId = widget.antrianId ?? '';
    final token = await getToken();

    if (domain == null || branch == null || sessionId == null) {
      print('Missing required parameters for API request.');
      return;
    }
    final body = jsonEncode({
      'session_id': sessionId,
      'sub_branch': branch,
      'antrian': antrianId,
      'user_id': kasirId
    });

    final url = Uri.parse("$domain/api/getCountItems");
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          totalQuantity = data['total_quantity'] ?? 0;
        });
        //print(" total quantity: $totalQuantity");
      } else {
        print("Failed to fetch total quantity: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching total quantity: $e");
    }
  }

  Future<void> _scanBarcode() async {
    while (true) {
      try {
        String barcodeScanRes = await FlutterBarcodeScanner.scanBarcode(
          "#ff6666", // Warna garis pemindai
          "Batal",
          true,
          ScanMode.BARCODE,
        );

        if (barcodeScanRes == "-1") {
          break; // Pengguna membatalkan scan, keluar dari loop
        }

        // Ambil data produk dari API
        final product = await fetchProductBySKU(barcodeScanRes);

        if (product != null) {
          setState(() {
            _searchController.text = barcodeScanRes;
          });

          await addToCart(product);

          // Mainkan suara jika berhasil
          await _audioPlayer.play(AssetSource('store.wav'));
        } else {
          // Mainkan suara error
          await _audioPlayer.play(AssetSource('error.wav'));

          print("Produk tidak ditemukan untuk SKU: $barcodeScanRes");
        }
      } catch (e) {
        print("Gagal memindai: $e");
      }
    }
  }

  Future<CartItem?> fetchProductBySKU(String sku) async {
    final token = await getToken();
    final domain = await getDomainFromLocalStorage();
    final subBranch = await getBranchFromLocalStorage();

    if (domain == null) {
      print('Domain tidak ditemukan');
      return null;
    }

    final url = Uri.parse('$domain/api/product-sku');
    final body = jsonEncode({
      'sku': sku,
      'sub_branch_name': subBranch,
    });

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        if (data.isNotEmpty) {
          final product = data[0]; // Ambil produk pertama dari list
          return CartItem(
            initial_product: product['initial_product'],
            name: product['name'],
            price: (product['price'] as num).toDouble(), // Konversi ke double
            quantity: 1,
            category_name: product['category_name'] ?? '',
            picture: product['picture'] ?? '',
            princo: product['print_co'] ?? '',
            category: product['category'] ?? '',
            // Pastikan tidak null
          );
        }
      }

      print('Produk tidak ditemukan: ${response.statusCode}');
      print('Response body: ${response.body}');
      return null;
    } catch (e) {
      print('Error mengambil data produk: $e');
      return null;
    }
  }

  Future<void> addToCart(CartItem item,
      {Map<String, dynamic>? variant, String? noteItem}) async {
    final mgTable = await getCrm();

    if (mgTable != true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_table');
      await prefs.remove('selected_area');
    }
    final token = await getToken();
    final domain = await getDomainFromLocalStorage();
    final subBranch = await getBranchFromLocalStorage();
    final deviceId = await getDeviceId();
    final sessionId = await getSession();
    final cashier = await getCashier();
    final cashierId = await getUser();
    final custName = await getCustomer();
    final antrianId = widget.antrianId ?? '';
    final custTable = await getTable() ?? '';
    final totalGuest = await TotalGuest() ?? '';
    final custArea = await getArea() ?? '';
    final orderType = await getorderType();

    if (domain == null || subBranch == null) {
      print('Domain or Sub-Branch not found');
      return;
    }

    final url = Uri.parse('$domain/api/add-to-cart');
    final body = {
      'product_id': item.initial_product.toString(),
      'name': item.name.toLowerCase(),
      'price': item.price,
      'quantity': item.quantity,
      'user': deviceId,
      'session_pos': sessionId,
      'sub_branch': subBranch,
      'print_co': item.princo,
      'antrian': antrianId,
      'cashier': cashier,
      'cashierId': cashierId,
      'customer': custName,
      'custtable': custTable,
      'guest': totalGuest,
      'typeOrder': orderType,
      'variant': variant,
      'item_note': noteItem,
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        setState(() {
          totalQuantity += item.quantity; // langsung tambahkan tanpa refetch
        });
      } else {
        print('Failed to add to cart: ${response.statusCode}');
      }
    } catch (e) {
      print('Error adding to cart: $e');
    }
  }

  void _search(String query) {
    setState(() {
      searchQuery = query;
    });
  }

  void _filterByCategory(String category) {
    final index = categories.indexOf(category);
    setState(() {
      selectedCategory = category;
      selectedIndex = index;
    });
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Widget _buildProductCard(CartItem product, NumberFormat currencyFormat) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: product.picture.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: product.picture,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.broken_image,
                              size: 40, color: Colors.grey)),
                    )
                  : Container(
                      width: double.infinity,
                      color: Theme.of(context).primaryColor,
                      child: const Icon(
                        Icons.shopping_bag,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                // HARGA PRODUK
                Expanded(
                  child: Text(
                    currencyFormat
                        .format(product.price)
                        .replaceAll(RegExp(r',\d+'), ''),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D5720),
                    ),
                  ),
                ),

                if (product.is_sold.toString() == "1") ...[
                  const Icon(Icons.block, size: 14, color: Colors.red),
                  const SizedBox(width: 2),
                  const Text(
                    "SOLD",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Future<Map<String, Map<String, dynamic>>?> showVariantSelector(
      String productId) async {
    final token = await getToken();
    final domain = await getDomainFromLocalStorage();
    final subBranch = await getBranchFromLocalStorage();

    if (domain == null) {
      print('Domain tidak ditemukan');
      return null;
    }

    final url = Uri.parse('$domain/api/master-variant');
    final body = jsonEncode({
      'product': productId,
      'sub_branch': subBranch,
    });

    List<Map<String, dynamic>> variants = [];

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['variants'] != null) {
          variants = List<Map<String, dynamic>>.from(data['variants']);
        }
      } else {
        print('Produk tidak ditemukan: ${response.statusCode}');
        print('Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error mengambil data produk: $e');
      return null;
    }

    // Grouping variants by 'group'
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var v in variants) {
      final groupName = v['group'] as String;
      grouped.putIfAbsent(groupName, () => []);
      grouped[groupName]!.add(v);
    }

    final Map<String, Map<String, dynamic>?> selectedVariants = {};

    return showModalBottomSheet<Map<String, Map<String, dynamic>>>(
      context: context,
      backgroundColor: Colors.grey[50],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pilih Variant',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: grouped.entries.map((entry) {
                        final groupName = entry.key;
                        final items = entry.value;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(
                                groupName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigoAccent,
                                ),
                              ),
                            ),
                            ...items.map((v) {
                              final isSelected =
                                  selectedVariants[groupName] == v;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    selectedVariants[groupName] = v;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8.0, horizontal: 12.0),
                                  margin: const EdgeInsets.only(bottom: 4.0),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.lightBlue[50]
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          v['variant_name'],
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isSelected
                                                ? Colors.blueGrey
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                      Radio<Map<String, dynamic>>(
                                        value: v,
                                        groupValue: selectedVariants[groupName],
                                        onChanged: (value) {
                                          setState(() {
                                            selectedVariants[groupName] = value;
                                          });
                                        },
                                        activeColor:
                                            Theme.of(context).primaryColor,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const Divider(height: 1, color: Colors.grey),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (selectedVariants.values.every((v) => v == null)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Pilih minimal 1 variant.'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }
                      final result =
                          Map<String, Map<String, dynamic>>.fromEntries(
                        selectedVariants.entries
                            .where((e) => e.value != null)
                            .map(
                              (e) => MapEntry(e.key, e.value!),
                            ),
                      );
                      Navigator.pop(context, result);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child:
                        const Text('Lanjutkan', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openNotePopup(product) async {
    TextEditingController noteController = TextEditingController();

    final noteText = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Catatan"),
          content: TextField(
            controller: noteController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: "Contoh: Tidak pedas, sambal dipisah...",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white, // warna teks
                backgroundColor:
                    Theme.of(context).primaryColor, // opsional: warna tombol
              ),
              onPressed: () =>
                  Navigator.pop(context, noteController.text.trim()),
              child: const Text("Lanjutkan"),
            ),
          ],
        );
      },
    );

    if (noteText != null && noteText.isNotEmpty) {
      await addToCart(product, noteItem: noteText);
      fetchTotalQuantity();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp');
    final screenWidth = MediaQuery.of(context).size.width;
    final orientation = MediaQuery.of(context).orientation;

// Deteksi tablet
    final isTablet = screenWidth >= 600;

    int crossAxisCount;

// Breakpoint default
    if (screenWidth < 800) {
      crossAxisCount = 2;
    } else if (screenWidth >= 800 && screenWidth < 900) {
      crossAxisCount = 5;
    } else if (screenWidth >= 900 && screenWidth < 1200) {
      crossAxisCount = 5;
    } else {
      crossAxisCount = 6;
    }

    if (isTablet) {
      if (orientation == Orientation.landscape) {
        crossAxisCount = 6; // tablet horizontal maksimal
      } else {
        crossAxisCount = 4; // tablet vertical lebih sedikit
      }
    }

    return WillPopScope(
        onWillPop: () async {
          return !widget.isSelfService;
        },
        child: Scaffold(
          backgroundColor: Colors.grey[100],
          body: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onLongPressStart: (_) {
                          _longPressTimer =
                              Timer(const Duration(seconds: 1), () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const HomeScreen()),
                            );
                          });
                        },
                        onLongPressEnd: (_) {
                          _longPressTimer?.cancel();
                        },
                        child: const Icon(Icons.search,
                            size: 16, color: Colors.grey),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onTap: () {
                            _searchController.selection = TextSelection(
                              baseOffset: 0,
                              extentOffset: _searchController.text.length,
                            );
                          },
                          onChanged: _search,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: "Cari product",
                            hintStyle:
                                TextStyle(fontSize: 14, color: Colors.grey),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                onPressed: totalQuantity > 0
                                    ? () async {
                                        final subBranch =
                                            await getBranchFromLocalStorage();
                                        final sessionId = await getSession();
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                CartItemScreen(
                                              sessionId: sessionId.toString(),
                                              subBranch: subBranch.toString(),
                                              isSelfService:
                                                  widget.isSelfService,
                                              antrianId: widget.antrianId,
                                            ),
                                          ),
                                        ).then((_) => fetchTotalQuantity());
                                      }
                                    : null,
                                icon: Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 24,
                                  color: Theme.of(context).primaryColor,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              if (totalQuantity > 0)
                                Positioned(
                                  left: -8,
                                  top: -8,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      totalQuantity
                                          .toString(), // ← nilai dinamis
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      // IconButton(
                      //   padding: EdgeInsets.zero,
                      //   constraints:
                      //       const BoxConstraints(minWidth: 28, minHeight: 28),
                      //   icon: const Icon(Icons.qr_code_scanner, size: 18),
                      //   onPressed: _scanBarcode,
                      // ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const HomeScreen()),
                            (route) => false,
                          );
                        },
                        child: Stack(
                          children: [
                            Icon(Icons.home,
                                size: 28,
                                color: Theme.of(context).primaryColor),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Category Buttons
              SizedBox(
                height: 38,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = selectedIndex == index;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(
                          category,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Theme.of(context).primaryColor,
                        backgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onSelected: (_) {
                          setState(() {
                            selectedIndex = index;
                          });
                          _pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: categories.length,
                  onPageChanged: (index) {
                    setState(() {
                      selectedIndex = index;
                      selectedCategory = categories[index];
                    });
                  },
                  itemBuilder: (context, pageIndex) {
                    final currentCategory = categories[pageIndex];
                    final currentCategoryLower = currentCategory.toLowerCase();

                    final filteredProducts = availableProducts.where((product) {
                      final productCategory =
                          product.category_name.toLowerCase();
                      final matchSearch = product.name
                          .toLowerCase()
                          .contains(searchQuery.toLowerCase());
                      if (_orderType == 'catering') {
                        return productCategory.contains('catering') &&
                            matchSearch;
                      }

                      final matchCategory = currentCategory == "ALL" ||
                          productCategory == currentCategoryLower;

                      return !productCategory.contains('catering') &&
                          matchCategory &&
                          matchSearch;
                    }).toList();

                    return GridView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: isTablet ? 0.95 : 1.05,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];

                        return Stack(
                          children: [
                            // =============================
                            // CARD PRODUK (klik = add to cart)
                            // =============================
                            GestureDetector(
                              onTap: () async {
                                if (product.is_sold == 1) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Menu ini sedang SOLD OUT.",
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                // =============================
                                // PRODUK DENGAN VARIANT
                                // =============================
                                if (product.is_variant == 1) {
                                  final selectedVariant =
                                      await showVariantSelector(
                                          product.initial_product);

                                  if (selectedVariant == null) return;

                                  if (selectedVariant['is_sold'] == 1) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Variant ini sedang SOLD OUT.",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  await addToCart(product,
                                      variant: selectedVariant);
                                  fetchTotalQuantity();
                                  return;
                                }

                                // =============================
                                // ORDER TYPE = CATERING
                                // =============================
                                if (_orderType == 'catering') {
                                  if (totalQuantity > 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "1 Transaksi hanya bisa memilih satu menu catering.",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  await addToCart(product);

                                  final subBranch =
                                      await getBranchFromLocalStorage();
                                  final sessionId = await getSession();

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CartItemScreen(
                                        sessionId: sessionId.toString(),
                                        subBranch: subBranch.toString(),
                                        isSelfService: widget.isSelfService,
                                        antrianId: widget.antrianId,
                                      ),
                                    ),
                                  ).then((_) => fetchTotalQuantity());
                                  return;
                                }

                                // =============================
                                // PRODUK NORMAL (tanpa variant)
                                // =============================
                                await addToCart(product);
                                fetchTotalQuantity();
                              },
                              child: _buildProductCard(product, currencyFormat),
                            ),

                            // =============================
                            // BUTTON ICON NOTE
                            // =============================
                            Positioned(
                              top: 6,
                              right: 6,
                              child: GestureDetector(
                                onTap: () => _openNotePopup(product),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.note_alt,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                            )
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "$totalQuantity item",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: totalQuantity > 0
                      ? () async {
                          final subBranch = await getBranchFromLocalStorage();
                          final sessionId = await getSession();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CartItemScreen(
                                sessionId: sessionId.toString(),
                                subBranch: subBranch.toString(),
                                isSelfService: widget.isSelfService,
                                antrianId: widget.antrianId,
                              ),
                            ),
                          ).then((_) => fetchTotalQuantity());
                        }
                      : null,
                  icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                  label: const Text("Keranjang"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    textStyle: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}
