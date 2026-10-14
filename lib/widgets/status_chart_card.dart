import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sensor_log.dart';
import '../theme/app_theme.dart';

class StatusChartCard extends StatefulWidget {
  final List<SensorLog> logs;
  final VoidCallback? onRefresh;

  const StatusChartCard({
    super.key,
    required this.logs,
    this.onRefresh,
  });

  @override
  State<StatusChartCard> createState() => _StatusChartCardState();
}

class _StatusChartCardState extends State<StatusChartCard> {
  String _selectedRange = 'Hari Ini'; // 'Hari Ini', '7 Hari', '30 Hari', 'Semua'
  int? _selectedBucketIndex;

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _getFilteredLogsByRange();
    final buckets = _buildBuckets(filteredLogs);

    final totalNormal = filteredLogs.where((l) => l.status.toUpperCase() == 'NORMAL').length;
    final totalSuspicious = filteredLogs.where((l) => l.status.toUpperCase() == 'CURIGA').length;
    final totalFalls = filteredLogs.where((l) => l.status.toUpperCase() == 'JATUH').length;
    final totalAll = filteredLogs.length;

    int maxBucketCount = 0;
    for (final b in buckets) {
      if (b.total > maxBucketCount) maxBucketCount = b.total;
    }
    if (maxBucketCount < 4) maxBucketCount = 4; // Baseline minimal agar proporsional

