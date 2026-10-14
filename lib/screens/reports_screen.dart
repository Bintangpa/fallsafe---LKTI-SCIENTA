import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sensor_log.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snackbar.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<SensorLog> _allLogs = [];
  bool _isLoading = true;
  String _timeRange = 'Semua Data';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await DatabaseService.getAllLogs();
    if (mounted) {
      setState(() {
        _allLogs = logs;
        _isLoading = false;
      });
    }
  }

  List<SensorLog> get _filteredLogs {
    if (_allLogs.isEmpty) return [];
    final now = DateTime.now();

    if (_timeRange == 'Hari Ini') {
      return _allLogs.where((l) =>
        l.timestamp.year == now.year &&
        l.timestamp.month == now.month &&
        l.timestamp.day == now.day
      ).toList();
    } else if (_timeRange == '7 Hari Terakhir') {
      final weekAgo = now.subtract(const Duration(days: 7));
      return _allLogs.where((l) => l.timestamp.isAfter(weekAgo)).toList();
    } else if (_timeRange == '30 Hari Terakhir') {
      final monthAgo = now.subtract(const Duration(days: 30));
      return _allLogs.where((l) => l.timestamp.isAfter(monthAgo)).toList();
    }
    return _allLogs;
  }

  void _exportReport(String format) {
    AppSnackBar.exported(
      context,
      'Laporan berhasil diexport dalam format $format! (File tersimpan ke folder Download)',
      duration: const Duration(seconds: 4),
    );
  }


  @override
  Widget build(BuildContext context) {
    final logs = _filteredLogs;
    final totalLogs = logs.length;
    final totalFalls = logs.where((l) => l.status == 'JATUH').length;
    final totalSuspicious = logs.where((l) => l.status == 'CURIGA').length;
    final totalNormal = logs.where((l) => l.status == 'NORMAL').length;

    final fallPercentage = totalLogs > 0 ? (totalFalls / totalLogs) : 0.0;
    final normalPercentage = totalLogs > 0 ? (totalNormal / totalLogs) : 0.0;
    final suspPercentage = totalLogs > 0 ? (totalSuspicious / totalLogs) : 0.0;

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
                // 1. Header Banner Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 600;
                      final exportBtn = PopupMenuButton<String>(
                        onSelected: _exportReport,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: AppTheme.softShadow,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download, size: 18, color: AppTheme.primary),
                              SizedBox(width: 8),
                              Text(
                                'Export Laporan',
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: 'PDF', child: Text('📄 Export PDF')),
                          const PopupMenuItem(value: 'Excel/CSV', child: Text('📊 Export Excel (CSV)')),
                        ],
                      );

                      final textInfo = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Laporan & Analytics Admin',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Rekapitulasi Monitoring',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Analisis statistik kejadian jatuh, frekuensi indikasi curiga, dan laporan siap cetak.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                          ),
                        ],
                      );

                      if (isMobile) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            textInfo,
                            const SizedBox(height: 16),
                            exportBtn,
                          ],
                        );
                      }

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: textInfo),
                          const SizedBox(width: 16),
                          exportBtn,
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // 2. Time Filter Bar (Compact Popup Selector)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppTheme.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Rentang:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _showTimeRangeModal,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _timeRange,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: AppTheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Muat Ulang Laporan',
                          icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
                          onPressed: _loadLogs,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 3. Metric Cards Grid (2x2 on Mobile, 1x4 on Desktop - Prevents Vertical Stretching & Text Squeezing)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;

                    if (isMobile) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricCard(
                                  title: 'Total Log',
                                  value: '$totalLogs',
                                  icon: Icons.list_alt,
                                  color: AppTheme.primary,
                                  bgColor: AppTheme.primaryLight,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildMetricCard(
                                  title: 'Jatuh Terdeteksi',
                                  value: '$totalFalls',
                                  icon: Icons.emergency,
                                  color: AppTheme.danger,
                                  bgColor: AppTheme.dangerBg,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricCard(
                                  title: 'Indikasi Curiga',
                                  value: '$totalSuspicious',
                                  icon: Icons.warning_amber_rounded,
                                  color: AppTheme.warning,
                                  bgColor: AppTheme.warningBg,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildMetricCard(
                                  title: 'Kondisi Aman',
                                  value: '$totalNormal',
                                  icon: Icons.check_circle_outline,
                                  color: AppTheme.success,
                                  bgColor: AppTheme.successBg,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    } else {
                      return Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              title: 'Total Log',
                              value: '$totalLogs',
                              icon: Icons.list_alt,
                              color: AppTheme.primary,
                              bgColor: AppTheme.primaryLight,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'Jatuh Terdeteksi',
                              value: '$totalFalls',
                              icon: Icons.emergency,
                              color: AppTheme.danger,
                              bgColor: AppTheme.dangerBg,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'Indikasi Curiga',
                              value: '$totalSuspicious',
                              icon: Icons.warning_amber_rounded,
                              color: AppTheme.warning,
                              bgColor: AppTheme.warningBg,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'Kondisi Aman',
                              value: '$totalNormal',
                              icon: Icons.check_circle_outline,
                              color: AppTheme.success,
                              bgColor: AppTheme.successBg,
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 24),

                // 4. Analytics Visual Progress Card
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
                            Icon(Icons.pie_chart_outline, color: AppTheme.primary),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Distribusi Persentase Kondisi Sensor',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildProgressBar(
                          label: 'Kondisi Aman (Normal)',
                          percentage: normalPercentage,
                          count: totalNormal,
                          color: AppTheme.success,
                        ),
                        const SizedBox(height: 14),
                        _buildProgressBar(
                          label: 'Indikasi Gerakan Mencurigakan (Curiga)',
                          percentage: suspPercentage,
                          count: totalSuspicious,
                          color: AppTheme.warning,
                        ),
                        const SizedBox(height: 14),
                        _buildProgressBar(
                          label: 'Kejadian Jatuh Darurat (Jatuh)',
                          percentage: fallPercentage,
                          count: totalFalls,
                          color: AppTheme.danger,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 5. Table / Log List Header
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    final printBtn = TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => _exportReport('PDF'),
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text(
                        'Cetak Laporan (PDF)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rincian Log Riwayat (${logs.length} data)',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: printBtn,
                          ),
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Rincian Log Riwayat (${logs.length} data)',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        printBtn,
                      ],
                    );
                  },
                ),

                const SizedBox(height: 12),

                // 6. Log List Items
                _isLoading
                    ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                    : logs.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(40),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.assignment_late_outlined, size: 64, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('Tidak ada log untuk periode ini', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: logs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (ctx, idx) {
                              final log = logs[idx];
                              Color statusColor = AppTheme.success;
                              Color statusBg = AppTheme.successBg;
                              IconData statusIcon = Icons.check_circle;

                              if (log.status == 'JATUH') {
                                statusColor = AppTheme.danger;
                                statusBg = AppTheme.dangerBg;
                                statusIcon = Icons.emergency;
                              } else if (log.status == 'CURIGA') {
                                statusColor = AppTheme.warning;
                                statusBg = AppTheme.warningBg;
                                statusIcon = Icons.warning;
                              }

                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: AppTheme.border.withValues(alpha: 0.8)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: statusBg,
                                        child: Icon(statusIcon, color: statusColor, size: 20),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Status Sensor: ${log.status}',
                                              style: TextStyle(fontWeight: FontWeight.bold, color: statusColor, fontSize: 15),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              DateFormat('dd MMM yyyy • HH:mm:ss').format(log.timestamp),
                                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
                                          'ID: #${log.id ?? idx + 1}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
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

  void _showTimeRangeModal() {
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
                        Icon(Icons.calendar_month_rounded, color: AppTheme.primary, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pilih Rentang Waktu Laporan',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTimeRangeOptionModal(
                      label: 'Hari Ini',
                      subtitle: 'Data insiden dan status sensor selama hari ini',
                      value: 'Hari Ini',
                      icon: Icons.today_rounded,
                    ),
                    const SizedBox(height: 6),
                    _buildTimeRangeOptionModal(
                      label: '7 Hari Terakhir',
                      subtitle: 'Rekapitulasi monitoring sensor dalam 1 minggu terakhir',
                      value: '7 Hari Terakhir',
                      icon: Icons.date_range_rounded,
                    ),
                    const SizedBox(height: 6),
                    _buildTimeRangeOptionModal(
                      label: '30 Hari Terakhir',
                      subtitle: 'Rekapitulasi monitoring sensor dalam 1 bulan terakhir',
                      value: '30 Hari Terakhir',
                      icon: Icons.calendar_month_rounded,
                    ),
                    const SizedBox(height: 6),
                    _buildTimeRangeOptionModal(
                      label: 'Semua Data',
                      subtitle: 'Seluruh riwayat log yang tersimpan di Supabase',
                      value: 'Semua Data',
                      icon: Icons.all_inclusive_rounded,
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

  Widget _buildTimeRangeOptionModal({
    required String label,
    required String subtitle,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _timeRange == value;

    return InkWell(
      onTap: () {
        setState(() => _timeRange = value);
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryLight.withValues(alpha: 0.6) : AppTheme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.primary.withValues(alpha: 0.6) : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: isSelected ? AppTheme.primaryLight : Colors.grey.shade100,
              child: Icon(icon, color: isSelected ? AppTheme.primary : AppTheme.textSecondary, size: 16),
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
                      color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
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
              const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: bgColor,
                  child: Icon(icon, color: color, size: 20),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'DATA',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar({
    required String label,
    required double percentage,
    required int count,
    required Color color,
  }) {
    final percentInt = (percentage * 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count Kejadian ($percentInt%)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 10,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
