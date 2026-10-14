import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Helper terpusat untuk menampilkan SnackBar dengan ikon Material (bukan emoji).
/// Gunakan class ini di seluruh aplikasi untuk konsistensi tampilan notifikasi.
class AppSnackBar {
  AppSnackBar._();

  // ✅ Sukses (hijau)
  static void success(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    _show(context, message, icon: Icons.check_circle_rounded, color: AppTheme.success, duration: duration);
  }

  // ❌ Error / Bahaya (merah)
  static void error(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    _show(context, message, icon: Icons.cancel_rounded, color: AppTheme.danger, duration: duration);
  }

  // ⚠️ Peringatan (kuning/oranye)
  static void warning(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    _show(context, message, icon: Icons.warning_rounded, color: Colors.orange.shade700, duration: duration);
  }

  // ℹ️ Info (biru/primary)
  static void info(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    _show(context, message, icon: Icons.info_rounded, color: AppTheme.primary, duration: duration);
  }

  // 🗑️ Hapus (merah dengan ikon sampah)
  static void deleted(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    _show(context, message, icon: Icons.delete_sweep_rounded, color: AppTheme.danger, duration: duration);
  }

  // 📄 Export / Download
  static void exported(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    _show(context, message, icon: Icons.download_done_rounded, color: AppTheme.primary, duration: duration);
  }

  static void _show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color color,
    required Duration duration,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
