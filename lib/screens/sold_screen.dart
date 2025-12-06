import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mposv2/models/cart_item_test.dart';

class SoldScreen extends StatefulWidget {
  const SoldScreen({super.key});

  @override
  SoldScreenState createState() => SoldScreenState();
}

class SoldScreenState extends State<SoldScreen> {
  List<CartItem> availableProducts = [];
  List<CartItem> filteredProducts = [];

  String selectedTab = "READY";
  bool isLoading = false;

  final Set<String> selectedInitials = {};

  bool checkAllReady = false;
  bool checkAllSold = false;
  bool isUpdating = false;

  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  String formatRupiah(num value) {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return formatter.format(value);
  }

  //helper storage

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

  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id');
  }

  Future<void> _fetchProducts() async {
    setState(() => isLoading = true);
    final token = await getToken();
    final branch = await getBranchFromLocalStorage();
    final domain = await getDomainFromLocalStorage();
    final deviceId = await getDeviceId();

    if (branch == null || domain == null) {
      setState(() => isLoading = false);
      return;
    }

    final uri = Uri.parse('$domain/api/product');

    try {
      final response = await http.post(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json"
        },
        body: jsonEncode({"sub_branch_name": branch, "onuser": deviceId}),
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);

        List<CartItem> apiData = data.map((item) {
          return CartItem(
            name: (item['name'] ?? '').toString().toUpperCase(),
            initial_product: item['initial_product'] ?? '',
            quantity: 1,
            price: (item['price'] as num?)?.toDouble() ?? 0.0,
            category_name: "",
            picture: "",
            princo: "",
            category: "",
            is_sold: item['is_sold'] ?? 0,
            is_variant: item['is_variant'] ?? 0,
          );
        }).toList();

        setState(() {
          availableProducts = apiData;
          selectedInitials.clear();
          checkAllReady = false;
          checkAllSold = false;
          applyFilter();
        });
      }
    } catch (e) {
      print("Fetch error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void filterTab(String tab) {
    setState(() {
      selectedTab = tab;
      selectedInitials.clear();
      checkAllReady = false;
      checkAllSold = false;
      applyFilter();
    });
  }

  void applyFilter() {
    String q = searchController.text.toLowerCase();

    List<CartItem> list = selectedTab == "READY"
        ? availableProducts.where((p) => p.is_sold == 0).toList()
        : availableProducts.where((p) => p.is_sold == 1).toList();

    filteredProducts =
        list.where((p) => p.name.toLowerCase().contains(q)).toList();

    setState(() {});
  }

  bool isSelected(CartItem p) => selectedInitials.contains(p.initial_product);

  void toggleSelectItem(CartItem p, bool? value) {
    setState(() {
      if (value == true) {
        selectedInitials.add(p.initial_product);
      } else {
        selectedInitials.remove(p.initial_product);
      }

      // update checkAll flags
      if (selectedTab == "READY") {
        checkAllReady = filteredProducts
            .every((it) => selectedInitials.contains(it.initial_product));
      } else {
        checkAllSold = filteredProducts
            .every((it) => selectedInitials.contains(it.initial_product));
      }
    });
  }

  void toggleCheckAllReady(bool? value) {
    setState(() {
      checkAllReady = value ?? false;
      if (checkAllReady) {
        for (var p in filteredProducts) {
          selectedInitials.add(p.initial_product);
        }
      } else {
        for (var p in filteredProducts) {
          selectedInitials.remove(p.initial_product);
        }
      }
    });
  }

  void toggleCheckAllSold(bool? value) {
    setState(() {
      checkAllSold = value ?? false;
      if (checkAllSold) {
        for (var p in filteredProducts) {
          selectedInitials.add(p.initial_product);
        }
      } else {
        for (var p in filteredProducts) {
          selectedInitials.remove(p.initial_product);
        }
      }
    });
  }

  void handleSoldOrUnsold() async {
    final selectedItems = filteredProducts
        .where((p) => selectedInitials.contains(p.initial_product))
        .toList();

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedTab == "READY"
                ? "Pilih minimal satu produk untuk di-Sold"
                : "Pilih minimal satu produk untuk di-UnSold",
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    List<String> productInitials =
        selectedItems.map((p) => p.initial_product).toList();

    int newStatus = selectedTab == "READY" ? 1 : 0;

    await _updateBatchSoldStatus(productInitials, newStatus);

    // update UI
    setState(() {
      for (var p in selectedItems) {
        p.is_sold = newStatus;
      }

      selectedInitials.clear();
      checkAllReady = false;
      checkAllSold = false;
      applyFilter();
    });
  }

  Future<void> _updateBatchSoldStatus(
      List<String> initialProducts, int newStatus) async {
    setState(() => isUpdating = true);

    final token = await getToken();
    final branch = await getBranchFromLocalStorage();
    final domain = await getDomainFromLocalStorage();
    final deviceId = await getDeviceId();

    if (domain == null) {
      setState(() => isUpdating = false);
      return;
    }

    final url = Uri.parse("$domain/api/update-sold-status");

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "initial_products": initialProducts,
          "is_sold": newStatus,
          "branch": branch,
          "device": deviceId,
        }),
      );

      print("Batch update response: ${response.body}");
    } catch (e) {
      print("Batch error: $e");
    }

    setState(() => isUpdating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.grey.shade100,
          appBar: AppBar(
            title: const Text("Manage Sold Product"),
            backgroundColor: Theme.of(context).primaryColor,
          ),
          body: Column(
            children: [
              const SizedBox(height: 10),

              // tab buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  tabButton("READY", Icons.inventory_2),
                  tabButton("SOLD", Icons.check_circle),
                ],
              ),

              // search
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: searchController,
                    onChanged: (_) => applyFilter(),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, color: Colors.black),
                      hintText: "Search product...",
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),

              // check all row
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      activeColor: Theme.of(context).primaryColor,
                      title: const Text("Select All"),
                      value: selectedTab == "READY"
                          ? checkAllReady
                          : selectedInitials.isNotEmpty &&
                              filteredProducts.every((p) =>
                                  selectedInitials.contains(p.initial_product)),
                      onChanged: (val) => toggleCheckAllReady(val),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              // action button
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedTab == "READY"
                          ? Theme.of(context).primaryColor
                          : Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: handleSoldOrUnsold,
                    child: Text(
                      selectedTab == "READY"
                          ? "Sold Selected"
                          : "UnSold Selected",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              // product list
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, i) {
                          final p = filteredProducts[i];
                          final selected = isSelected(p);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 6,
                                  offset: Offset(0, 3),
                                )
                              ],
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: p.is_sold == 1
                                    ? Colors.green
                                    : Colors.orange,
                                child: Text(
                                  p.initial_product.toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                p.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(formatRupiah(p.price)),
                              trailing: Checkbox(
                                value: selected,
                                activeColor: Theme.of(context).primaryColor,
                                onChanged: (val) => toggleSelectItem(p, val),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        if (isUpdating)
          Positioned.fill(
            child: Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }

  Widget tabButton(String label, IconData icon) {
    bool active = selectedTab == label;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        onTap: () => filterTab(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(
                    colors: [
                      theme.primaryColor.withOpacity(0.9),
                      theme.primaryColor.withOpacity(0.6),
                    ],
                  )
                : LinearGradient(
                    colors: [
                      Colors.grey.shade300,
                      Colors.grey.shade400,
                    ],
                  ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
