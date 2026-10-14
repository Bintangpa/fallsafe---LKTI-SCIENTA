import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'models/app_user.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Konfigurasi Edge-to-Edge & System Navigation Bar Transparan Full Screen
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Inisialisasi Date Formatting untuk Locale Indonesian dengan pengaman timeout
  try {
    await initializeDateFormatting('id_ID', null).timeout(const Duration(seconds: 2));
  } catch (e) {
    print('⚠️ Date formatting init error: $e');
  }

  // Inisialisasi Supabase Database dengan pengaman timeout
  try {
    await DatabaseService.init().timeout(const Duration(seconds: 4));
  } catch (e) {
    print('⚠️ Database init error: $e');
  }

  // Hanya jalankan foreground task & local notification pada platform mobile (Android/iOS)
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      // 1. Inisialisasi komunikasi port
      FlutterForegroundTask.initCommunicationPort();

      // 2. Minta izin (Android 13+ memerlukan izin notifikasi)
      final notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      // 3. Minta mengabaikan optimasi baterai
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // 4. Inisialisasi konfigurasi service
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'fallsafe_service',
          channelName: 'FallSafe Monitoring',
          channelDescription: 'Memantau sensor jatuh secara real-time',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(5000),
          autoRunOnBoot: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );

      await NotificationService.init();
    } catch (e) {
      print('⚠️ Mobile service init skipped: $e');
    }
  }

  runApp(const FallSafeApp());
}

class FallSafeApp extends StatelessWidget {
  const FallSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FallSafe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: FutureBuilder<AppUser?>(
        future: AuthService.getCurrentUser().timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: AppTheme.background,
              body: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}