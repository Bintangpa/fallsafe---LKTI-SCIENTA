import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _isPlayingAlarm = false;
  static bool _isInitialized = false;

  // Status alarm jatuh aktif & timer getar berulang
  static bool _isFallAlertActive = false;
  static Timer? _vibrationTimer;

  static bool get isFallAlertActive => _isFallAlertActive;

  // Cek apakah suara sirine diaktifkan oleh pengguna
  static Future<bool> isSoundAlarmEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('enable_sound_alarm') ?? true;
    } catch (_) {
      return true;
    }
  }

  // Cek apakah getaran diaktifkan oleh pengguna
  static Future<bool> isVibrationEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('enable_vibration') ?? true;
    } catch (_) {
      return true;
    }
  }

  // Inisialisasi
  static Future<void> init() async {
    if (_isInitialized) return;
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      _isInitialized = true;
      return;
    }

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (details) {
          print('Notifikasi diklik: ${details.payload}');
        },
      );

      // Buat channel untuk JATUH (dengan suara alarm)
      await _createFallChannel();

      // Minta permission (Android 13+)
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      _isInitialized = true;
      print('✅ NotificationService siap');
    } catch (e) {
      print('⚠️ NotificationService init warning: $e');
    }
  }

  // Buat channel khusus JATUH dengan suara alarm
  static Future<void> _createFallChannel() async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) return;
    try {
      const androidChannel = AndroidNotificationChannel(
        'fallsafe_fall',
        'FallSafe - Deteksi Jatuh',
        description: 'Notifikasi saat jatuh terdeteksi',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alarm'),
        enableVibration: true,
        enableLights: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    } catch (_) {}
  }

  // Mulai getaran berulang tanpa henti (kebal limit timeout OS)
  static void _startContinuousVibration(bool vibEnabled) {
    _vibrationTimer?.cancel();
    if (!vibEnabled || kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    // Getaran awal instan
    _pulseVibration();

    // Pulse berkala setiap 1.5 detik agar getaran HP terus menyala tanpa henti
    // meskipun sensor kembali ke status NORMAL, sampai tombol dimatikan user
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!_isFallAlertActive) {
        timer.cancel();
        return;
      }
      _pulseVibration();
    });
  }

  static Future<void> _pulseVibration() async {
    try {
      final hasVib = await Vibration.hasVibrator();
      if (hasVib == true) {
        await Vibration.vibrate(duration: 1000, amplitude: 255);
      }
    } catch (e) {
      print('⚠️ Vibration error: $e');
    }
  }

  // Notifikasi JATUH (dipanggil saat terdeteksi jatuh)
  static Future<void> notifyFall() async {
    await init();
    _isFallAlertActive = true;

    final soundEnabled = await isSoundAlarmEnabled();
    final vibEnabled = await isVibrationEnabled();

    // 1. Getar HP terus-menerus tanpa henti
    _startContinuousVibration(vibEnabled);

    // 2. Putar suara alarm dari assets/sounds/alarm.mp3 HANYA jika diaktifkan
    if (soundEnabled) {
      await playAlarmSound();
    } else {
      await stopAlarmSound();
    }

    // 3. Tampilkan Notifikasi Push Pop-Up (hanya mobile)
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        final androidDetails = AndroidNotificationDetails(
          'fallsafe_fall',
          'FallSafe - Deteksi Jatuh',
          channelDescription: 'Notifikasi saat jatuh terdeteksi',
          importance: Importance.max,
          priority: Priority.high,
          playSound: soundEnabled,
          sound: soundEnabled ? const RawResourceAndroidNotificationSound('alarm') : null,
          enableVibration: vibEnabled,
          ongoing: true,
          autoCancel: false,
          fullScreenIntent: true,
        );

        await _notifications.show(
          999,
          '🚨 JATUH TERDETEKSI!',
          'Segera cek kondisi pengguna!',
          NotificationDetails(android: androidDetails),
          payload: 'FALL',
        );
      } catch (_) {}
    }
  }

  // Putar alarm audio dari assets/sounds/alarm.mp3 (cek setting terlebih dahulu)
  static Future<void> playAlarmSound() async {
    final soundEnabled = await isSoundAlarmEnabled();
    if (!soundEnabled) {
      print('🔇 Suara alarm dinonaktifkan di pengaturan');
      return;
    }

    try {
      if (!_isPlayingAlarm) {
        _isPlayingAlarm = true;

        if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
          await _audioPlayer.setAudioContext(AudioContext(
            android: const AudioContextAndroid(
              stayAwake: true,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.alarm,
              audioFocus: AndroidAudioFocus.gainTransient,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {AVAudioSessionOptions.defaultToSpeaker},
            ),
          ));
        }

        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(AssetSource('sounds/alarm.mp3'), volume: 1.0);
        print('🔊 Alarm audio diputar dari assets/sounds/alarm.mp3');
      }
    } catch (e) {
      print('❌ Gagal memutar alarm audio: $e');
      _isPlayingAlarm = false;
    }
  }

  // Hentikan suara audio alarm
  static Future<void> stopAlarmSound() async {
    try {
      if (_isPlayingAlarm) {
        await _audioPlayer.stop();
        _isPlayingAlarm = false;
        print('🔇 Audio alarm dihentikan');
      }
    } catch (e) {
      print('❌ Gagal menghentikan audio alarm: $e');
      _isPlayingAlarm = false;
    }
  }

  // Notifikasi CURIGA
  static Future<void> notifyWarning() async {
    // 🛡️ Jika alarm jatuh sedang aktif, JANGAN timpa getaran atau suara alarm jatuh
    if (_isFallAlertActive) return;

    await init();
    final soundEnabled = await isSoundAlarmEnabled();
    final vibEnabled = await isVibrationEnabled();

    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      if (vibEnabled) {
        try {
          final hasVib = await Vibration.hasVibrator();
          if (hasVib == true) {
            await Vibration.vibrate(duration: 500, amplitude: 128);
          }
        } catch (_) {}
      }

      try {
        final androidDetails = AndroidNotificationDetails(
          'fallsafe_warning',
          'FallSafe - Peringatan',
          channelDescription: 'Peringatan gerakan curiga',
          importance: Importance.high,
          priority: Priority.high,
          playSound: soundEnabled,
          enableVibration: vibEnabled,
        );

        await _notifications.show(
          998,
          '⚠️ Gerakan Curiga',
          'Ada gerakan tidak normal. Mohon periksa.',
          NotificationDetails(android: androidDetails),
        );
      } catch (_) {}
    }
  }

  // Stop alarm, suara & vibration (HANYA saat ditekan oleh user)
  static Future<void> stopAlarm() async {
    _isFallAlertActive = false;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;

    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        await Vibration.cancel();
      } catch (_) {}
    }

    await stopAlarmSound();

    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        await _notifications.cancel(999);
        await _notifications.cancel(998);
      } catch (_) {}
    }
    print('🔇 Alarm audio, notif & getar dihentikan oleh pengguna');
  }
}