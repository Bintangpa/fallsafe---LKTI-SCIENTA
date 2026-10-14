import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sensor_log.dart';

class DatabaseService {
  // 🔑 GANTI SESUAI DENGAN PROJECT URL DAN ANON KEY SUPABASE ANDA
  static const String supabaseUrl = 'https://yjajzvirrzrkszmeyccn.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlqYWp6dmlycnpya3N6bWV5Y2NuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA4NzY2NDYsImV4cCI6MjEwNjQ1MjY0Nn0.x87omanoFEvs2nVWlRO3WAckG8wA59SBXikvk39USn4';

  static SupabaseClient get client => Supabase.instance.client;

  // Cache status terakhir yang tersimpan di DB
  static String? _lastRecordedStatus;
  static DateTime? _lastRecordedTime;

  // Inisialisasi Supabase (dipanggil di main.dart dan background task)
  static Future<void> init() async {
    try {
      Supabase.instance.client;
    } catch (_) {
      try {
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseAnonKey,
        ).timeout(const Duration(seconds: 4));
        print('✅ Supabase Berhasil Diinisialisasi');
      } catch (e) {
        print('⚠️ Supabase initialize error: $e');
      }
    }

    // Muat status terakhir dari DB dengan timeout pengaman agar tidak memblokir render UI
    try {
      final latestLog = await getLatestLog().timeout(const Duration(seconds: 2));
      if (latestLog != null) {
        _lastRecordedStatus = latestLog.status;
        _lastRecordedTime = latestLog.timestamp;
        print('ℹ️ Status terakhir dari DB: $_lastRecordedStatus (waktu: $_lastRecordedTime)');
      }
    } catch (e) {
      print('ℹ️ Status log awal dilewati: $e');
    }
  }

  // Simpan log jika:
  // 1. Status BERUBAH dari status terakhir (simpan segera / instan), ATAU
  // 2. Status SAMA tapi sudah lewat >= 1 menit sejak penyimpanan terakhir (rekam berkala per menit)
  static Future<bool> insertLog(SensorLog log, {bool forceInsert = false}) async {
    if (!forceInsert) {
      final isStatusChanged = _lastRecordedStatus != log.status;
      final elapsedSinceLastSave = _lastRecordedTime == null
          ? const Duration(days: 999) // Belum pernah simpan, langsung simpan
          : log.timestamp.difference(_lastRecordedTime!);
      final isOneMinutePassed = elapsedSinceLastSave.inSeconds >= 60;

      // ✋ Lewati penyimpanan jika status SAMA dan belum lewat 1 menit
      if (!isStatusChanged && !isOneMinutePassed) {
        return false;
      }

      if (isStatusChanged) {
        print('🔄 Status BERUBAH: $_lastRecordedStatus → ${log.status} — simpan segera');
      } else {
        print('⏱️ Status SAMA (${log.status}) — simpan berkala (${elapsedSinceLastSave.inSeconds}s)');
      }
    }

    try {
      await client.from('sensor_logs').insert({
        'status': log.status,
        'timestamp': log.timestamp.toIso8601String(),
      });

      _lastRecordedStatus = log.status;
      _lastRecordedTime = log.timestamp;
      print('✅ Log tersimpan ke Supabase: ${log.status}');
      return true;
    } catch (e) {
      print('❌ Gagal simpan log ke Supabase: $e');
      return false;
    }
  }

  // Ambil semua log (terbaru di atas)
  static Future<List<SensorLog>> getAllLogs() async {
    try {
      final response = await client
          .from('sensor_logs')
          .select()
          .order('timestamp', ascending: false);

      final list = response as List<dynamic>;
      return list
          .map((map) => SensorLog.fromMap(map as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Gagal ambil log dari Supabase: $e');
      return [];
    }
  }

  // Stream data log sensor secara REALTIME dari Internet (Supabase Cloud)
  static Stream<List<SensorLog>> streamLogs() {
    return client
        .from('sensor_logs')
        .stream(primaryKey: ['id'])
        .order('timestamp', ascending: false)
        .map((maps) => maps.map((map) => SensorLog.fromMap(map)).toList());
  }

  // Ambil log terakhir
  static Future<SensorLog?> getLatestLog() async {
    try {
      final response = await client
          .from('sensor_logs')
          .select()
          .order('timestamp', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return SensorLog.fromMap(response);
    } catch (e) {
      print('❌ Gagal ambil log terbaru dari Supabase: $e');
      return null;
    }
  }

  // Hitung total log
  static Future<int> countLogs() async {
    try {
      final response = await client.from('sensor_logs').select('id');
      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  // Hapus semua log
  static Future<void> clearAll() async {
    try {
      await client.from('sensor_logs').delete().neq('id', 0);
      _lastRecordedStatus = null;
      _lastRecordedTime = null;
      print('✅ Semua log di Supabase berhasil dihapus & cache status di-reset');
    } catch (e) {
      print('❌ Gagal hapus log Supabase: $e');
    }
  }

  // Ambil pengaturan sistem dari Supabase app_settings
  static Future<Map<String, dynamic>?> getSettings() async {
    try {
      final response = await client
          .from('app_settings')
          .select()
          .eq('id', 1)
          .maybeSingle();
      return response;
    } catch (e) {
      print('⚠️ Gagal ambil settings dari Supabase: $e');
      return null;
    }
  }

  // Simpan/update pengaturan sistem ke Supabase app_settings
  static Future<bool> saveSettings({
    required String wsUrl,
    String emergencyPhone = '',
    required bool enableSoundAlarm,
    required bool enableVibration,
    bool autoCallEmergency = false,
  }) async {
    try {
      await client.from('app_settings').upsert({
        'id': 1,
        'ws_url': wsUrl,
        'emergency_phone': emergencyPhone,
        'enable_sound_alarm': enableSoundAlarm,
        'enable_vibration': enableVibration,
        'auto_call_emergency': autoCallEmergency,
        'updated_at': DateTime.now().toIso8601String(),
      }).timeout(const Duration(seconds: 4));
      print('✅ Pengaturan berhasil tersimpan ke Supabase');
      return true;
    } catch (e) {
      print('❌ Gagal simpan settings ke Supabase: $e');
      return false;
    }
  }
}