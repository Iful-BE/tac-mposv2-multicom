import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';

class ForceUpdateDialog extends StatefulWidget {
  final String downloadUrl;
  final String latestVersion;
  final String currentVersion;

  const ForceUpdateDialog(
      {super.key,
      required this.downloadUrl,
      required this.latestVersion,
      required this.currentVersion});

  @override
  State<ForceUpdateDialog> createState() => _ForceUpdateDialogState();
}

class _ForceUpdateDialogState extends State<ForceUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;

  Future<String> _getDeviceId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id') ?? 'No Device available';
  }

  Future<bool> checkInstallPermission(BuildContext context) async {
    if (!Platform.isAndroid) return true; // iOS tidak perlu

    try {
      final status = await Permission.requestInstallPackages.status;
      if (status.isGranted) return true;

      // Tampilkan dialog untuk arahkan ke settings
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("Izin Diperlukan"),
          content: Text(
              "Untuk melakukan update, izinkan instalasi dari sumber tidak dikenal."),
          actions: [
            TextButton(
              onPressed: () async {
                // Buka halaman setting install unknown apps
                final intent = AndroidIntent(
                  action: 'android.settings.MANAGE_UNKNOWN_APP_SOURCES',
                );
                await intent.launch();
                Navigator.pop(context);
              },
              child: Text("Buka Pengaturan"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Batal"),
            ),
          ],
        ),
      );

      return false;
    } catch (e) {
      //debugPrint("Error checkInstallPermission: $e");
      return false;
    }
  }

  Future<void> _downloadAndInstall(BuildContext context) async {
    bool canInstall = await checkInstallPermission(context);
    if (!canInstall) return;

    setState(() => _isDownloading = true);
    _progress = 0.0;

    final prefs = await SharedPreferences.getInstance();

    try {
      // Path aman di folder private aplikasi
      final dir = await getExternalStorageDirectory();
      final downloadPath = "${dir!.path}/update.apk";
      final file = File(downloadPath);

      // Hapus file lama supaya dinamis
      if (await file.exists()) await file.delete();

      final dio = Dio();
      //debugPrint("Start download APK versi ${widget.latestVersion}");

      await dio.download(
        widget.downloadUrl,
        downloadPath,
        onReceiveProgress: (received, total) {
          setState(() {
            _progress = total != 0 ? received / total : 0;
          });
        },
      );

      //debugPrint("Download APK selesai: $downloadPath");

      // Simpan versi terbaru di prefs (dinamis)
      await prefs.setString('next_version', widget.latestVersion);
      await prefs.setString('current_version', widget.currentVersion);

      // Install APK otomatis
      try {
        await InstallPlugin.installApk(
          downloadPath,
          appId: 'com.example.mposv2',
        );
      } catch (e) {
        //debugPrint("Install otomatis gagal: $e");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Install otomatis gagal. Silakan buka file APK di folder aplikasi."),
            ),
          );
        }
        await OpenFile.open(downloadPath);
      }
    } catch (e) {
      //debugPrint("Download / Install error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gagal update. Silakan coba lagi.")),
        );
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: AlertDialog(
        title: const Text("Updater Multipos"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                "Versi multipos diperbaharui. Silakan update aplikasi untuk melanjutkan."),
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              Text("${(_progress * 100).toStringAsFixed(0)}%"),
            ]
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed:
                _isDownloading ? null : () => _downloadAndInstall(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: _isDownloading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text("Update APK"),
          ),
        ],
      ),
    );
  }
}
