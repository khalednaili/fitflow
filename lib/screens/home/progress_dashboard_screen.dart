import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/personal_record.dart';
import '../../services/progress_service.dart';

const _kTeal = Color(0xFF0F766E);
const _kOrange = Color(0xFFF97316);

class ProgressDashboardScreen extends StatefulWidget {
  const ProgressDashboardScreen({super.key, this.gymId = ''});

  final String gymId;

  @override
  State<ProgressDashboardScreen> createState() =>
      _ProgressDashboardScreenState();
}

class _ProgressDashboardScreenState extends State<ProgressDashboardScreen> {
  final _service = ProgressService();
  late final Stream<ProgressData> _stream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _stream = uid.isNotEmpty ? _service.streamProgress(uid) : Stream.empty();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: _kTeal,
            title: Text(
              context.l10n.tr('My Progress'),
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            iconTheme: IconThemeData(color: Colors.white),
          ),
          StreamBuilder<ProgressData>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError || snap.data == null) {
                return SliverFillRemaining(
                  child: Center(
                    child: Text(context.l10n.tr('Could not load progress.')),
                  ),
                );
              }
              final data = snap.data!;
              return SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 20, 16, 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Top stat cards ───────────────────────────────
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  icon: Icons.local_fire_department,
                                  iconColor: _kOrange,
                                  value: '${data.currentStreakWeeks}',
                                  label: context.l10n.tr('Week streak'),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  icon: Icons.fitness_center,
                                  iconColor: _kTeal,
                                  value: '${data.totalCheckIns}',
                                  label: context.l10n.tr('Total check-ins'),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 24),

                          // ── Weekly attendance bar chart ──────────────────
                          _SectionTitle(
                              label: context.l10n.tr('Classes per week (last 8 weeks)')),
                          SizedBox(height: 12),
                          _WeeklyBarChart(weeks: data.weeklyAttendance),
                          SizedBox(height: 28),

                          // ── PR trends ────────────────────────────────────
                          _SectionTitle(label: context.l10n.tr('Personal Records')),
                          SizedBox(height: 12),
                          if (data.prsByExercise.isEmpty)
                            _EmptyPRs()
                          else
                            ...data.prsByExercise.entries.map(
                              (entry) => _PrCard(
                                exercise: entry.key,
                                prs: entry.value,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Stat card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section title ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

// ── Weekly bar chart ─────────────────────────────────────────────────────────

class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({required this.weeks});
  final List<WeeklyCount> weeks;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxY = weeks.map((w) => w.count).fold<int>(0, (a, b) => a > b ? a : b);
    final yMax = (maxY < 5 ? 5 : maxY + 1).toDouble();

    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: yMax,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) =>
                      isDark ? Color(0xFF2D2D2D) : Colors.grey.shade800,
                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                    '${rod.toY.toInt()} ${context.l10n.tr('classes')}',
                    TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 24,
                    getTitlesWidget: (v, _) => Text(
                      v.toInt() == 0 ? '' : '${v.toInt()}',
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= weeks.length) return SizedBox.shrink();
                      return Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          weeks[i].label,
                          style: TextStyle(
                              fontSize: 9, color: cs.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: weeks.asMap().entries.map((e) {
                final isThisWeek = e.key == weeks.length - 1;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.count.toDouble(),
                      color: isThisWeek ? _kOrange : _kTeal,
                      width: 14,
                      borderRadius: BorderRadius.circular(4),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: yMax,
                        color: cs.outlineVariant.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ── PR card with line chart ──────────────────────────────────────────────────

class _PrCard extends StatelessWidget {
  const _PrCard({required this.exercise, required this.prs});

  final String exercise;
  final List<PersonalRecord> prs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final latest = prs.last;

    // Build chart spots from parseable values
    final spots = <FlSpot>[];
    for (var i = 0; i < prs.length; i++) {
      final v = parsePrValue(prs[i].value);
      if (v != null) spots.add(FlSpot(i.toDouble(), v));
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    exercise,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.onSurface),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      latest.value,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: _kTeal,
                      ),
                    ),
                    Text(
                      DateFormat('dd MMM yyyy').format(latest.achievedAt),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),

            // Line chart (only if ≥2 numeric points)
            if (spots.length >= 2) ...[
              SizedBox(height: 12),
              SizedBox(
                height: 90,
                child: LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: _kTeal,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (_, __, ___, ____) =>
                              FlDotCirclePainter(
                            radius: 3,
                            color: _kTeal,
                            strokeWidth: 1.5,
                            strokeColor: Colors.white,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: _kTeal.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => Color(0xFF111827),
                        getTooltipItems: (spots) => spots
                            .map((s) => LineTooltipItem(
                                  prs[s.x.toInt()].value,
                                  TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // All entries list (collapsed to last 3)
            if (prs.length > 1) ...[
              SizedBox(height: 8),
              ...prs.reversed.take(3).map((pr) => Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_forward_ios,
                            size: 10, color: cs.onSurfaceVariant),
                        SizedBox(width: 6),
                        Text(
                          pr.value,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                        ),
                        Spacer(),
                        Text(
                          DateFormat('dd MMM').format(pr.achievedAt),
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyPRs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 40, color: Theme.of(context).colorScheme.outlineVariant),
            SizedBox(height: 8),
            Text(
              context.l10n.tr('No personal records yet'),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