    final selectedBucket = (_selectedBucketIndex != null &&
            _selectedBucketIndex! >= 0 &&
            _selectedBucketIndex! < buckets.length)
        ? buckets[_selectedBucketIndex!]
        : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header Card
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primaryLight,
                  child: const Icon(Icons.insights_rounded, color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Grafik Riwayat Status Sensor',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Distribusi kondisi deteksi per rentang waktu',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (widget.onRefresh != null)
                  IconButton(
                    tooltip: 'Segarkan Data Grafik',
                    icon: const Icon(Icons.refresh_rounded, size: 20, color: AppTheme.primary),
                    onPressed: widget.onRefresh,
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // 2. Selector Kurun Waktu (Segmented Pills)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildRangePill('Hari Ini', Icons.today_rounded),
                  const SizedBox(width: 8),
                  _buildRangePill('7 Hari', Icons.date_range_rounded),
                  const SizedBox(width: 8),
                  _buildRangePill('30 Hari', Icons.calendar_month_rounded),
                  const SizedBox(width: 8),
                  _buildRangePill('Semua', Icons.all_inclusive_rounded),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3. Mini Summary Badges (Normal, Curiga, Jatuh, Total)
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 450;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSummaryBadge(
                      label: 'Normal',
                      count: totalNormal,
                      color: AppTheme.success,
                      bgColor: AppTheme.successBg,
                      icon: Icons.check_circle_outline,
                      isNarrow: isNarrow,
                    ),
                    _buildSummaryBadge(
                      label: 'Curiga',
                      count: totalSuspicious,
                      color: AppTheme.warning,
                      bgColor: AppTheme.warningBg,
                      icon: Icons.warning_amber_rounded,
                      isNarrow: isNarrow,
                    ),
                    _buildSummaryBadge(
                      label: 'Jatuh',
                      count: totalFalls,
                      color: AppTheme.danger,
                      bgColor: AppTheme.dangerBg,
                      icon: Icons.emergency,
                      isNarrow: isNarrow,
                    ),
                    _buildSummaryBadge(
                      label: 'Total',
                      count: totalAll,
                      color: AppTheme.primary,
                      bgColor: AppTheme.primaryLight,
                      icon: Icons.bar_chart_rounded,
                      isNarrow: isNarrow,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 18),

            // 4. Bar Chart Area
            Container(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  if (totalAll == 0)
                    SizedBox(
                      height: 160,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.query_stats_rounded, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            const Text(
                              'Belum ada data riwayat sensor pada kurun waktu ini.',
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 180,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: buckets.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final b = entry.value;
                          final isSelected = _selectedBucketIndex == idx;

                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedBucketIndex = (_selectedBucketIndex == idx) ? null : idx;
                                });
                              },
                              child: Container(
                                color: Colors.transparent, // Hit area
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // Angka total di atas bar
                                    FittedBox(
                                      child: Text(
                                        b.total > 0 ? '${b.total}' : '-',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: b.total > 0 ? FontWeight.bold : FontWeight.normal,
                                          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),

                                    // Bar Column (Stacked Colors)
                                    Expanded(
                                      child: Container(
                                        width: isSelected ? 22 : 18,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(6),
                                          border: isSelected
                                              ? Border.all(color: AppTheme.primary, width: 2)
                                              : null,
                                        ),
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: _buildStackedBar(b, maxBucketCount),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),

                                    // Label sumbu X
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        b.label,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                                        ),
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppTheme.border),
                  const SizedBox(height: 10),

                  // 5. Chart Legend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendItem('Normal', AppTheme.success),
                      const SizedBox(width: 14),
                      _buildLegendItem('Curiga', AppTheme.warning),
                      const SizedBox(width: 14),
                      _buildLegendItem('Jatuh', AppTheme.danger),
                    ],
                  ),
                ],
              ),
            ),

            // 6. Tooltip Info Box saat bar disentuh/diklik
            if (selectedBucket != null) ...[
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_rounded, color: AppTheme.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedBucket.fullTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Total: ${selectedBucket.total} log  •  Normal: ${selectedBucket.normalCount}  •  Curiga: ${selectedBucket.suspiciousCount}  •  Jatuh: ${selectedBucket.fallCount}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
                      onPressed: () => setState(() => _selectedBucketIndex = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Filter logs berdasarkan kurun waktu yang dipilih
  List<SensorLog> _getFilteredLogsByRange() {
    if (widget.logs.isEmpty) return [];
    final now = DateTime.now();

    switch (_selectedRange) {
      case 'Hari Ini':
        return widget.logs.where((l) {
          return l.timestamp.year == now.year &&
              l.timestamp.month == now.month &&
              l.timestamp.day == now.day;
        }).toList();

      case '7 Hari':
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        return widget.logs.where((l) => l.timestamp.isAfter(sevenDaysAgo)).toList();

      case '30 Hari':
        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        return widget.logs.where((l) => l.timestamp.isAfter(thirtyDaysAgo)).toList();

      case 'Semua':
      default:
        return widget.logs;
    }
  }

  // Buat time buckets untuk diagram batang
  List<_ChartTimeBucket> _buildBuckets(List<SensorLog> logs) {
    final now = DateTime.now();

    if (_selectedRange == 'Hari Ini') {
      // 6 interval 4 jam per hari: 00-04, 04-08, 08-12, 12-16, 16-20, 20-24
      final intervals = [
        {'label': '00-04', 'start': 0, 'end': 4},
        {'label': '04-08', 'start': 4, 'end': 8},
        {'label': '08-12', 'start': 8, 'end': 12},
        {'label': '12-16', 'start': 12, 'end': 16},
        {'label': '16-20', 'start': 16, 'end': 20},
        {'label': '20-24', 'start': 20, 'end': 24},
      ];

      return intervals.map((it) {
        final startHour = it['start'] as int;
        final endHour = it['end'] as int;
        final label = it['label'] as String;

        final bucketLogs = logs.where((l) {
          final h = l.timestamp.hour;
          return h >= startHour && h < endHour;
        }).toList();

        return _ChartTimeBucket(
          label: label,
          fullTitle: 'Jam $label (Hari Ini)',
          normalCount: bucketLogs.where((l) => l.status.toUpperCase() == 'NORMAL').length,
          suspiciousCount: bucketLogs.where((l) => l.status.toUpperCase() == 'CURIGA').length,
          fallCount: bucketLogs.where((l) => l.status.toUpperCase() == 'JATUH').length,
        );
      }).toList();
    } else if (_selectedRange == '7 Hari') {
      // 7 hari terakhir (dari 6 hari lalu s/d hari ini)
      final List<_ChartTimeBucket> result = [];
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        final dayFormat = DateFormat('E', 'id_ID').format(d);
        final fullFormat = DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(d);

        final bucketLogs = logs.where((l) {
          return l.timestamp.year == d.year &&
              l.timestamp.month == d.month &&
              l.timestamp.day == d.day;
        }).toList();

        result.add(_ChartTimeBucket(
          label: dayFormat,
          fullTitle: fullFormat,
          normalCount: bucketLogs.where((l) => l.status.toUpperCase() == 'NORMAL').length,
          suspiciousCount: bucketLogs.where((l) => l.status.toUpperCase() == 'CURIGA').length,
          fallCount: bucketLogs.where((l) => l.status.toUpperCase() == 'JATUH').length,
        ));
      }
      return result;
    } else if (_selectedRange == '30 Hari') {
      // 5 bucket mingguan/periode per 6 hari
      final List<_ChartTimeBucket> result = [];
      const periodDays = 6;
      for (int i = 4; i >= 0; i--) {
        final start = now.subtract(Duration(days: (i + 1) * periodDays));
        final end = now.subtract(Duration(days: i * periodDays));
        final label = DateFormat('dd/MM').format(end);

        final bucketLogs = logs.where((l) {
          return l.timestamp.isAfter(start) && l.timestamp.isBefore(end.add(const Duration(days: 1)));
        }).toList();

        result.add(_ChartTimeBucket(
          label: label,
          fullTitle: 'Periode s/d ${DateFormat('dd MMM yyyy', 'id_ID').format(end)}',
          normalCount: bucketLogs.where((l) => l.status.toUpperCase() == 'NORMAL').length,
          suspiciousCount: bucketLogs.where((l) => l.status.toUpperCase() == 'CURIGA').length,
          fallCount: bucketLogs.where((l) => l.status.toUpperCase() == 'JATUH').length,
        ));
      }
      return result;
    } else {
      // 'Semua' - kelompokkan per bulan atau 6 tanggal log terkini
      final Map<String, List<SensorLog>> grouped = {};
      for (final l in logs) {
        final key = DateFormat('dd MMM').format(l.timestamp);
        grouped.putIfAbsent(key, () => []).add(l);
      }

      if (grouped.isEmpty) {
        return [
          _ChartTimeBucket(
            label: 'Data',
            fullTitle: 'Semua Riwayat Sensor',
            normalCount: 0,
            suspiciousCount: 0,
            fallCount: 0,
          )
        ];
      }

      // Ambil maksimal 7 hari terbaru
      final keys = grouped.keys.toList();
      final takeKeys = keys.length > 7 ? keys.sublist(keys.length - 7) : keys;

      return takeKeys.map((k) {
        final bLogs = grouped[k] ?? [];
        return _ChartTimeBucket(
          label: k,
          fullTitle: 'Tanggal $k',
          normalCount: bLogs.where((l) => l.status.toUpperCase() == 'NORMAL').length,
          suspiciousCount: bLogs.where((l) => l.status.toUpperCase() == 'CURIGA').length,
          fallCount: bLogs.where((l) => l.status.toUpperCase() == 'JATUH').length,
        );
      }).toList();
    }
  }

  // Bangun Stacked Bar yang proporsional
  Widget _buildStackedBar(_ChartTimeBucket b, int maxCount) {
    if (b.total == 0) {
      return const SizedBox();
    }

    // Persentase tinggi relatif terhadap nilai maksimum
    final heightFactor = (b.total / maxCount).clamp(0.08, 1.0);

    return FractionallySizedBox(
      heightFactor: heightFactor,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Column(
          children: [
            // Jatuh (Merah - atas)
            if (b.fallCount > 0)
              Expanded(
                flex: b.fallCount,
                child: Container(color: AppTheme.danger),
              ),
            // Curiga (Kuning/Oranye - tengah)
            if (b.suspiciousCount > 0)
              Expanded(
                flex: b.suspiciousCount,
                child: Container(color: AppTheme.warning),
              ),
            // Normal (Hijau - bawah)
            if (b.normalCount > 0)
              Expanded(
                flex: b.normalCount,
                child: Container(color: AppTheme.success),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangePill(String title, IconData icon) {
    final isSelected = _selectedRange == title;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedRange = title;
          _selectedBucketIndex = null;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBadge({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
    required IconData icon,
    bool isNarrow = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
          Text(
            '$count',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          title,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _ChartTimeBucket {
  final String label;
  final String fullTitle;
  final int normalCount;
  final int suspiciousCount;
  final int fallCount;

  _ChartTimeBucket({
    required this.label,
    required this.fullTitle,
    required this.normalCount,
    required this.suspiciousCount,
    required this.fallCount,
  });

  int get total => normalCount + suspiciousCount + fallCount;
}
