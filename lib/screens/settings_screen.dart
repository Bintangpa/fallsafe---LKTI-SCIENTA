import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/mdns_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snackbar.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool? isAdmin;
  const SettingsScreen({super.key, this.isAdmin});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _wsController = TextEditingController(text: MdnsService.defaultEndpoint);
  AppUser? _currentUser;
  bool _enableVibration = true;
  bool _enableSoundAlarm = true;
  bool _isLoading = false;
  bool _isScanningMdns = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _scanMdns() async {
    setState(() => _isScanningMdns = true);
    try {
      final result = await MdnsService.discoverSensor(hostname: MdnsService.defaultHostname, port: MdnsService.defaultPort);
      if (!mounted) return;
      setState(() {
        _wsController.text = result.wsUrl;
        _isScanningMdns = false;
      });

      if (result.success) {
        AppSnackBar.success(context, result.message);
      } else {
        AppSnackBar.info(context, '${result.message} Diatur ke default: ${result.wsUrl}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanningMdns = false);
      AppSnackBar.error(context, 'Pencarian mDNS gagal: $e');
    }
  }

  @override
  void dispose() {
    _wsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Prioritaskan pembacaan dari memori lokal HP (Instan 0ms tanpa menunggu internet)
    final localWsUrl = prefs.getString('ws_url');
    final localSound = prefs.getBool('enable_sound_alarm');
    final localVib = prefs.getBool('enable_vibration');
    final user = await AuthService.getCurrentUser();

    if (mounted) {
      setState(() {
        if (localWsUrl != null && localWsUrl.isNotEmpty) {
          _wsController.text = localWsUrl;
        }
        if (localSound != null) {
          _enableSoundAlarm = localSound;
        }
        if (localVib != null) {
          _enableVibration = localVib;
        }
        _currentUser = user;
        _isLoading = false;
      });
    }

    // 2. Sinkronisasi cloud di latar belakang hanya jika preferensi lokal masih kosong
    if (localSound == null || localVib == null || localWsUrl == null) {
      try {
        final data = await DatabaseService.getSettings().timeout(const Duration(seconds: 1));
        if (data != null && mounted) {
          setState(() {
            if ((localWsUrl == null || localWsUrl.isEmpty) && data['ws_url'] != null) {
              _wsController.text = data['ws_url'];
              prefs.setString('ws_url', data['ws_url']);
            }
            if (localSound == null && data['enable_sound_alarm'] != null) {
              _enableSoundAlarm = data['enable_sound_alarm'] == true;
              prefs.setBool('enable_sound_alarm', _enableSoundAlarm);
            }
            if (localVib == null && data['enable_vibration'] != null) {
              _enableVibration = data['enable_vibration'] == true;
              prefs.setBool('enable_vibration', _enableVibration);
            }
          });
        }
      } catch (_) {}
    }
  }

  // Simpan otomatis ke penyimpanan lokal seketika saat tombol switch digeser
  Future<void> _toggleSoundAlarm(bool val) async {
    setState(() => _enableSoundAlarm = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_sound_alarm', val);
    if (!val) {
      // Jika dimatikan, segera hentikan audio alarm yang mungkin sedang berbunyi
      await NotificationService.stopAlarmSound();
    }
  }

  // Simpan otomatis ke penyimpanan lokal seketika saat tombol switch digeser
  Future<void> _toggleVibration(bool val) async {
    setState(() => _enableVibration = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_vibration', val);
    if (!val) {
      // Jika dimatikan, segera hentikan getaran perangkat
      await NotificationService.stopAlarm();
    }
  }

  Future<void> _saveSettings() async {
    final wsUrlTrimmed = _wsController.text.trim();
    final prefs = await SharedPreferences.getInstance();

    // 1. Simpan instan ke penyimpanan lokal HP (Pasti tersimpan & tidak terganggu koneksi offline)
    await prefs.setString('ws_url', wsUrlTrimmed);
    await prefs.setBool('enable_sound_alarm', _enableSoundAlarm);
    await prefs.setBool('enable_vibration', _enableVibration);

    if (mounted) {
      AppSnackBar.success(context, 'Pengaturan berhasil disimpan ke HP!');
    }

    // Beritahu background foreground task agar segera beralih ke endpoint baru
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      FlutterForegroundTask.sendDataToTask({'action': 'reconnect', 'ws_url': wsUrlTrimmed});
    }

    // 2. Sinkronkan ke Supabase Cloud di latar belakang (tidak memblokir tombol simpan)
    DatabaseService.saveSettings(
      wsUrl: wsUrlTrimmed,
      enableSoundAlarm: _enableSoundAlarm,
      enableVibration: _enableVibration,
    ).timeout(const Duration(seconds: 2)).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.isAdmin ?? (_currentUser?.isAdmin ?? false);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: Colors.white,
        onRefresh: _loadSettings,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Settings Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: isAdmin ? Colors.amber.shade100 : AppTheme.primaryLight,
                        child: Icon(
                          isAdmin ? Icons.admin_panel_settings : Icons.settings,
                          color: isAdmin ? Colors.amber.shade900 : AppTheme.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAdmin ? 'Pengaturan Sistem & Keamanan (Role Admin)' : 'Pengaturan Notifikasi & Aplikasi',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                            Text(
                              isAdmin
                                  ? 'Konfigurasi endpoint sensor, pemantauan sistem, dan manajemen keamanan server.'
                                  : 'Atur preferensi alarm suara dan getaran perangkat saat status darurat.',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Connection Settings Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: AppTheme.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.wifi_tethering, color: AppTheme.primary),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Koneksi Endpoint Sensor (mDNS / Wi-Fi)',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                            ),
                            if (isAdmin)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.successBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                                ),
                                child: const Text(
                                  'mDNS Aktif',
                                  style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _wsController,
                          enabled: isAdmin,
                          decoration: InputDecoration(
                            labelText: 'WebSocket Server Endpoint URL',
                            hintText: 'ws://fallsafe.local:81',
                            prefixIcon: const Icon(Icons.link),
                            helperText: isAdmin
                                ? 'Direkomendasikan menggunakan domain mDNS ws://fallsafe.local:81'
                                : 'Endpoint ini dikonfigurasi oleh Administrator Utama.',
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.5),
                                side: const BorderSide(color: AppTheme.primary, width: 1.2),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isScanningMdns ? null : _scanMdns,
                              icon: _isScanningMdns
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                                    )
                                  : const Icon(Icons.radar_rounded, size: 20),
                              label: Text(
                                _isScanningMdns ? 'Mencari Sensor via mDNS...' : 'Deteksi Otomatis Sensor (mDNS / NSD)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                avatar: const Icon(Icons.auto_awesome, size: 16, color: AppTheme.primary),
                                label: const Text('fallsafe.local (mDNS Otomatis)', style: TextStyle(fontSize: 12)),
                                backgroundColor: AppTheme.primaryLight,
                                onPressed: () {
                                  setState(() => _wsController.text = 'ws://fallsafe.local:81');
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.router, size: 16, color: AppTheme.textSecondary),
                                label: const Text('192.168.4.1 (AP Mode)', style: TextStyle(fontSize: 12)),
                                backgroundColor: Colors.grey.shade100,
                                onPressed: () {
                                  setState(() => _wsController.text = 'ws://192.168.4.1:81');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: AppTheme.textSecondary),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Dengan mDNS (fallsafe.local), Anda tidak perlu mengisi IP manual. Aplikasi akan otomatis menemukan IP sensor di jaringan Wi-Fi.',
                                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // If Admin: System Security & Admin Control Info Card
                if (isAdmin)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shield_outlined, color: Colors.amber.shade900),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Mode Pengawasan System Administrator',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ℹ️ Kebijakan Notifikasi Role Admin:',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  '• Akun Administrator tidak akan diganggu oleh suara sirine paksa, getaran berulang, atau popup alarm yang mengunci layar.\n'
                                  '• Setiap insiden deteksi jatuh tetap tercatat secara otomatis dan real-time di Riwayat Log Sensor.\n'
                                  '• Pengaturan alarm suara dan getaran dikhususkan bagi role Petugas Pemantau.',
                                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // If Not Admin (Pemantau / Viewer): Show Alarm & Emergency Settings Card
                if (!isAdmin)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.notifications_active, color: AppTheme.danger),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Notifikasi & Peringatan Darurat',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            title: const Text('Suara Sirine Alarm Darurat'),
                            subtitle: const Text('Mainkan nada sirine saat sensor mendeteksi status JATUH'),
                            value: _enableSoundAlarm,
                            activeTrackColor: AppTheme.primary,
                            onChanged: _toggleSoundAlarm,
                          ),
                          const Divider(),
                          SwitchListTile(
                            title: const Text('Getaran HP / Vibrate'),
                            subtitle: const Text('Getarkan perangkat secara terus menerus saat alert aktif'),
                            value: _enableVibration,
                            activeTrackColor: AppTheme.primary,
                            onChanged: _toggleVibration,
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;

                    final saveBtn = SizedBox(
                      width: isMobile ? double.infinity : null,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        onPressed: _isLoading ? null : _saveSettings,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isLoading ? 'Menyimpan...' : 'Simpan Pengaturan'),
                      ),
                    );

                    final logoutBtn = SizedBox(
                      width: isMobile ? double.infinity : null,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          await AuthService.logout();
                          if (context.mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                            );
                          }
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Keluar (Logout)'),
                      ),
                    );

                    if (isMobile) {
                      return Column(
                        children: [
                          saveBtn,
                          const SizedBox(height: 12),
                          logoutBtn,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: saveBtn),
                        const SizedBox(width: 12),
                        logoutBtn,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
