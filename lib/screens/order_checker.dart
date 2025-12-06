import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock/wakelock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrderChecker extends StatefulWidget {
  const OrderChecker({super.key});

  @override
  State<OrderChecker> createState() => _OrderCheckerState();
}

class _OrderCheckerState extends State<OrderChecker> {
  final player = AudioPlayer();
  Timer? timer;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  String? domain;
  String? subBranch;
  Map<String, dynamic>? currentOrder;

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    initData();
    initializeNotifications();
  }

  Future<void> initData() async {
    domain = await getDomainFromLocalStorage();
    subBranch = await getBranchFromLocalStorage();
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        const InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {},
    );
  }

  Future<void> showNotification(String bodyText) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'order_channel',
      'Order Channel',
      channelDescription: 'Channel untuk notifikasi order baru',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Order Baru Masuk!',
      bodyText,
      platformChannelSpecifics,
    );
  }

  Future<String?> getDomainFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('domain');
  }

  Future<String?> getBranchFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sub_branch_name');
  }

  Future<void> checkNewOrders() async {
    final token = await getToken();

    if (domain == null || subBranch == null) return;

    final body = jsonEncode({'sub_branch': subBranch});

    try {
      final response = await http.post(
        Uri.parse('$domain/api/selfservice-orders/new'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['has_new'] == true && data['order'] != null) {
          currentOrder = data['order'];
          final customer = currentOrder!['customer'] ?? 'Pelanggan';
          final lokasi = currentOrder!['lokasi'] ?? 'Lokasi Tidak Diketahui';

          await showNotification('Pesanan baru dari $customer di $lokasi');
          await player.play(AssetSource('sounds/notification.mp3'));
        }
      }
    } catch (e) {
      print("Gagal fetch: $e");
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
