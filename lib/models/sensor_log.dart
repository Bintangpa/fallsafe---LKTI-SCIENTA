class SensorLog {
  final int? id;
  final String status;
  final DateTime timestamp;

  SensorLog({
    this.id,
    required this.status,
    required this.timestamp,
  });

  // Konversi ke Map (untuk simpan ke database Supabase)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // Konversi dari Map (untuk baca dari database Supabase)
  factory SensorLog.fromMap(Map<String, dynamic> map) {
    DateTime parsedTime;
    final rawTime = map['timestamp'];
    if (rawTime is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(rawTime);
    } else if (rawTime is String) {
      parsedTime = DateTime.parse(rawTime);
    } else {
      parsedTime = DateTime.now();
    }

    return SensorLog(
      id: map['id'] is int ? map['id'] : (map['id'] != null ? int.tryParse(map['id'].toString()) : null),
      status: map['status'] ?? 'NORMAL',
      timestamp: parsedTime,
    );
  }
}