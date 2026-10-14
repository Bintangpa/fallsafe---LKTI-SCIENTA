import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'database_service.dart';
import 'mdns_service.dart';
import 'notification_service.dart';
import '../models/sensor_log.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FallSafeTaskHandler());
}

class FallSafeTaskHandler extends TaskHandler {
  WebSocketChannel? _channel;
  bool _isConnecting = false;
  String _lastStatus = 'NORMAL';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await DatabaseService.init();
    _connectWebSocket();
  }

  Future<void> _connectWebSocket() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      var wsUrl = prefs.getString('ws_url');
      if (wsUrl == null || wsUrl.isEmpty) {
        final settings = await DatabaseService.getSettings();
        if (settings != null && settings['ws_url'] != null) {
          wsUrl = settings['ws_url'] as String;
          await prefs.setString('ws_url', wsUrl);
        }
      }
      wsUrl ??= MdnsService.defaultEndpoint;
      final resolvedUrl = await MdnsService.getResolvedWsUrl(wsUrl);
      final uri = Uri.parse(resolvedUrl);

      await _channel?.sink.close();
      _channel = WebSocketChannel.connect(uri);

      _channel!.ready.then((_) {
        _isConnecting = false;
        print('✅ ForegroundTask WebSocket terhubung ke $resolvedUrl');
        FlutterForegroundTask.sendDataToMain({'connected': true});
      }).catchError((e) {
        _isConnecting = false;
        FlutterForegroundTask.sendDataToMain({'connected': false});
        _scheduleReconnect();
      });

      _channel!.stream.listen(
        (message) async {
          try {
            String? status;
            try {
              final data = jsonDecode(message);
              if (data is Map) {
                status = data['status']?.toString();
              } else if (data is String) {
                status = data;
              }
            } catch (_) {
              status = message.toString().trim();
            }

            if (status != null && status.isNotEmpty) {
              status = status.toUpperCase();

              // Simpan ke database
              await DatabaseService.insertLog(SensorLog(
                status: status,
                timestamp: DateTime.now(),
              ));

              await _handleStatusChange(status);

              // Kirim ke UI (terhubung = true + update data)
              FlutterForegroundTask.sendDataToMain({
                'connected': true,
                'status': status,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              });
            }
          } catch (e) {
            print('❌ Parse error: $e');
          }
        },
        onDone: () {
          _isConnecting = false;
          FlutterForegroundTask.sendDataToMain({'connected': false});
          _scheduleReconnect();
        },
        onError: (e) {
          _isConnecting = false;
          FlutterForegroundTask.sendDataToMain({'connected': false});
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isConnecting = false;
      FlutterForegroundTask.sendDataToMain({'connected': false});
      _scheduleReconnect();
    }
  }

  bool _isFallAlertPending = false;

  // ⚡ Handle status change - update notifikasi service, push notification & getar
  Future<void> _handleStatusChange(String status) async {
    // Jangan spam kalau status sama
    if (status == _lastStatus) return;
    _lastStatus = status;

    if (status == 'JATUH') {
      _isFallAlertPending = true;
      // 1. Update notifikasi foreground service
      await FlutterForegroundTask.updateService(
        notificationTitle: '🚨 JATUH TERDETEKSI!',
        notificationText: 'Segera cek kondisi pengguna!',
      );

      // 2. Kirim Notifikasi Pop-Up / Heads-Up Push ke HP dan aktifkan getar
      await NotificationService.notifyFall();

      print('🚨 JATUH - notif push & getar dipicu dari background');
    } else if (status == 'CURIGA') {
      if (!_isFallAlertPending) {
        await FlutterForegroundTask.updateService(
          notificationTitle: '⚠️ Gerakan Curiga',
          notificationText: 'Ada gerakan tidak normal',
        );

        await NotificationService.notifyWarning();
        print('⚠️ CURIGA - notif warning dipicu');
      }
    } else {
      // 🟢 NORMAL:
      if (_isFallAlertPending) {
        // Jika pernah jatuh sebelumnya dan belum dimatikan oleh user:
        // getar & alarm TETAP berjalan, beri tahu user di bar notifikasi
        await FlutterForegroundTask.updateService(
          notificationTitle: '🚨 PERINGATAN: Pasien Sempat Terjatuh!',
          notificationText: 'Sensor kini normal. Ketuk aplikasi untuk matikan alarm & getar.',
        );
        print('🟡 NORMAL setelah JATUH - getar & alarm tetap aktif, menunggu konfirmasi user');
      } else {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'FallSafe Aktif',
          notificationText: 'Sensor normal dan sedang memantau...',
        );
      }
    }
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 3), () {
      _connectWebSocket();
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _channel?.sink.close();
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      if (data['action'] == 'stopAlarm') {
        _isFallAlertPending = false;
        NotificationService.stopAlarm();
        FlutterForegroundTask.updateService(
          notificationTitle: 'FallSafe Aktif',
          notificationText: 'Sensor normal dan sedang memantau...',
        );
        print('🔕 ForegroundTask menerima perintah stopAlarm dari UI');
      } else if (data['action'] == 'reconnect') {
        print('🔄 ForegroundTask menerima perintah reconnect dari UI');
        _channel?.sink.close();
        _isConnecting = false;
        _connectWebSocket();
      }
    }
  }
}