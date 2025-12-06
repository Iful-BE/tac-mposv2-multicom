import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_controller.dart';
import 'screens/login_screen.dart';
import 'screens/branch_form.dart';
// import 'screens/order_checker.dart'; // sementara nonaktif biar gak nutup UI
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

final player = AudioPlayer();
// Simpan notifikasi aktif berdasarkan order_id (string)
final Set<String> _activeNotifs = {};
// ================= Local Notifications =================
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'This channel is used for important notifications.',
  importance: Importance.high,
);

// ================ FCM background handler ================
@pragma('vm:entry-point') // WAJIB biar handler bisa dipanggil
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final notif = message.notification;
  final data = message.data;

  print('[BG] ${notif?.title} - ${notif?.body}');
  print('📦 data: $data');

  // ✅ Ambil device_id lokal
  final localDeviceId = await getDevice();
  final notifDeviceId = data['device_id'];

  // ✅ Check device cocok
  if (notifDeviceId != null && notifDeviceId != localDeviceId) {
    print("⚠️ Notif ini untuk device lain, diabaikan (BG).");
    return;
  }

  // ✅ Panggil reminder biar ada suara berulang
  await showReminderNotification(message);
}

Future<void> showReminderNotification(RemoteMessage message) async {
  final notif = message.notification;
  final android = notif?.android;
  final data = message.data;

  if (notif == null || android == null) return;

  final String id = data['order_id'] ?? notif.hashCode.toString();
  _activeNotifs.add(id);

  await flutterLocalNotificationsPlugin.show(
    id.hashCode,
    notif.title,
    notif.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        playSound: false,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: id,
  );

  await player.play(AssetSource('sounds/notification.mp3'));

  // Reminder tiap 30 detik
  // Future.delayed(const Duration(seconds: 10), () async {
  //   if (_activeNotifs.contains(id)) {
  //     print("🔔 Reminder untuk order $id masih aktif");
  //     await player.play(AssetSource('sounds/notification.mp3'));
  //     showReminderNotification(message);
  //   }
  // });

  // Future.delayed(const Duration(minutes: 1), () {
  //   if (_activeNotifs.contains(id)) {
  //     print("⏹️ Auto-stop reminder karena notif $id sudah lebih dari 1 menit");
  //     _activeNotifs.remove(id);
  //     flutterLocalNotificationsPlugin.cancel(id.hashCode);
  //   }
  // });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Init Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Ambil branch info dari SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final String? branch = prefs.getString('branch_name');
    final String? subBranch = prefs.getString('sub_branch_name');
    print("✅ SharedPreferences: branch=$branch, subBranch=$subBranch");

    // Load theme
    await ThemeController.loadThemeColor();

    // Init local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    // Buat channel notifikasi
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Hanya jalankan FCM jika **bukan Windows**
    if (!kIsWeb && !Platform.isWindows) {
      // Daftarkan handler background
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // Setup FCM (izin, token, listener)
      await _initFCM();
    } else {
      print("ℹ️ FCM dimatikan di Windows/Web");
    }

    // RunApp
    runApp(MyApp(branch: branch, subBranch: subBranch));
  } catch (e, st) {
    print("🔥 ERROR in main: $e\n$st");
  }
}

class MyApp extends StatelessWidget {
  final String? branch;
  final String? subBranch;
  const MyApp({super.key, this.branch, this.subBranch});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeController.primaryColor,
      builder: (context, color, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primaryColor: color,
            scaffoldBackgroundColor: Colors.white,
            appBarTheme: AppBarTheme(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(backgroundColor: color),
            ),
          ),
          builder: (context, child) {
            print("✅ MaterialApp builder dipanggil");
            // sementara jangan pakai OrderChecker dulu
            return child!;
            /*
            return Stack(
              children: [
                child!,
                const OrderChecker(),
              ],
            );
            */
          },
          home: branch == null || subBranch == null
              ? BranchFormScreen()
              : const LoginScreen(),
        );
      },
    );
  }
}

Future<String?> getDomainFromLocalStorage() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('domain');
}

Future<String?> getBranchFromLocalStorage() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('sub_branch_name');
}

Future<String?> getDevice() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('device_id');
}

