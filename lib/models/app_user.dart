import 'package:intl/intl.dart';

class AppUser {
  final int? id;
  final String username;
  final String name;
  final String role; // 'admin' atau 'viewer'
  final String email;
  final String status; // 'Aktif' atau 'Nonaktif'
  final String phone;
  final String department;
  final String emergencyContact;
  final String createdAt;

  AppUser({
    this.id,
    required this.username,
    required this.name,
    required this.role,
    this.email = '',
    this.status = 'Aktif',
    this.phone = '',
    this.department = '',
    this.emergencyContact = '',
    this.createdAt = '',
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] is int
          ? map['id']
          : (map['id'] != null ? int.tryParse(map['id'].toString()) : null),
      username: map['username'] ?? '',
      name: map['name'] ?? map['username'] ?? 'User',
      role: map['role'] ?? 'viewer',
      email: map['email'] ?? '',
      status: map['status'] ?? 'Aktif',
      phone: map['phone'] ?? map['no_hp'] ?? '',
      department: map['department'] ?? map['jabatan'] ?? '',
      emergencyContact: map['emergency_contact'] ?? map['kontak_darurat'] ?? '',
      createdAt: map['created_at'] ?? map['created_at_str'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'username': username,
      'name': name,
      'role': role,
      'email': email,
      'status': status,
      'phone': phone,
      'department': department,
      'emergency_contact': emergencyContact,
      'created_at': createdAt,
    };
  }

  AppUser copyWith({
    int? id,
    String? username,
    String? name,
    String? role,
    String? email,
    String? status,
    String? phone,
    String? department,
    String? emergencyContact,
    String? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      role: role ?? this.role,
      email: email ?? this.email,
      status: status ?? this.status,
      phone: phone ?? this.phone,
      department: department ?? this.department,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isAdmin => role.toLowerCase() == 'admin';

  /// Format tanggal terdaftar hanya sampai tanggal, bulan, dan tahun (tanpa jam/menit/detik/timezone).
  /// Contoh output: "02 Oktober 2026"
  String get formattedCreatedAt {
    if (createdAt.trim().isEmpty) return '-';
    
    // Parsing format ISO 8601 (contoh: 2026-10-02T02:12:26.134241+00:00)
    final parsed = DateTime.tryParse(createdAt.trim());
    if (parsed != null) {
      try {
        return DateFormat('dd MMMM yyyy', 'id_ID').format(parsed.toLocal());
      } catch (_) {
        return DateFormat('dd MMMM yyyy').format(parsed.toLocal());
      }
    }

    // Parsing format tanggal lama (contoh: "15 Jan 2025" atau "01 Feb 2025")
    try {
      final legacy = DateFormat('dd MMM yyyy').tryParse(createdAt.trim());
      if (legacy != null) {
        try {
          return DateFormat('dd MMMM yyyy', 'id_ID').format(legacy);
        } catch (_) {
          return DateFormat('dd MMMM yyyy').format(legacy);
        }
      }
    } catch (_) {}

    return createdAt;
  }
}
