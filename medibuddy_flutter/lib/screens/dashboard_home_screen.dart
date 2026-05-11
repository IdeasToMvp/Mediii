import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/prescription.dart';
import '../theme/medisathi_colors.dart';

String _firstLetterUpper(String name, {String fallback = '?'}) {
  final t = name.trim();
  if (t.isEmpty) return fallback;
  return String.fromCharCode(t.runes.first).toUpperCase();
}

String? _familySubtitle(Map<String, dynamic> fm) {
  final parts = <String>[];
  final raw = fm['birth_year'];
  if (raw is num) {
    final y = raw.toInt();
    final approx = DateTime.now().year - y;
    if (approx >= 0 && approx < 130) parts.add('$approx yrs');
  }
  final rel = fm['relation']?.toString().trim();
  if (rel != null && rel.isNotEmpty) parts.add(rel);
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

Widget _glowBrandTitle(TextTheme textTheme) {
  return ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => const LinearGradient(
      colors: [
        MediSathiColors.neonAccent,
        MediSathiColors.brandBlue,
        Color(0xFFC4B5FD),
      ],
    ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
    child: Text(
      'MediSathi',
      style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: Colors.white,
          ),
    ),
  );
}

/// Main signed-in dashboard (first tab) aligned with MediSathi mocks.
class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({
    super.key,
    required this.displayName,
    required this.notificationsEnabled,
    required this.upcomingMedicines,
    required this.familyMembers,
    required this.recentPrescriptions,
    this.latestReport,
    required this.onRefresh,
    required this.onViewScheduleTap,
    required this.onAddFamilyTap,
    required this.onEditFamilyMember,
    required this.onDeleteFamilyMember,
    required this.onSearchFocusTap,
    required this.onRecentPrescriptionTap,
    required this.onEditPrescription,
    required this.onDeletePrescription,
  });

  final String displayName;
  final bool notificationsEnabled;
  final List<Map<String, dynamic>> upcomingMedicines;
  final List<Map<String, dynamic>> familyMembers;
  final List<Prescription> recentPrescriptions;
  final Prescription? latestReport;

  final Future<void> Function() onRefresh;
  final VoidCallback onViewScheduleTap;
  final VoidCallback onAddFamilyTap;
  final Future<void> Function(Map<String, dynamic> member) onEditFamilyMember;
  final Future<void> Function(Map<String, dynamic> member) onDeleteFamilyMember;
  final VoidCallback onSearchFocusTap;
  final void Function(Prescription p) onRecentPrescriptionTap;
  final Future<void> Function(Prescription p) onEditPrescription;
  final Future<void> Function(Prescription p) onDeletePrescription;

  static String greetingForNow() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  int _medicinesScheduledToday() {
    final now = DateTime.now();
    return upcomingMedicines.where((e) {
      final iso = e['due_at_iso']?.toString();
      final d = DateTime.tryParse(iso ?? '');
      if (d == null) return false;
      final l = d.toLocal();
      return l.year == now.year && l.month == now.month && l.day == now.day;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final medCount = upcomingMedicines.isEmpty ? 0 : _medicinesScheduledToday();
    final timeFmt = DateFormat.jm();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    MediSathiColors.surfaceDeep,
                    Color(0xFF121A34),
                    Color(0xFFEEF2FB),
                  ],
                  stops: [0.0, 0.38, 1.0],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  MediSathiColors.neonAccent.withValues(alpha: 0.55),
                                  MediSathiColors.brandBlue.withValues(alpha: 0.35),
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(2.8),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFF161E36),
                                child: Text(
                                  displayName.isEmpty ? '?' : _firstLetterUpper(displayName, fallback: 'M'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: MediSathiColors.neonAccent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Center(child: _glowBrandTitle(Theme.of(context).textTheme))),
                          Material(
                            color: Colors.white.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(999),
                            child: Tooltip(
                              message: notificationsEnabled ? 'Notifications' : 'Notifications (coming soon)',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () {},
                                splashColor: MediSathiColors.neonAccent.withValues(alpha: 0.18),
                                child: Padding(
                                  padding: const EdgeInsets.all(11),
                                  child: Icon(
                                    Icons.notifications_none_rounded,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    size: 23,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        '${greetingForNow()}, ${displayName.isEmpty ? 'there' : displayName}',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: MediSathiColors.surfaceDeep.withValues(alpha: 0.45), blurRadius: 12),
                              ],
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        upcomingMedicines.isEmpty
                            ? 'No reminders yet — capture a prescription to get gentle nudges.'
                            : 'You have $medCount medication${medCount == 1 ? '' : 's'} on the clock today.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.78),
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 20),
                      Material(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: onSearchFocusTap,
                          splashColor: MediSathiColors.neonAccent.withValues(alpha: 0.22),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                            child: Row(
                              children: [
                                Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.88)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'Ask MediSathi… records, meds, doctors',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.78),
                                      fontSize: 15,
                                      letterSpacing: 0.05,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 22,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [MediSathiColors.neonAccent, MediSathiColors.brandBlue],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Upcoming medicines',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                          ),
                          const Spacer(),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: MediSathiColors.brandBlue,
                              textStyle: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            onPressed: onViewScheduleTap,
                            child: const Text('View schedule'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (upcomingMedicines.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    'Create schedules manually or generate them from a saved prescription.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black45),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverList.separated(
                itemCount: upcomingMedicines.length.clamp(0, 4),
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, idx) {
                  final m = upcomingMedicines[idx];
                  final name = m['medication_name']?.toString() ?? 'Medicine';
                  final dosage = m['dosage_text']?.toString() ?? '';
                  final instruct = m['meal_instruction']?.toString().trim();
                  final iso = m['due_at_iso']?.toString();
                  final when = iso != null ? timeFmt.format(DateTime.parse(iso).toLocal()) : '—';

                  final colors = [
                    MediSathiColors.brandBlue,
                    const Color(0xFF10B981),
                    const Color(0xFFF59E0B),
                  ];
                  final tint = colors[idx % colors.length];

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                          color: Colors.black.withValues(alpha: 0.06),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: tint.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.medication_rounded, color: tint, size: 28),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dosage.isEmpty ? name : '$name · $dosage',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (instruct != null && instruct.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(instruct, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: MediSathiColors.brandBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.schedule_rounded, size: 15, color: MediSathiColors.brandBlue),
                                const SizedBox(width: 6),
                                Text(
                                  when,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: MediSathiColors.brandBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 26, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: const LinearGradient(
                            colors: [MediSathiColors.brandBlue, MediSathiColors.neonAccent],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Family',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 120,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final fm in familyMembers)
                          Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: PopupMenuButton<String>(
                              tooltip: 'Family options',
                              onSelected: (v) {
                                if (v == 'edit') {
                                  onEditFamilyMember(fm);
                                } else if (v == 'delete') {
                                  onDeleteFamilyMember(fm);
                                }
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          MediSathiColors.brandBlue.withValues(alpha: 0.5),
                                          MediSathiColors.neonAccent.withValues(alpha: 0.35),
                                        ],
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2.4),
                                      child: CircleAvatar(
                                        radius: 30,
                                        backgroundColor: const Color(0xFFF5F8FF),
                                        child: Text(
                                          _firstLetterUpper((fm['display_name'] ?? '?').toString(), fallback: '?'),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            color: MediSathiColors.brandBlue,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: 92,
                                    child: Text(
                                      (fm['display_name'] ?? '').toString(),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final sub = _familySubtitle(fm);
                                      if (sub == null) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: SizedBox(
                                          width: 92,
                                          child: Text(
                                            sub,
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Column(
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: onAddFamilyTap,
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: MediSathiColors.neonAccent.withValues(alpha: 0.65),
                                      width: 2,
                                    ),
                                    color: MediSathiColors.surfaceDeep.withValues(alpha: 0.04),
                                  ),
                                  child: Icon(Icons.add_rounded, color: MediSathiColors.brandBlue, size: 28),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reports Summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  _ReportSummaryCard(
                    prescription: latestReport,
                    onTap: latestReport == null ? null : () => onRecentPrescriptionTap(latestReport!),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 28, 18, 0),
              child: Row(
                children: [
                  Text(
                    'Recent Prescriptions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: const Text('See All'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
            sliver: SliverList.separated(
              itemCount: recentPrescriptions.length.clamp(0, 4),
              separatorBuilder: (context, index) => const SizedBox(height: 2),
              itemBuilder: (context, i) {
                final p = recentPrescriptions[i];
                final sub = '${p.prescriptionDate ?? 'Visit'} • saved ${DateFormat.yMMMd().format(p.createdAt ?? DateTime.now())}';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: CircleAvatar(backgroundColor: Colors.grey.shade200, child: const Icon(Icons.description_outlined)),
                  title: Text(
                    p.doctorName?.isNotEmpty == true ? 'Dr. ${p.doctorName}' : (p.title ?? 'Prescription'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${p.generalInstructions ?? p.diagnosis ?? 'Health visit'} • $sub',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    child: Icon(Icons.more_vert_rounded, color: Colors.grey.shade500),
                    onSelected: (v) {
                      if (v == 'edit') {
                        onEditPrescription(p);
                      } else if (v == 'delete') {
                        onDeletePrescription(p);
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (!p.isReport) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  onTap: () => onRecentPrescriptionTap(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


class _ReportSummaryCard extends StatelessWidget {
  const _ReportSummaryCard({this.prescription, this.onTap});

  final Prescription? prescription;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    double headlineFromModel() {
      final m = prescription?.reportSummary;
      if (m == null) return 94;
      final hv = m['headline_value'];
      if (hv is num) return hv.toDouble();
      return _lastSeriesMapValue(m);
    }

    String metricLabel() {
      final m = prescription?.reportSummary;
      final v =
          m != null ?
            (m['metric_label'] ?? m['title'] ?? 'BLOOD GLUCOSE').toString()
          : 'BLOOD GLUCOSE';
      return v.toUpperCase();
    }

    final headlineNum = headlineFromModel();
    final badgeRaw =
        prescription?.reportSummary != null ?
          prescription!.reportSummary!['headline_status_label']
        : null;

    Widget bars() {
      List<dynamic> series =
        prescription?.reportSummary != null && prescription!.reportSummary!['series'] is List ?
          prescription!.reportSummary!['series'] as List
        : <dynamic>[];

      if (series.isEmpty) {
        series = [
          {'value': 80},
          {'value': 86},
          {'value': 90},
          {'value': 88},
          {'value': 92},
          {'value': 91},
          {'value': 94},
        ];
      }

      final nums = series.map((e) {
        if (e is Map && e['value'] != null) return (e['value'] as num).toDouble();
        return 70.0;
      }).toList();

      final max = nums.reduce((a, b) => a > b ? a : b);
      final min = nums.reduce((a, b) => a < b ? a : b);
      final span = (max - min).abs().clamp(4.0, 999.0);

      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < nums.length && i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AnimatedContainer(
                  duration: Duration.zero,
                  height: 12 + ((nums[i] - min) / span) * 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: i == nums.length - 1 ?
                          [MediSathiColors.brandBlue, MediSathiColors.brandBlue]
                      : [
                          MediSathiColors.brandBlue.withValues(alpha: 0.25),
                          MediSathiColors.brandBlue.withValues(alpha: 0.45),
                        ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                blurRadius: 28,
                offset: const Offset(0, 14),
                color: Colors.black.withValues(alpha: 0.06),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    metricLabel(),
                    style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: Colors.grey.shade600),
                  ),
                ),
                if ((badgeRaw ?? 'STABLE').toString().isNotEmpty)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      child: Text(
                        (badgeRaw ?? 'STABLE').toString().toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${headlineNum.round()} '
              '${prescription?.reportSummary != null ? (prescription!.reportSummary!['unit'] ?? 'mg/dL').toString() : 'mg/dL'}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
            ),
            const SizedBox(height: 20),
            SizedBox(height: 72, child: bars()),
            if (prescription == null) ...[
              const SizedBox(height: 14),
              Text(
                'Upload a lab snapshot — AI classifies prescriptions vs reports and stores chart-friendly metrics.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
        ),
      ),
    );
  }
}

double _lastSeriesMapValue(Map<String, dynamic> summary) {
  final raw = summary['series'];
  if (raw is List && raw.isNotEmpty) {
    final last = raw.last;
    if (last is Map && last['value'] is num) return (last['value'] as num).toDouble();
  }
  return 94;
}
