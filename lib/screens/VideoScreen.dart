import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mposv2/screens/sales_screen.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final PageController _pageController = PageController();

  List<String> imageUrls = [];
  bool isLoading = true;

  Timer? _autoSlideTimer;

  @override
  void initState() {
    super.initState();
    fetchImages();
  }

  Future<String?> getBranchFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_branch_name');
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<String?> getDomainFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('domain');
  }

  Future<void> fetchImages() async {
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

      final uri = Uri.parse('$domain/api/advertise-self-service');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sub_branch_name': branch}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final urls = List<String>.from(data);
        setState(() {
          imageUrls = urls;
          isLoading = false;
        });

        if (imageUrls.isNotEmpty) {
          _startAutoSlide();
        }
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  void _startAutoSlide() {
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pageController.hasClients && imageUrls.isNotEmpty) {
        final currentPage = _pageController.page?.round() ?? 0;
        final nextPage = (currentPage + 1) % imageUrls.length;

        _pageController.animateToPage(
          nextPage,
          duration:
              const Duration(seconds: 1), // smooth, lebih lama = lebih halus
          curve: Curves.easeInOut, // kurva halus
        );
      }
    });
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: imageUrls.length,
              itemBuilder: (context, index) {
                return CachedNetworkImage(
                  imageUrl: imageUrls[index],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  placeholder: (context, url) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) =>
                      const Center(child: Text("Gagal memuat gambar")),
                );
              },
            ),
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SalesScreen(
                          isSelfService: true,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                  ),
                  child: const Text(
                    "Mulai Order",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
