import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_snackbar.dart';
import 'package:intl/intl.dart';
import '../models/sensor_log.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_chart_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SensorLog> _logs = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedStatusFilter = 'Semua';
  StreamSubscription? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _listenLogsRealtime();
  }

  void _listenLogsRealtime() {
    try {
      _streamSubscription = DatabaseService.streamLogs().listen((logs) {
        if (mounted) {
          setState(() {
            _logs = logs;
            _isLoading = false;
          });
        }
      }, onError: (e) {
        print('Realtime logs stream error: $e');
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await DatabaseService.getAllLogs();
    if (mounted) {
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAllLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
            SizedBox(width: 10),
            Expanded(child: Text('Hapus Semua Riwayat?')),
          ],
        ),
        content: const Text(
          'Apakah Anda yakin ingin menghapus seluruh log riwayat sensor?\nData yang dihapus dari database Supabase tidak dapat dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Sekarang', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.clearAll();
      if (mounted) {
        AppSnackBar.deleted(context, 'Seluruh riwayat sensor berhasil dihapus!');
        _loadLogs();
      }
    }
  }

  List<SensorLog> get _filteredLogs {
    return _logs.where((log) {
      final matchesSearch = log.status.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          DateFormat('dd MMM yyyy HH:mm:ss').format(log.timestamp).toLowerCase().contains(_searchQuery.toLowerCase());

      if (_selectedStatusFilter == 'Semua') return matchesSearch;
      return matchesSearch && log.status.toUpperCase() == _selectedStatusFilter.toUpperCase();
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
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

  Color _statusBg(String status) {
    switch (status) {
      case 'NORMAL':
        return AppTheme.successBg;
      case 'CURIGA':
        return AppTheme.warningBg;
      case 'JATUH':
        return AppTheme.dangerBg;
      default:
        return AppTheme.primaryLight;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLogs;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: Colors.white,
        onRefresh: _loadLogs,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Control Header Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 750;

                        final deleteButton = OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _logs.isEmpty ? AppTheme.textMuted : AppTheme.danger,
                            backgroundColor: _logs.isEmpty
                                ? Colors.grey.shade100
                                : AppTheme.dangerBg.withValues(alpha: 0.6),
                            side: BorderSide(
                              color: _logs.isEmpty ? Colors.grey.shade300 : AppTheme.danger.withValues(alpha: 0.5),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrow ? 10 : 14,
                              vertical: isNarrow ? 8 : 10,
                            ),
                          ),
                          icon: Icon(
                            Icons.delete_sweep_outlined,
                            size: 18,
                            color: _logs.isEmpty ? AppTheme.textMuted : AppTheme.danger,
                          ),
                          label: Text(
                            'Hapus Riwayat',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isNarrow ? 12 : 13,
                              color: _logs.isEmpty ? AppTheme.textMuted : AppTheme.danger,
                            ),
                          ),
                          onPressed: _logs.isEmpty ? null : _clearAllLogs,
                        );

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: isNarrow ? 22 : 24,
                              backgroundColor: AppTheme.primaryLight,
                              child: Icon(
                                Icons.history_rounded,
                                color: AppTheme.primary,
                                size: isNarrow ? 24 : 26,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Riwayat Deteksi',
                                          style: TextStyle(
                                            fontSize: isNarrow ? 16 : 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryLight,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          '${_logs.length} Log',
                                          style: const TextStyle(
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  const Text(
                                    'Sinkronisasi otomatis Wemos & Supabase',
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            deleteButton,
                          ],
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 18),

                // 2. Grafik Tren Status Sensor (Berdasarkan Kurun Waktu & Database Realtime)
                StatusChartCard(
                  logs: _logs,
                  onRefresh: _loadLogs,
                ),

                const SizedBox(height: 18),

                // Search & Filter Bar
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppTheme.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: 'Cari log berdasarkan status atau tanggal...',
                            prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => setState(() => _searchQuery = ''),
                                  )
                                : null,
                            filled: true,
                            fillColor: AppTheme.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.tune_rounded, size: 18, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            const Text('Filter Status:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSecondary)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: _showStatusFilterModal,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _selectedStatusFilter == 'Semua' ? AppTheme.background : _statusBg(_selectedStatusFilter),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _selectedStatusFilter == 'Semua'
                                          ? AppTheme.border
                                          : _statusColor(_selectedStatusFilter).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_selectedStatusFilter != 'Semua') ...[
                                              Icon(
                                                _statusIcon(_selectedStatusFilter),
                                                size: 14,
                                                color: _statusColor(_selectedStatusFilter),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Flexible(
                                              child: Text(
                                                _selectedStatusFilter == 'Semua' ? 'Semua Status' : _selectedStatusFilter,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: _selectedStatusFilter == 'Semua'
                                                      ? AppTheme.textPrimary
                                                      : _statusColor(_selectedStatusFilter),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: _selectedStatusFilter == 'Semua'
                                            ? AppTheme.textSecondary
                                            : _statusColor(_selectedStatusFilter),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_selectedStatusFilter != 'Semua') ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Reset Filter',
                                icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                                onPressed: () => setState(() => _selectedStatusFilter = 'Semua'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Logs List Body
                _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : filtered.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(40),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.history_toggle_off, size: 56, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                const Text(
                                  'Belum Ada Data Riwayat',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Riwayat akan terisi otomatis ketika ada perubahan status dari sensor Wemos.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final log = filtered[index];
                              final color = _statusColor(log.status);
                              final bg = _statusBg(log.status);
                              final icon = _statusIcon(log.status);

                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: AppTheme.border.withValues(alpha: 0.8)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: bg,
                                        child: Icon(icon, color: color, size: 20),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  log.status,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color: color,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: bg,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    log.status == 'JATUH' ? 'EMERGENCY' : 'SENSOR LOG',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: color,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              DateFormat('dd MMMM yyyy • HH:mm:ss').format(log.timestamp),
                                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.background,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: AppTheme.border),
                                        ),
                                        child: Text(
                                          '#${log.id ?? index + 1}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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

  void _showStatusFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                maxWidth: 600,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Pilih Filter Status Sensor',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildFilterOptionModal(
                      label: 'Semua Status',
                      subtitle: 'Tampilkan seluruh riwayat tanpa filter status',
                      value: 'Semua',
                      icon: Icons.all_inclusive_rounded,
                      iconColor: AppTheme.primary,
                      bgColor: AppTheme.primaryLight,
                    ),
                    const SizedBox(height: 6),
                    _buildFilterOptionModal(
                      label: 'NORMAL',
                      subtitle: 'Kondisi sensor terdeteksi aman & stabil',
                      value: 'NORMAL',
                      icon: Icons.check_circle_rounded,
                      iconColor: AppTheme.success,
                      bgColor: AppTheme.successBg,
                    ),
                    const SizedBox(height: 6),
                    _buildFilterOptionModal(
                      label: 'CURIGA',
                      subtitle: 'Indikasi gerakan tidak wajar terdeteksi',
                      value: 'CURIGA',
                      icon: Icons.warning_rounded,
                      iconColor: AppTheme.warning,
                      bgColor: AppTheme.warningBg,
                    ),
                    const SizedBox(height: 6),
                    _buildFilterOptionModal(
                      label: 'JATUH',
                      subtitle: 'Insiden darurat jatuh terdeteksi Wemos',
                      value: 'JATUH',
                      icon: Icons.emergency_rounded,
                      iconColor: AppTheme.danger,
                      bgColor: AppTheme.dangerBg,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterOptionModal({
    required String label,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    final isSelected = _selectedStatusFilter == value;

    return InkWell(
      onTap: () {
        setState(() => _selectedStatusFilter = value);
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? bgColor.withValues(alpha: 0.5) : AppTheme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? iconColor.withValues(alpha: 0.6) : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: bgColor,
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isSelected ? iconColor : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: iconColor, size: 18),
          ],
        ),
      ),
    );
  }
}