Future<void> sendTokenToBackend({
  required String tokenFcm,
  required String deviceId,
  required String subBranch,
}) async {
  try {
    final domain =
        await getDomainFromLocalStorage(); // ambil base url backend dari local storage
    if (domain == null) {
      print("❌ Domain backend tidak ditemukan");
      return;
    }

    const String apiToken = '6XCkiyLZUFFxomPkxyeliAedIrvMvFoNibXRlinY73710468';

    final url = Uri.parse('$domain/api/update-token');
    final body = jsonEncode({
      'device_id': deviceId,
      'sub_branch': subBranch,
      'token_fcm': tokenFcm,
    });

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      print("✅ Token berhasil dikirim ke Laravel: ${response.body}");
    } else {
      print("❌ Gagal kirim token (${response.statusCode}): ${response.body}");
    }
  } catch (e) {
    print("🔥 Error kirim token: $e");
  }
}

// ================= FCM setup =================
Future<void> _initFCM() async {
  final messaging = FirebaseMessaging.instance;

  // Minta izin notifikasi
  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  print('📢 FCM perm status: ${settings.authorizationStatus}');

  // 🔑 Cek dulu apakah branch sudah di-setup
  final domain = await getDomainFromLocalStorage();
  final subBranch = await getBranchFromLocalStorage();
  final deviceId = await getDevice();

  if (domain == null || subBranch == null || deviceId == null) {
    print("⚠️ Branch / device belum setup. FCM token tidak diambil.");
    return;
  }

  // Kalau branch lengkap → ambil token FCM
  String? token = await messaging.getToken();
  print('📢 FCM token: $token');

  if (token != null) {
    await sendTokenToBackend(
      tokenFcm: token,
      deviceId: deviceId,
      subBranch: subBranch,
    );
  }

  Future<void> showReminderNotification(RemoteMessage message) async {
    final notif = message.notification;
    final android = notif?.android;
    final data = message.data;

    if (notif == null || android == null) return;

    final String id = data['order_id'] ?? notif.hashCode.toString();
    _activeNotifs.add(id);

    await flutterLocalNotificationsPlugin.show(
      id.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: false,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: id,
    );

    await player.play(AssetSource('sounds/notification.mp3'));

    // Reminder tiap 30 detik
    // Future.delayed(const Duration(seconds: 10), () async {
    //   if (_activeNotifs.contains(id)) {
    //     print("🔔 Reminder untuk order $id masih aktif");
    //     await player.play(AssetSource('sounds/notification.mp3'));
    //     showReminderNotification(message);
    //   }
    // });

    // Future.delayed(const Duration(minutes: 1), () {
    //   if (_activeNotifs.contains(id)) {
    //     print(
    //         "⏹️ Auto-stop reminder karena notif $id sudah lebih dari 1 menit");
    //     _activeNotifs.remove(id);
    //     flutterLocalNotificationsPlugin.cancel(id.hashCode);
    //   }
    // });
  }

  // Listener saat token berubah
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    print('📢 FCM token refreshed: $newToken');
    final domain = await getDomainFromLocalStorage();
    final subBranch = await getBranchFromLocalStorage();
    final deviceId = await getDevice();

    if (domain != null && subBranch != null && deviceId != null) {
      await sendTokenToBackend(
        tokenFcm: newToken,
        deviceId: deviceId,
        subBranch: subBranch,
      );
    } else {
      print("⚠️ Token refresh di-skip, branch/device belum lengkap.");
    }
  });

  // ✅ Notifikasi saat app di foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final notif = message.notification;
    final data = message.data;

    final localDeviceId = await getDevice();
    final notifDeviceId = data['device_id'];

    print('[FG] ${notif?.title} - ${notif?.body}');
    print('📱 localDeviceId=$localDeviceId, notifDeviceId=$notifDeviceId');

    if (notifDeviceId != null && notifDeviceId != localDeviceId) {
      print("⚠️ Notif ini untuk device lain, diabaikan.");
      return;
    }

    // ✅ Panggil fungsi reminder
    await showReminderNotification(message);
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final data = message.data;
    final id = data['order_id'] ?? message.notification.hashCode.toString();

    print('[CLICK] ${message.notification?.title}');
    if (data['order_id'] != null) {
      print("➡️ Buka detail order ID: ${data['order_id']}");
    }

    _activeNotifs.remove(id); // stop reminder
    flutterLocalNotificationsPlugin.cancelAll();
  });

  final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMsg != null) {
    final data = initialMsg.data;
    final id = data['order_id'] ?? initialMsg.notification.hashCode.toString();

    print('[INITIAL] ${initialMsg.notification?.title}');
    if (data['order_id'] != null) {
      print("➡️ Buka detail order ID: ${data['order_id']}");
    }

    _activeNotifs.remove(id); // stop reminder
    flutterLocalNotificationsPlugin.cancelAll();
  }
}
