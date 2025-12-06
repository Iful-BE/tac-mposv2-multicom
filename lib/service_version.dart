import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Model response sesuai backend
class ServiceVersionResponse {
  final String latestVersion;
  final String currentVersion;
  final String minSupportedVersion;
  final String apkUrl;
  final String changelog;
  final bool upToDate;

  ServiceVersionResponse({
    required this.latestVersion,
    required this.currentVersion,
    required this.minSupportedVersion,
    required this.apkUrl,
    required this.changelog,
    required this.upToDate,
  });

  factory ServiceVersionResponse.fromJson(Map<String, dynamic> json) {
    return ServiceVersionResponse(
      latestVersion: json['latest_version'],
      minSupportedVersion: json['min_supported_version'],
      apkUrl: json['apk_url'],
      changelog: json['changelog'] ?? '',
      upToDate: json['up_to_date'] ?? false,
      currentVersion: json['current_versi'] ?? false,
    );
  }
}

/// Model request
class ServiceVersionRequest {
  final String subBranch;
  final String device;

  ServiceVersionRequest({
    required this.subBranch,
    required this.device,
  });

  Map<String, dynamic> toJson() {
    return {
      "sub_branch": subBranch,
      "device": device,
    };
  }
}

/// Fungsi fetch
Future<ServiceVersionResponse?> fetchServiceVersion(
    ServiceVersionRequest request) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final domain = prefs.getString('domain') ?? '';

    if (domain.isEmpty) {
      print("Domain tidak ditemukan di SharedPreferences");
      return null;
    }

    final uri = Uri.parse('$domain/api/app-version');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return ServiceVersionResponse.fromJson(data);
    } else {
      print("Error fetchServiceVersion: ${response.statusCode}");
      return null;
    }
  } catch (e) {
    print("Exception fetchServiceVersion: $e");
    return null;
  }
}
