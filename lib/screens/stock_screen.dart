import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StockInputScreen extends StatefulWidget {
  const StockInputScreen({super.key});

  @override
  _StockInputScreenState createState() => _StockInputScreenState();
}

class _StockInputScreenState extends State<StockInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();

  String? selectedCategory;
  List<Map<String, dynamic>> categories = [];

  bool isLoading = false;
  String? branchName;
  String? domain;
  String? userId;

  @override
  void initState() {
    super.initState();
    loadBranchFromLocalStorage();
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> loadBranchFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      branchName = prefs.getString('sub_branch_name') ?? '';
      domain = prefs.getString('domain') ?? '';
      userId = prefs.getString('user_id') ?? '';
    });

    fetchCategories(); // Load categories setelah mengambil data branch
  }

  Future<void> fetchCategories() async {
     final token = await getToken();

    if (domain == null ||
        domain!.isEmpty ||
        branchName == null ||
        branchName!.isEmpty) {
      debugPrint("Missing domain or branch name.");
      return;
    }

    final uri = Uri.parse('$domain/api/category');

    setState(() {
      isLoading = true;
      categories = []; // Reset sebelum fetch
    });

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sub_branch_name': branchName}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = json.decode(response.body);

        if (jsonData.containsKey('data') && jsonData['data'] is List) {
          setState(() {
            categories = List<Map<String, dynamic>>.from(jsonData['data']);
          });
        } else {
          debugPrint("Invalid data format received: ${response.body}");
        }
      } else {
        debugPrint("Failed to fetch categories: ${response.body}");
      }
    } catch (e) {
      debugPrint("Error fetching categories: $e");
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> scanBarcode() async {
    String barcodeScanRes = await FlutterBarcodeScanner.scanBarcode(
        "#ff0000", "Cancel", true, ScanMode.BARCODE);
    if (barcodeScanRes != "-1") {
      setState(() {
        _barcodeController.text = barcodeScanRes;
      });
    }
  }

  Future<void> submitData() async {
    if (!_formKey.currentState!.validate()) return;

    if ((domain?.trim().isEmpty ?? true) ||
        (branchName?.trim().isEmpty ?? true)) {
      debugPrint("Missing domain or branch name.");
      return;
    }

    final Map<String, String> data = {
      "sub_branch_name": branchName ?? "",
      "code": _codeController.text.trim(),
      "name": _nameController.text.trim(),
      "stock": _stockController.text.trim(),
      "price": _priceController.text.trim(),
      "category": selectedCategory ?? "",
      "barcode": _barcodeController.text.trim(),
    };

     final token = await getToken();
    final uri = Uri.parse('$domain/api/add-product');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);

        if (responseData['status'] == 'success') {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    responseData['message'] ?? "Stock successfully added")),
          );

          _formKey.currentState!.reset();
          setState(() {
            selectedCategory = null;
          });
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(responseData['message'] ?? "Failed to add stock")),
          );
        }
      } else {
        debugPrint("Failed response: ${response.body}");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to add stock")),
        );
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("An error occurred, please try again")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(title: const Text("Stock Input")),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(screenWidth * 0.05), // Responsif padding
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 10),
                isLoading
                    ? const CircularProgressIndicator()
                    : DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: "Category",
                          border: OutlineInputBorder(),
                        ),
                        items: categories.map((category) {
                          return DropdownMenuItem<String>(
                            value: category["category_code"]
                                .toString()
                                .toUpperCase(), // Uppercase code
                            child: Text(
                              "${category["category_code"].toString().toUpperCase()} - ${category["category_name"].toString().toUpperCase()}",
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedCategory = value;
                          });
                        },
                        validator: (value) =>
                            value == null ? "Please select a category" : null,
                      ),
                const SizedBox(height: 10),
                _buildTextField("Code Product", _codeController),
                _buildTextField("Name Product", _nameController),
                _buildTextField("Stock", _stockController,
                    keyboardType: TextInputType.number),
                _buildTextField("Price", _priceController,
                    keyboardType: TextInputType.number),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField("Barcode", _barcodeController,
                          isRequired: false),
                    ),
                    IconButton(
                      icon: Icon(Icons.qr_code_scanner,
                          color: Theme.of(context).primaryColor),
                      onPressed: scanBarcode,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, // Tombol penuh sesuai lebar layar
                  child: ElevatedButton(
                    onPressed: submitData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      padding:
                          const EdgeInsets.symmetric(vertical: 16), // Responsif
                    ),
                    child: const Text("Submit",
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text,
      bool isRequired = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 16), // Font yang nyaman dibaca
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.red)),
        ),
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return "$label cannot be empty";
          }
          return null;
        },
      ),
    );
  }
}
