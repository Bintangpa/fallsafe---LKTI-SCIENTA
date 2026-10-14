import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;

  // Key SharedPreferences
  static const String _keyUsername = 'auth_username';
  static const String _keyName = 'auth_name';
  static const String _keyRole = 'auth_role';
  static const String _keyEmail = 'auth_email';
  static const String _keyPhone = 'auth_phone';
  static const String _keyDepartment = 'auth_department';
  static const String _keyEmergencyContact = 'auth_emergency_contact';
  static const String _keyCreatedAt = 'auth_created_at';

  // Demo Fallback Users with Detailed Profiles
  static final List<AppUser> _localFallbackUsers = [
    AppUser(
      id: 1,
      username: 'admin',
      name: 'Administrator Utama',
      role: 'admin',
      email: 'admin@fallsafe.io',
      status: 'Aktif',
      phone: '+62 812-3456-7890',
      department: 'Manajemen Sistem & IT RS',
      emergencyContact: '+62 811-9999-0000',
      createdAt: '2025-01-15T08:00:00Z',
    ),
    AppUser(
      id: 2,
      username: 'pemantau',
      name: 'Petugas Pemantau',
      role: 'viewer',
      email: 'pemantau@fallsafe.io',
      status: 'Aktif',
      phone: '+62 857-1122-3344',
      department: '',
      emergencyContact: '+62 821-4433-2211',
      createdAt: '2025-02-01T08:00:00Z',
    ),
    AppUser(
      id: 3,
      username: 'dr_john',
      name: 'Dr. Jonny Wilson',
      role: 'admin',
      email: 'j.wilson@fallsafe.io',
      status: 'Aktif',
      phone: '+62 813-9876-5432',
      department: 'Kepala Tim Dokter Spesialis',
      emergencyContact: '+62 812-0000-1111',
      createdAt: '2025-02-10T08:00:00Z',
    ),
    AppUser(
      id: 4,
      username: 'perawat_elena',
      name: 'Elena Henry',
      role: 'viewer',
      email: 'elena@fallsafe.io',
      status: 'Aktif',
      phone: '+62 818-5544-3322',
      department: 'Perawat Jaga Shift Pagi',
      emergencyContact: '+62 819-7766-5544',
      createdAt: '2025-02-20T08:00:00Z',
    ),
  ];

  // Login dengan Username & Password dari Supabase
  static Future<AppUser?> login(String username, String password) async {
    try {
      final response = await _client
          .from('users')
          .select()
          .eq('username', username)
          .eq('password', password)
          .maybeSingle();

      if (response != null) {
        final user = AppUser.fromMap(response);
        await saveSession(user);
        return user;
      }
    } catch (e) {
      print('⚠️ Login error Supabase, checking local fallback: $e');
    }

    // Local fallback login for demo accounts if DB query fails or user isn't in DB yet
    if ((username == 'admin' && password == 'admin123') || (username == 'pemantau' && password == 'user123')) {
      final user = _localFallbackUsers.firstWhere(
        (u) => u.username == username,
        orElse: () => AppUser(
          id: username == 'admin' ? 1 : 2,
          username: username,
          name: username == 'admin' ? 'Administrator Utama' : 'Petugas Pemantau',
          role: username == 'admin' ? 'admin' : 'viewer',
          email: '$username@fallsafe.io',
          phone: username == 'admin' ? '+62 812-3456-7890' : '+62 857-1122-3344',
          department: username == 'admin' ? 'Manajemen Sistem & IT' : 'Bangsal Pemantauan Lansia',
          emergencyContact: '+62 811-9999-0000',
          createdAt: username == 'admin' ? '2025-01-15T08:00:00Z' : '2025-02-01T08:00:00Z',
        ),
      );
      await saveSession(user);
      return user;
    }

    return null;
  }

  // Simpan Sesi Login ke SharedPreferences
  static Future<void> saveSession(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, user.username);
    await prefs.setString(_keyName, user.name);
    await prefs.setString(_keyRole, user.role);
    await prefs.setString(_keyEmail, user.email);
    await prefs.setString(_keyPhone, user.phone);
    await prefs.setString(_keyDepartment, user.department);
    await prefs.setString(_keyEmergencyContact, user.emergencyContact);
    await prefs.setString(_keyCreatedAt, user.createdAt);
  }

  // Ambil Sesi User Terlogin
  static Future<AppUser?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_keyUsername);
    final role = prefs.getString(_keyRole);

    if (username == null || role == null) {
      return null;
    }

    final savedName = prefs.getString(_keyName);
    final savedEmail = prefs.getString(_keyEmail);
    final savedPhone = prefs.getString(_keyPhone);
    final savedDepartment = prefs.getString(_keyDepartment);
    final savedEmergency = prefs.getString(_keyEmergencyContact);
    final savedCreatedAt = prefs.getString(_keyCreatedAt);

    final matchedIndex = _localFallbackUsers.indexWhere((u) => u.username == username);
    final matched = matchedIndex != -1 ? _localFallbackUsers[matchedIndex] : null;

    return AppUser(
      id: matched?.id,
      username: username,
      name: (savedName != null && savedName.isNotEmpty) ? savedName : (matched?.name ?? username),
      role: role,
      email: (savedEmail != null && savedEmail.isNotEmpty) ? savedEmail : (matched?.email ?? ''),
      phone: (savedPhone != null && savedPhone.isNotEmpty) ? savedPhone : (matched?.phone ?? ''),
      department: (role == 'admin')
          ? ((savedDepartment != null && savedDepartment.isNotEmpty) ? savedDepartment : (matched?.department ?? ''))
          : '',
      emergencyContact: (savedEmergency != null && savedEmergency.isNotEmpty) ? savedEmergency : (matched?.emergencyContact ?? ''),
      createdAt: (savedCreatedAt != null && savedCreatedAt.isNotEmpty) ? savedCreatedAt : (matched?.createdAt ?? '2025-02-01T08:00:00Z'),
    );
  }

  // Logout (Hapus Sesi Login)
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyName);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyPhone);
    await prefs.remove(_keyDepartment);
    await prefs.remove(_keyEmergencyContact);
    await prefs.remove(_keyCreatedAt);
  }

  // Ambil Semua User (untuk kelola user admin)
  static Future<List<AppUser>> getAllUsers() async {
    try {
      final response = await _client.from('users').select().order('id', ascending: true);
      final list = response as List<dynamic>;
      if (list.isNotEmpty) {
        return list.map((map) => AppUser.fromMap(map as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('⚠️ Gagal ambil user dari Supabase: $e');
    }
    return List.from(_localFallbackUsers);
  }

  // Tambah User Baru
  static Future<bool> createUser({
    required String username,
    required String password,
    required String name,
    required String role,
    required String email,
    String phone = '',
    String department = '',
    String emergencyContact = '',
  }) async {
    final createdAtIso = DateTime.now().toIso8601String();
    final newUserMap = {
      'username': username,
      'password': password,
      'name': name,
      'role': role,
      'email': email,
      'phone': phone,
      'department': department,
      'emergency_contact': emergencyContact,
      'status': 'Aktif',
      'created_at': createdAtIso,
    };

    try {
      await _client.from('users').insert(newUserMap);
    } catch (e) {
      print('⚠️ Supabase insert user failed, adding to local fallback: $e');
    }

    _localFallbackUsers.add(AppUser(
      id: DateTime.now().millisecondsSinceEpoch,
      username: username,
      name: name,
      role: role,
      email: email,
      status: 'Aktif',
      phone: phone,
      department: department,
      emergencyContact: emergencyContact,
      createdAt: createdAtIso,
    ));
    return true;
  }

  // Update User
  static Future<bool> updateUser(AppUser user) async {
    final updateData = {
      'name': user.name,
      'role': user.role,
      'email': user.email,
      'status': user.status,
      'phone': user.phone,
      'department': user.department,
      'emergency_contact': user.emergencyContact,
    };

    try {
      if (user.id != null) {
        await _client.from('users').update(updateData).eq('id', user.id!);
      } else {
        await _client.from('users').update(updateData).eq('username', user.username);
      }
      print('✅ Supabase user update succeed for ${user.username}');
    } catch (e) {
      print('⚠️ Supabase update user error: $e');
    }

    final index = _localFallbackUsers.indexWhere((u) => u.username == user.username || u.id == user.id);
    if (index != -1) {
      _localFallbackUsers[index] = user;
    }

    // Always persist updated user data to local session
    await saveSession(user);

    return true;
  }

  // Hapus User
  static Future<bool> deleteUser(int id) async {
    try {
      await _client.from('users').delete().eq('id', id);
    } catch (e) {
      print('⚠️ Supabase delete user error: $e');
    }
    _localFallbackUsers.removeWhere((u) => u.id == id);
    return true;
  }
}
