import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_custom_clippers/flutter_custom_clippers.dart';

import 'login_screen.dart';

class BranchFormScreen extends StatefulWidget {
  const BranchFormScreen({super.key});

  @override
  _BranchFormScreenState createState() => _BranchFormScreenState();
}

class _BranchFormScreenState extends State<BranchFormScreen> {
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _domainController = TextEditingController();
  final TextEditingController _deviceController = TextEditingController();
  final TextEditingController _subdeviceController = TextEditingController();
  String? _selectedSubBranch;
  List<dynamic> _subBranches = [];
  bool _branchFound = false;
  Future<void> _checkBranch() async {
    setState(() {
      _branchFound = false;
      _subBranches = [];
      _selectedSubBranch = null;
    });

    final domain = _domainController.text.trim();
    final branchName = _branchController.text.trim();
    final subDevice = _subdeviceController.text.trim();
    final device = _deviceController.text.trim();

    if (branchName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a bisnis unit name')),
      );
      return;
    }

    try {
      final url = Uri.parse(
        '$domain/api/branches?name=$branchName&device=$device&sub_device=$subDevice',
      );

      final response = await http.get(url);

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        if (data['success'] == true) {
          final subs = data['data']['sub_branches'] ?? [];

          if (subs.isNotEmpty) {
            setState(() {
              _branchFound = true;
              _subBranches = subs;
            });
            return;
          }
        }

        // jika success false ATAU sub_branches kosong
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message'] ?? 'Bisnis unit belum terdaftar',
              style: TextStyle(color: Colors.red),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to fetch bisnis unit data'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An error occurred. Please try again.'),
        ),
      );
    }
  }

  Future<void> _saveToLocalStorage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final domain = _domainController.text;
    final branchName = _branchController.text;
    final device = _deviceController.text;
    final subDevice = _subdeviceController.text;

    if (domain.isEmpty || branchName.isEmpty || _selectedSubBranch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    await prefs.setString('domain', domain);
    await prefs.setString('branch_name', branchName);
    await prefs.setString('sub_branch_name', _selectedSubBranch!);
    await prefs.setString('device_id', device);
    await prefs.setString('sub_device', subDevice);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuration saved successfully')),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Align(
          alignment: Alignment.bottomCenter,
          child: ClipPath(
            clipper: WaveClipperOne(reverse: true),
            child: Container(
              height: 100,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo
                  Image.asset(
                    'assets/mjn-logo.png',
                    height: 70,
                    width: 70,
                  ),
                  const SizedBox(height: 16),

                  // Host input
                  TextField(
                    controller: _domainController,
                    decoration: InputDecoration(
                      labelText: 'Host',
                      labelStyle:
                          TextStyle(color: Theme.of(context).primaryColor),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: Theme.of(context).primaryColor),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _deviceController,
                    decoration: InputDecoration(
                      labelText: 'Enter ID Device',
                      labelStyle:
                          TextStyle(color: Theme.of(context).primaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: Theme.of(context).primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _subdeviceController,
                    decoration: InputDecoration(
                      labelText: 'Enter Sub Device',
                      labelStyle:
                          TextStyle(color: Theme.of(context).primaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: Theme.of(context).primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Branch + Check button
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _branchController,
                          decoration: InputDecoration(
                            labelText: 'Bisnis Unit',
                            labelStyle: TextStyle(
                                color: Theme.of(context).primaryColor),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor),
                            ),
                          ),
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _checkBranch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(12),
                        ),
                        child: const Icon(Icons.check, size: 20),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Sub-branch dropdown
                  if (_branchFound)
                    DropdownButtonFormField<String>(
                      value: _selectedSubBranch,
                      hint: const Text('Pilih Sub-Branch'),
                      items: _subBranches.map((subBranch) {
                        return DropdownMenuItem<String>(
                          value: subBranch['sub_branch_name'],
                          child: Text(
                            subBranch['sub_branch_name'],
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedSubBranch = value;
                        });
                      },
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Save button
                  ElevatedButton(
                    onPressed: _saveToLocalStorage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Theme.of(context).primaryColor),
                      ),
                    ),
                    child: const Text(
                      'Simpan & Login',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
