import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import '../models/sensor_log.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/foreground_task_handler.dart';
import '../services/mdns_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snackbar.dart';

import 'history_screen.dart';
import 'login_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'user_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _status = 'MENUNGGU...';
  String _connectionState = 'Terputus';
  String _currentWsUrl = MdnsService.defaultEndpoint;
  DateTime? _lastUpdate;
  AppUser? _currentUser;
  WebSocketChannel? _directWebsocketChannel;
  int _selectedIndex = 0;
  List<SensorLog> _recentLogs = [];
  bool _isDialogShowing = false;
  // Callback untuk memperbarui konten dialog secara reaktif dari luar
  StateSetter? _dialogSetState;

  Timer? _heartbeatTimer;
  StreamSubscription? _supabaseSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUser();
    _initMonitoring();
    _loadLatestFromDb();
    _listenSupabaseRealtime();
    _startHeartbeatTimer();

    // Jika alarm jatuh masih aktif saat app dibuka kembali, tampilkan dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (NotificationService.isFallAlertActive && !_isDialogShowing) {
        _showFallDialog();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (NotificationService.isFallAlertActive && !_isDialogShowing) {
        _showFallDialog();
      }
    }
  }

  void _listenSupabaseRealtime() {
    try {
      _supabaseSubscription = DatabaseService.streamLogs().listen((logs) {
        if (logs.isNotEmpty && mounted) {
          final latest = logs.first;
          setState(() {
            _recentLogs = logs.take(5).toList();
            _status = latest.status;
            _lastUpdate = latest.timestamp;
            final diff = DateTime.now().difference(latest.timestamp).inSeconds;
            if (diff <= 30) {
              _connectionState = 'Terhubung';
            } else {
              _connectionState = 'Terputus';
            }
          });

          if (latest.status == 'JATUH') {
            if (!(_currentUser?.isAdmin ?? false)) {
              _showFallDialog();
            }
          } else {
            // Jika dialog masih terbuka, perbarui kontennya secara reaktif
            if (_isDialogShowing && _dialogSetState != null) {
              _dialogSetState!(() {});
            }
          }
        }
      }, onError: (e) {
        print('Supabase stream error: $e');
      });
    } catch (e) {
      print('Supabase stream error: $e');
    }
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      if (_lastUpdate == null) {
        if (_connectionState != 'Terputus') {
          setState(() => _connectionState = 'Terputus');
        }
      } else {
        final diff = DateTime.now().difference(_lastUpdate!).inSeconds;
        if (diff > 30 && _connectionState != 'Terputus') {
          setState(() => _connectionState = 'Terputus');
        }
      }
    });
  }

  void _initMonitoring() {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      _checkServiceRunning();
      FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    }
    _connectDirectWebSocket();
  }

  Future<void> _connectDirectWebSocket() async {
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
      if (mounted) setState(() => _currentWsUrl = wsUrl!);

      // Resolusi mDNS: selesaikan fallsafe.local ke IP riil jika diperlukan
      final resolvedUrl = await MdnsService.getResolvedWsUrl(wsUrl);
      print('🔌 Menghubungkan WebSocket ke: $resolvedUrl (asal: $wsUrl)');
      final uri = Uri.parse(resolvedUrl);

      await _directWebsocketChannel?.sink.close();
      _directWebsocketChannel = WebSocketChannel.connect(uri);

      _directWebsocketChannel!.ready.then((_) {
        print('✅ WebSocket terhubung ke $resolvedUrl');
        if (mounted) {
          setState(() {
            _connectionState = 'Terhubung';
            _lastUpdate = DateTime.now();
          });
        }
      }).catchError((e) {
        print('❌ WebSocket gagal konek ke $resolvedUrl: $e');
        if (mounted) setState(() => _connectionState = 'Terputus');
        _reconnectDirectWebSocket();
      });

      _directWebsocketChannel!.stream.listen(
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

            if (status != null && status.isNotEmpty && mounted) {
              final now = DateTime.now();
              setState(() {
                _status = status!.toUpperCase();
                _lastUpdate = now;
                _connectionState = 'Terhubung';
              });

              final log = SensorLog(status: _status, timestamp: now);
              await DatabaseService.insertLog(log);
              _refreshRecentLogs();

              if (_status == 'JATUH') {
                if (!(_currentUser?.isAdmin ?? false)) {
                  _showFallDialog();
                }
              } else {
                // Jika dialog masih terbuka, perbarui kontennya secara reaktif
                if (_isDialogShowing && _dialogSetState != null) {
                  _dialogSetState!(() {});
                }
              }
              // ⚠️ Alarm & getar TIDAK dihentikan otomatis.
              // User harus menekan tombol MATIKAN ALARM sendiri.
            }
          } catch (e) {
            print('WebSocket parse error: $e');
          }
        },
        onDone: () {
          print('🔌 WebSocket onDone: terputus');
          if (mounted) setState(() => _connectionState = 'Terputus');
          _reconnectDirectWebSocket();
        },
        onError: (err) {
          print('🔌 WebSocket onError: $err');
          if (mounted) setState(() => _connectionState = 'Terputus');
          _reconnectDirectWebSocket();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print('WebSocket connect exception: $e');
      if (mounted) setState(() => _connectionState = 'Terputus');
      _reconnectDirectWebSocket();
    }
  }

  void _reconnectDirectWebSocket() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS))) {
        _connectDirectWebSocket();
      }
    });
  }

  Future<void> _loadUser() async {
    final user = await AuthService.getCurrentUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
      });
    }
  }

  Future<void> _loadLatestFromDb() async {
    final latest = await DatabaseService.getLatestLog();
    final logs = await DatabaseService.getAllLogs();
    if (mounted) {
      setState(() {
        if (latest != null) {
          _status = latest.status;
          _lastUpdate = latest.timestamp;
          final diff = DateTime.now().difference(latest.timestamp).inSeconds;
          if (diff <= 30) {
            _connectionState = 'Terhubung';
          } else {
            _connectionState = 'Terputus';
          }
        } else {
          _connectionState = 'Terputus';
        }
        _recentLogs = logs.take(5).toList();
      });
    }
  }

  Future<void> _refreshRecentLogs() async {
    final logs = await DatabaseService.getAllLogs();
    if (mounted) {
      setState(() {
        _recentLogs = logs.take(5).toList();
      });
    }
  }

  Future<void> _checkServiceRunning() async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) return;
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (!isRunning) {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'FallSafe Aktif',
          notificationText: 'Memantau sensor jatuh...',
          callback: startCallback,
        );
      }
    } catch (e) {
      print('ForegroundTask check service error: $e');
    }
  }

  void _onReceiveTaskData(Object data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    final isConnected = map['connected'] as bool?;

    if (isConnected != null && mounted) {
      if (isConnected && _connectionState != 'Terhubung') {
        setState(() => _connectionState = 'Terhubung');
      }
    }

    final status = map['status'] as String?;
    final timestamp = map['timestamp'] as int?;
    if (status == null || timestamp == null) return;
    if (!mounted) return;

    setState(() {
      _status = status;
      _lastUpdate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      _connectionState = 'Terhubung';
    });

    _refreshRecentLogs();

    if (status == 'JATUH') {
      if (!(_currentUser?.isAdmin ?? false)) {
        _showFallDialog();
      }
    } else {
      // Jika dialog masih terbuka, perbarui kontennya secara reaktif
      if (_isDialogShowing && _dialogSetState != null) {
        _dialogSetState!(() {});
      }
    }
    // ⚠️ Alarm & getar TIDAK dihentikan otomatis.
    // User harus menekan tombol MATIKAN ALARM sendiri.
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Logout'),
        content: const Text('Apakah Anda yakin ingin keluar dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _showFallDialog() {
    // 🛡️ Mode Admin: Hanya pencatatan riwayat & monitoring live, tanpa alarm paksa / dialog pengunci layar
    if (_currentUser?.isAdmin ?? false) return;

    if (_isDialogShowing) return;
    _isDialogShowing = true;

    NotificationService.notifyFall();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false, // 🚫 Kunci layar: jangan biarkan ditutup dengan tombol back HP atau gesture swipe back!
        child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Simpan callback setDialogState agar bisa dipanggil dari luar saat status sensor berubah
            _dialogSetState = setDialogState;

            final currentStatus = _status;
            final isNowNormal = currentStatus == 'NORMAL';

            return AlertDialog(
              backgroundColor: AppTheme.dangerBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              icon: Icon(
                isNowNormal ? Icons.warning_amber_rounded : Icons.emergency,
                size: 64,
                color: AppTheme.danger,
              ),
              title: Text(
                isNowNormal
                    ? 'SENSOR KEMBALI NORMAL\n(SEMPAT TERJATUH)'
                    : '🚨 JATUH TERDETEKSI!',
                style: const TextStyle(
                  color: AppTheme.danger,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.vibration, color: AppTheme.danger, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isNowNormal
                                ? 'Sensor terdeteksi sempat terjatuh dan kini sudah kembali NORMAL.\n\nGetaran & alarm di HP TETAP MENYALA agar Anda mengecek kondisi pengguna secara langsung.'
                                : 'Sensor mengidentifikasi pasien terjatuh!\nSegera cek kondisi fisik pasien atau matikan alarm setelah memastikan kondisi aman.',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pastikan Anda telah mengecek pasien secara langsung sebelum mematikan alarm.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      NotificationService.stopAlarm();
                      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
                        FlutterForegroundTask.sendDataToTask({'action': 'stopAlarm'});
                      }
                      _isDialogShowing = false;
                      _dialogSetState = null;
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.notifications_off_rounded),
                    label: const Text(
                      'MATIKAN ALARM & KONFIRMASI (OK)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ).then((_) {
      // Pastikan flag direset jika dialog selesai ditutup
      _isDialogShowing = false;
      _dialogSetState = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _supabaseSubscription?.cancel();
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    }
    _directWebsocketChannel?.sink.close();
    super.dispose();
  }

  Color _getStatusColor() {
    switch (_status) {
      case 'NORMAL':
        return AppTheme.success;
      case 'CURIGA':
        return AppTheme.warning;
      case 'JATUH':
        return AppTheme.danger;
      default:
        return AppTheme.textMuted;
    }
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case 'NORMAL':
        return Icons.check_circle;
      case 'CURIGA':
        return Icons.warning;
      case 'JATUH':
        return Icons.emergency;
      default:
        return Icons.help_outline;
    }
  }

  String _getFormattedDate() {
    try {
      return DateFormat('EEEE, d MMMM', 'id_ID').format(DateTime.now());
    } catch (_) {
      try {
        return DateFormat('EEEE, d MMMM').format(DateTime.now());
      } catch (_) {
        return DateTime.now().toString().split(' ')[0];
      }
    }
  }

  void _onTabChanged(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) {
      // Reconnect WebSocket secara otomatis saat kembali ke Dashboard
      _connectDirectWebSocket();
    }
  }

  // --------------------------------------------------------------------------
  // DASHBOARD MAIN CONTENT VIEW (Styled after reference image 1 & 2)
  // --------------------------------------------------------------------------
  Widget _buildDashboardContent(bool isAdmin) {
    final nowStr = _getFormattedDate();

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: Colors.white,
      onRefresh: () async {
        await _connectDirectWebSocket();
        await _loadLatestFromDb();
        _refreshRecentLogs();
        await _loadUser();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. TOP HEADER (Salam Pengguna)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Halo, ${_currentUser?.name ?? 'Petugas'} 👋',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Sistem Pemantauan Sensor Real-Time',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 3. HERO LIVE SENSOR CARD
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppTheme.softShadow,
                ),
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          child: const Icon(Icons.sensors, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Perangkat Monitoring Sensor',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Text(
                                    'Esp-32 u',
                                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _connectionState == 'Terhubung'
                                          ? Colors.greenAccent.withValues(alpha: 0.25)
                                          : Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _connectionState == 'Terhubung'
                                            ? Colors.greenAccent
                                            : Colors.white38,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _connectionState == 'Terhubung' ? Icons.circle : Icons.circle_outlined,
                                          size: 8,
                                          color: _connectionState == 'Terhubung' ? Colors.greenAccent : Colors.white70,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _connectionState == 'Terhubung' ? 'ONLINE' : 'OFFLINE',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: _connectionState == 'Terhubung' ? Colors.greenAccent : Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Endpoint: $_currentWsUrl',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      AppSnackBar.info(context, 'Mencoba menghubungkan ulang ke sensor...');
                                      _connectDirectWebSocket();
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.refresh, size: 12, color: Colors.white),
                                          SizedBox(width: 4),
                                          Text(
                                            'Hubungkan',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _connectionState == 'Terhubung' ? Icons.access_time_filled : Icons.history_toggle_off,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _lastUpdate == null
                                        ? 'Belum ada data'
                                        : DateFormat('HH:mm:ss').format(_lastUpdate!),
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today, color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    _lastUpdate == null
                                        ? nowStr
                                        : DateFormat('dd MMM yyyy').format(_lastUpdate!),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _connectionState == 'Terhubung'
                                  ? _getStatusColor()
                                  : Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: _connectionState == 'Terhubung'
                                  ? null
                                  : Border.all(color: Colors.white38),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _connectionState == 'Terhubung' ? _getStatusIcon() : Icons.wifi_off_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _connectionState == 'Terhubung'
                                      ? _status
                                      : 'TERPUTUS ($_status)',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 4. CATEGORY SPECIALTY ICONS GRID (Matching "Doctor Speciality" in Reference UI)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isAdmin ? 'Menu Fitur Admin' : 'Fitur Utama',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Lihat Semua', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 450;
                  final List<Widget> categoryItems = [
                    _buildSpecialtyCategoryItem(
                      label: 'Status Live',
                      icon: Icons.monitor_heart,
                      bgColor: const Color(0xFFEFF6FF),
                      iconColor: AppTheme.primary,
                      isSelected: _selectedIndex == 0,
                      onTap: () => setState(() => _selectedIndex = 0),
                      isCompact: isCompact,
                    ),
                    _buildSpecialtyCategoryItem(
                      label: 'Riwayat Log',
                      icon: Icons.history,
                      bgColor: const Color(0xFFECFDF5),
                      iconColor: AppTheme.success,
                      isSelected: _selectedIndex == 1,
                      onTap: () => setState(() => _selectedIndex = 1),
                      isCompact: isCompact,
                    ),
                    if (isAdmin) ...[
                      _buildSpecialtyCategoryItem(
                        label: 'Kelola User',
                        icon: Icons.people_alt,
                        bgColor: const Color(0xFFF3E8FF),
                        iconColor: const Color(0xFF9333EA),
                        isSelected: _selectedIndex == 2,
                        onTap: () => setState(() => _selectedIndex = 2),
                        isCompact: isCompact,
                      ),
                      _buildSpecialtyCategoryItem(
                        label: 'Laporan',
                        icon: Icons.assessment,
                        bgColor: const Color(0xFFFFFBEB),
                        iconColor: AppTheme.warning,
                        isSelected: _selectedIndex == 3,
                        onTap: () => setState(() => _selectedIndex = 3),
                        isCompact: isCompact,
                      ),
                    ],
                    _buildSpecialtyCategoryItem(
                      label: 'Pengaturan',
                      icon: Icons.settings,
                      bgColor: const Color(0xFFCFFAFE),
                      iconColor: const Color(0xFF0891B2),
                      isSelected: _selectedIndex == (isAdmin ? 4 : 2),
                      onTap: () => setState(() => _selectedIndex = (isAdmin ? 4 : 2)),
                      isCompact: isCompact,
                    ),
                  ];

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: categoryItems.map((item) => Expanded(child: item)).toList(),
                  );
                },
              ),

              const SizedBox(height: 24),

              // 5. METRICS STAT BADGES (Matching "7,500+ Patients" horizontal stats in Reference UI)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.softShadow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricStatItem(
                      title: 'Koneksi Sensor',
                      value: _connectionState,
                      icon: _connectionState == 'Terhubung' ? Icons.wifi : Icons.wifi_off,
                      color: _connectionState == 'Terhubung' ? AppTheme.success : AppTheme.danger,
                    ),
                    Container(height: 32, width: 1, color: AppTheme.border),
                    _buildMetricStatItem(
                      title: 'Deteksi Hari Ini',
                      value: '${_recentLogs.length}+',
                      icon: Icons.dataset,
                      color: AppTheme.primary,
                    ),
                    Container(height: 32, width: 1, color: AppTheme.border),
                    _buildMetricStatItem(
                      title: 'Emergency Fall',
                      value: '${_recentLogs.where((l) => l.status == 'JATUH').length}',
                      icon: Icons.emergency,
                      color: AppTheme.danger,
                    ),
                    Container(height: 32, width: 1, color: AppTheme.border),
                    _buildMetricStatItem(
                      title: 'Role User',
                      value: isAdmin ? 'ADMIN' : 'PEMANTAU',
                      icon: isAdmin ? Icons.admin_panel_settings : Icons.visibility,
                      color: Colors.amber.shade900,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // 6. RECENT ACTIVITY LIST PREVIEW
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Riwayat Log Sensor Terakhir',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedIndex = 1),
                    child: const Text('Buka Riwayat Full', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Builder(
                builder: (context) {
                  final displayLogs = _recentLogs;

                  if (displayLogs.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.sensors, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              const Text(
                                'Menunggu transmisi data dari peranti sensor ESP...',
                                style: TextStyle(color: AppTheme.textSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayLogs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) {
                      final log = displayLogs[idx];
                        Color logColor = AppTheme.success;
                        IconData logIcon = Icons.check_circle;

                        if (log.status == 'JATUH') {
                          logColor = AppTheme.danger;
                          logIcon = Icons.emergency;
                        } else if (log.status == 'CURIGA') {
                          logColor = AppTheme.warning;
                          logIcon = Icons.warning;
                        }

                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: AppTheme.border),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: logColor.withValues(alpha: 0.15),
                              child: Icon(logIcon, color: logColor, size: 20),
                            ),
                            title: Text(
                              'Status: ${log.status}',
                              style: TextStyle(fontWeight: FontWeight.bold, color: logColor),
                            ),
                            subtitle: Text(
                              DateFormat('dd MMM yyyy • HH:mm:ss').format(log.timestamp),
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            trailing: Text(
                              'ID: #${log.id ?? idx + 1}',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                            ),
                          ),
                        );
                      },
                    );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  // Helper specialty category icon widget
  Widget _buildSpecialtyCategoryItem({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
    bool isCompact = false,
  }) {
    final double circleSize = isCompact ? 50.0 : 60.0;
    final double iconSize = isCompact ? 24.0 : 28.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: circleSize,
              width: circleSize,
              decoration: BoxDecoration(
                color: isSelected ? iconColor : bgColor,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [BoxShadow(color: iconColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : iconColor,
                size: iconSize,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isCompact ? 11 : 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper metric stat item
  Widget _buildMetricStatItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 3),
                  Text(
                    value,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // USER PROFILE VIEW
  // --------------------------------------------------------------------------
  void _showEditProfileModal() {
    if (_currentUser == null) return;

    final nameCtrl = TextEditingController(text: _currentUser!.name);
    final emailCtrl = TextEditingController(text: _currentUser!.email);
    final phoneCtrl = TextEditingController(text: _currentUser!.phone);
    final deptCtrl = TextEditingController(text: _currentUser!.department);
    final emergencyCtrl = TextEditingController(text: _currentUser!.emergencyContact);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppTheme.primaryLight,
                          child: Icon(Icons.badge, color: AppTheme.primary),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Edit Detail Profil',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Lengkap', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Nomor HP / Telepon', prefixIcon: Icon(Icons.phone_outlined)),
                ),
                if (_currentUser?.isAdmin ?? false) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: deptCtrl,
                    decoration: const InputDecoration(labelText: 'Unit / Jabatan Pemantauan', prefixIcon: Icon(Icons.domain_outlined)),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: emergencyCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Kontak Darurat Petugas', prefixIcon: Icon(Icons.contact_emergency_outlined)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text('Simpan Perubahan'),
                    onPressed: () async {
                      final updatedUser = _currentUser!.copyWith(
                        name: nameCtrl.text.trim(),
                        email: emailCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        department: (_currentUser?.isAdmin ?? false) ? deptCtrl.text.trim() : '',
                        emergencyContact: emergencyCtrl.text.trim(),
                      );
                      await AuthService.updateUser(updatedUser);
                      setState(() {
                        _currentUser = updatedUser;
                      });
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (context.mounted) {
                        AppSnackBar.success(context, 'Detail profil berhasil diperbarui!');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileTile({
    required IconData icon,
    required String label,
    required String value,
    Color iconColor = AppTheme.primary,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: iconColor.withValues(alpha: 0.12),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 1),
                Text(
                  value.isNotEmpty ? value : '-',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView() {
    final isAdmin = _currentUser?.isAdmin ?? false;

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: Colors.white,
      onRefresh: () async {
        await _loadUser();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              // Header Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: AppTheme.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 46,
                            backgroundColor: isAdmin ? Colors.amber.shade100 : AppTheme.primaryLight,
                            child: Text(
                              _currentUser?.name.isNotEmpty == true ? _currentUser!.name[0].toUpperCase() : 'U',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: isAdmin ? Colors.amber.shade900 : AppTheme.primary,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: InkWell(
                              onTap: _showEditProfileModal,
                              borderRadius: BorderRadius.circular(20),
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: AppTheme.primary,
                                child: const Icon(Icons.edit, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _currentUser?.name ?? 'Pengguna FallSafe',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${_currentUser?.username ?? 'user'}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(
                            avatar: Icon(
                              isAdmin ? Icons.admin_panel_settings : Icons.visibility,
                              size: 16,
                              color: isAdmin ? Colors.amber.shade900 : AppTheme.primary,
                            ),
                            label: Text(
                              isAdmin ? 'ROLE: ADMINISTRATOR UTAMA' : 'ROLE: PETUGAS PEMANTAU (VIEWER)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isAdmin ? Colors.amber.shade900 : AppTheme.primary,
                              ),
                            ),
                            backgroundColor: isAdmin ? Colors.amber.shade50 : AppTheme.primaryLight,
                          ),
                          Chip(
                            avatar: const Icon(Icons.check_circle, size: 14, color: AppTheme.success),
                            label: const Text(
                              'AKUN AKTIF',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.success),
                            ),
                            backgroundColor: AppTheme.successBg,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Detail Informasi Profil Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: AppTheme.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.badge_outlined, color: AppTheme.primary, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Informasi Detail Akun',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _showEditProfileModal,
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildProfileTile(
                        icon: Icons.email_outlined,
                        label: 'Alamat Email',
                        value: _currentUser?.email.isNotEmpty == true ? _currentUser!.email : 'Belum diisi',
                        iconColor: AppTheme.primary,
                      ),
                      _buildProfileTile(
                        icon: Icons.phone_outlined,
                        label: 'Nomor Telepon / HP',
                        value: _currentUser?.phone.isNotEmpty == true ? _currentUser!.phone : 'Belum diisi',
                        iconColor: AppTheme.success,
                      ),
                      if (isAdmin)
                        _buildProfileTile(
                          icon: Icons.domain_outlined,
                          label: 'Unit / Jabatan Pemantauan',
                          value: _currentUser?.department.isNotEmpty == true ? _currentUser!.department : 'Manajemen IT & Admin RS',
                          iconColor: Colors.amber.shade900,
                        ),
                      _buildProfileTile(
                        icon: Icons.contact_emergency_outlined,
                        label: 'Kontak Darurat Petugas',
                        value: _currentUser?.emergencyContact.isNotEmpty == true ? _currentUser!.emergencyContact : 'Belum diisi',
                        iconColor: AppTheme.danger,
                      ),
                      _buildProfileTile(
                        icon: Icons.calendar_today_outlined,
                        label: 'Terdaftar Sejak',
                        value: _currentUser != null && _currentUser!.createdAt.isNotEmpty
                            ? _currentUser!.formattedCreatedAt
                            : '-',
                        iconColor: Colors.purple,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Hak Akses & Wewenang System Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: AppTheme.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isAdmin ? Icons.verified_user_outlined : Icons.shield_outlined,
                            color: isAdmin ? Colors.amber.shade900 : AppTheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isAdmin ? 'Wewenang & Akses Administrator' : 'Fungsi & Hak Akses Pemantau',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isAdmin) ...[
                        _buildPrivilegeBullet('Manajemen Akun User (Tambah, Edit, Reset Password, Hapus)'),
                        _buildPrivilegeBullet('Konfigurasi Endpoint WebSocket Wemos ESP8266'),
                        _buildPrivilegeBullet('Ekspor & Cetak Laporan Analytics Deteksi Jatuh (PDF/Print)'),
                        _buildPrivilegeBullet('Manajemen & Reset Seluruh Database Riwayat Sensor'),
                      ] else ...[
                        _buildPrivilegeBullet('Pemantauan Status Sensor Live secara Real-Time'),
                        _buildPrivilegeBullet('Penerimaan Notifikasi & Audio Alarm Bahaya Jatuh'),
                        _buildPrivilegeBullet('Auto-Call Kontak Darurat saat Emergency Fall Detected'),
                        _buildPrivilegeBullet('Akses Riwayat Deteksi & Pencarian Filter Status Log'),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Logout Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Keluar dari Akun', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  onPressed: _handleLogout,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildPrivilegeBullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // Get view based on selected tab & role
  Widget _getMainContent(bool isAdmin) {
    if (isAdmin) {
      switch (_selectedIndex) {
        case 0:
          return _buildDashboardContent(isAdmin);
        case 1:
          return const HistoryScreen();
        case 2:
          return const UserManagementScreen(); // Kelola User
        case 3:
          return const ReportsScreen(); // Laporan & Analytics
        case 4:
          return const SettingsScreen(isAdmin: true); // Pengaturan
        case 5:
          return _buildProfileView();
        default:
          return _buildDashboardContent(isAdmin);
      }
    } else {
      // Pemantau / Viewer Role
      switch (_selectedIndex) {
        case 0:
          return _buildDashboardContent(isAdmin);
        case 1:
          return const HistoryScreen();
        case 2:
          return const SettingsScreen(isAdmin: false);
        case 3:
          return _buildProfileView();
        default:
          return _buildDashboardContent(isAdmin);
      }
    }
  }

  String _getPageTitle(bool isAdmin) {
    if (isAdmin) {
      switch (_selectedIndex) {
        case 0:
          return 'Dashboard Sensor Live';
        case 1:
          return 'Riwayat Log Sensor';
        case 2:
          return 'Kelola User & Role Admin';
        case 3:
          return 'Laporan & Analytics';
        case 4:
          return 'Pengaturan Sistem';
        case 5:
          return 'Profil Saya';
        default:
          return 'FallSafe Admin';
      }
    } else {
      switch (_selectedIndex) {
        case 0:
          return 'Dashboard Live';
        case 1:
          return 'Riwayat Deteksi';
        case 2:
          return 'Pengaturan Aplikasi';
        case 3:
          return 'Profil Saya';
        default:
          return 'FallSafe';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 768;
    final isAdmin = _currentUser?.isAdmin ?? false;

    // 💻 DESKTOP LAYOUT (WITH SLEEK SIDEBAR)
    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Row(
          children: [
            // Sidebar Navigation
            Container(
              width: 270,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                children: [
                  // App Brand Box
                  Container(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.asset(
                              'assets/images/app_logo.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.health_and_safety, color: AppTheme.primary, size: 28),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FallSafe',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              'Smart Fall Monitoring',
                              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, color: AppTheme.border),

                  // Menu Items
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      children: [
                        _buildSidebarMenuItem(
                          index: 0,
                          icon: Icons.grid_view,
                          title: 'Dashboard Utama',
                        ),
                        _buildSidebarMenuItem(
                          index: 1,
                          icon: Icons.history,
                          title: 'Riwayat Sensor',
                        ),
                        if (isAdmin) ...[
                          const SizedBox(height: 12),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Text('ADMINISTRATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                          ),
                          _buildSidebarMenuItem(
                            index: 2,
                            icon: Icons.people_alt_outlined,
                            title: 'Kelola User',
                          ),
                          _buildSidebarMenuItem(
                            index: 3,
                            icon: Icons.assessment_outlined,
                            title: 'Laporan & Analytics',
                          ),
                          _buildSidebarMenuItem(
                            index: 4,
                            icon: Icons.settings_outlined,
                            title: 'Pengaturan System',
                          ),
                        ] else ...[
                          _buildSidebarMenuItem(
                            index: 2,
                            icon: Icons.settings_outlined,
                            title: 'Pengaturan Aplikasi',
                          ),
                        ],
                        const SizedBox(height: 12),
                        _buildSidebarMenuItem(
                          index: isAdmin ? 5 : 3,
                          icon: Icons.person_outline,
                          title: 'Profil Saya',
                        ),
                      ],
                    ),
                  ),

                  // User Info Footer Box
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: isAdmin ? Colors.amber.shade100 : AppTheme.primaryLight,
                          child: Text(
                            _currentUser?.name.isNotEmpty == true ? _currentUser!.name[0].toUpperCase() : 'U',
                            style: TextStyle(fontWeight: FontWeight.bold, color: isAdmin ? Colors.amber.shade900 : AppTheme.primary),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentUser?.name ?? 'User',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                isAdmin ? 'ADMIN' : 'PEMANTAU',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isAdmin ? Colors.amber.shade900 : AppTheme.primary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, size: 18, color: AppTheme.danger),
                          onPressed: _handleLogout,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Main Desktop Page Content
            Expanded(
              child: Scaffold(
                backgroundColor: AppTheme.background,
                appBar: AppBar(
                  title: Text(_getPageTitle(isAdmin)),
                ),
                body: _getMainContent(isAdmin),
              ),
            ),
          ],
        ),
      );
    }

    // 📱 MOBILE LAYOUT (WITH BOTTOM NAVIGATION BAR)
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.health_and_safety, color: AppTheme.primary, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _getPageTitle(isAdmin),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Profil Saya',
              icon: const Icon(Icons.account_circle_outlined, color: AppTheme.primary),
              onPressed: () => setState(() => _selectedIndex = isAdmin ? 5 : 3),
            ),
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout, color: AppTheme.danger),
              onPressed: _handleLogout,
            ),
          ],
        ),
        body: _getMainContent(isAdmin),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Colors.white,
          currentIndex: _selectedIndex > (isAdmin ? 4 : 3) ? 0 : _selectedIndex,
          onTap: _onTabChanged,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textMuted,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          items: isAdmin
              ? const [
                  BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Dashboard'),
                  BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
                  BottomNavigationBarItem(icon: Icon(Icons.people_alt), label: 'User'),
                  BottomNavigationBarItem(icon: Icon(Icons.assessment), label: 'Laporan'),
                  BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Setting'),
                ]
              : const [
                  BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Dashboard'),
                  BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
                  BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Setting'),
                  BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
                ],
        ),
      ),
    );
  }

  Widget _buildSidebarMenuItem({
    required int index,
    required IconData icon,
    required String title,
  }) {
    final isSelected = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: isSelected,
        selectedTileColor: AppTheme.primaryLight,
        leading: Icon(
          icon,
          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
            fontSize: 14,
          ),
        ),
        onTap: () => _onTabChanged(index),
      ),
    );
  }
}