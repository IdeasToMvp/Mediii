import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/medibuddy_api.dart';
import '../theme/medisathi_colors.dart';

List<String> _timePointsFromRow(dynamic tp) {
  if (tp is List) {
    return tp.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
  }
  if (tp is String) {
    try {
      final j = jsonDecode(tp);
      if (j is List) return j.map((e) => e.toString()).toList();
    } catch (_) {}
  }
  return ['09:00'];
}

String? _isoEndFromStartAndDays(String startYmd, int days) {
  if (days <= 0) return null;
  final p = startYmd.trim().split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  final start = DateTime.utc(y, m, d);
  final end = start.add(Duration(days: days - 1));
  return '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
}

List<String> _parseTimesInput(String raw) {
  return raw
      .split(RegExp(r'[\s,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

bool _dueLocalIsToday(DateTime d) {
  final l = d.toLocal();
  final n = DateTime.now();
  return l.year == n.year && l.month == n.month && l.day == n.day;
}

List<Map<String, dynamic>> _occurrencesDueToday(List<Map<String, dynamic>> occurrences) {
  final list = occurrences.where((e) {
    final d = DateTime.tryParse(e['due_at_iso']?.toString() ?? '');
    return d != null && _dueLocalIsToday(d);
  }).toList();
  list.sort((a, b) {
    final da = DateTime.tryParse(a['due_at_iso']?.toString() ?? '');
    final db = DateTime.tryParse(b['due_at_iso']?.toString() ?? '');
    if (da == null || db == null) return 0;
    return da.compareTo(db);
  });
  return list;
}

class MedicineRemindersTab extends StatelessWidget {
  const MedicineRemindersTab({
    super.key,
    required this.occurrences,
    required this.schedules,
    required this.familyMembers,
    required this.api,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> occurrences;
  final List<Map<String, dynamic>> schedules;
  final List<Map<String, dynamic>> familyMembers;
  final MediBuddyApi api;
  final Future<void> Function() onRefresh;

  Future<void> _openEditor(BuildContext context, Map<String, dynamic>? existing) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScheduleEditorSheet(
        api: api,
        familyMembers: familyMembers,
        existing: existing,
      ),
    );
    if (changed == true) await onRefresh();
  }

  Future<void> _confirmDelete(BuildContext context, String id, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('Remove schedule for $label?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await api.deleteMedicineSchedule(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder removed.')));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
    await onRefresh();
  }

  Iterable<Widget> _occurrenceTiles(BuildContext context, DateFormat fmt, List<Map<String, dynamic>> occurrences) sync* {
    if (occurrences.isEmpty) {
      yield Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Nothing scheduled for today.\nCreate a reminder or check back when a dose is due.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black45),
        ),
      );
      return;
    }
    final n = occurrences.length.clamp(0, 40);
    for (var idx = 0; idx < n; idx++) {
      if (idx > 0) yield const SizedBox(height: 8);
      final m = occurrences[idx];
      final when = DateTime.tryParse((m['due_at_iso'] ?? '').toString());
      final s = when == null ? '—' : fmt.format(when.toLocal());
      yield Card(
        child: ListTile(
          leading: Icon(Icons.notifications_active_outlined, color: MediSathiColors.brandBlue),
          title: Text(m['medication_name']?.toString() ?? 'Medicine', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            [
              if ((m['dosage_text'] ?? '').toString().trim().isNotEmpty) m['dosage_text'].toString(),
              if ((m['meal_instruction'] ?? '').toString().trim().isNotEmpty) m['meal_instruction'].toString(),
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(s, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      );
    }
  }

  Iterable<Widget> _scheduleTiles(BuildContext context, List<Map<String, dynamic>> sorted) sync* {
    if (sorted.isEmpty) {
      yield Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(
          'No schedules yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black45),
        ),
      );
      return;
    }
    for (var idx = 0; idx < sorted.length; idx++) {
      if (idx > 0) yield const SizedBox(height: 10);
      final sch = sorted[idx];
      final id = sch['id']?.toString() ?? '';
      final name = sch['medication_name']?.toString() ?? 'Medicine';
      final src = sch['source']?.toString() ?? '';
      final badge = src == 'prescription_generated' ? 'From prescription' : 'Custom';
      final times = _timePointsFromRow(sch['time_points']).join(', ');
      final sd = sch['start_date']?.toString() ?? '';
      final ed = sch['end_date']?.toString();
      final range = ed != null && ed.toString().isNotEmpty ? '$sd → $ed' : '$sd → open-ended';
      yield Card(
        child: ListTile(
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$badge\n$range · $times', style: Theme.of(context).textTheme.bodySmall),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _openEditor(context, sch);
              if (v == 'delete') _confirmDelete(context, id, name);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd().add_jm();
    final sorted = [...schedules];
    sorted.sort((a, b) {
      final sa = '${a['start_date'] ?? ''}';
      final sb = '${b['start_date'] ?? ''}';
      return sa.compareTo(sb);
    });
    final todayOcc = _occurrencesDueToday(occurrences);

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 108),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14, top: 4),
                child: Text(
                  'End dates are optional. If duration is unclear, reminders stay open until you edit them.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.35),
                ),
              ),
              Text("Today's doses", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Only shows what is due today (local time).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.3),
              ),
              const SizedBox(height: 10),
              ..._occurrenceTiles(context, fmt, todayOcc),
              const SizedBox(height: 24),
              Text('Reminder schedules', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Edit auto-generated schedules or add your own. Use "Course days" to derive an end date from the start.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              ..._scheduleTiles(context, sorted),
            ],
          ),
        ),
        Positioned(
          right: 18,
          bottom: 28,
          child: FloatingActionButton.extended(
            onPressed: () => _openEditor(context, null),
            icon: const Icon(Icons.add_alarm_rounded),
            label: const Text('Custom'),
            foregroundColor: Colors.white,
            backgroundColor: MediSathiColors.brandBlue,
          ),
        ),
      ],
    );
  }
}

class _ScheduleEditorSheet extends StatefulWidget {
  const _ScheduleEditorSheet({
    required this.api,
    required this.familyMembers,
    this.existing,
  });

  final MediBuddyApi api;
  final List<Map<String, dynamic>> familyMembers;
  final Map<String, dynamic>? existing;

  @override
  State<_ScheduleEditorSheet> createState() => _ScheduleEditorSheetState();
}

class _ScheduleEditorSheetState extends State<_ScheduleEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _dosage;
  late final TextEditingController _meal;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _courseDays;
  late final TextEditingController _times;
  String? _familyId;

  bool _busy = false;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now().toUtc().toIso8601String().split('T').first;

    _name = TextEditingController(text: e == null ? '' : '${e['medication_name'] ?? ''}');
    _dosage = TextEditingController(text: e == null ? '' : '${e['dosage_text'] ?? ''}');
    _meal = TextEditingController(text: e == null ? '' : '${e['meal_instruction'] ?? ''}');
    final sd = e == null ?
        now
        : (e['start_date'] != null ? e['start_date'].toString() : now);
    _start = TextEditingController(text: sd);
    _end = TextEditingController(text: e != null && e['end_date'] != null ? e['end_date'].toString() : '');
    _courseDays = TextEditingController();
    _times = TextEditingController(
      text: e == null ?
          '09:00'
          : _timePointsFromRow(e['time_points']).join(', '),
    );
    if (e != null && e['family_member_id'] != null) {
      final id = e['family_member_id'].toString();
      final ok = widget.familyMembers.any((m) => m['id']?.toString() == id);
      _familyId = ok ? id : null;
    } else if (widget.familyMembers.length == 1) {
      _familyId = widget.familyMembers.first['id']?.toString();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _meal.dispose();
    _start.dispose();
    _end.dispose();
    _courseDays.dispose();
    _times.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    var timesList = _parseTimesInput(_times.text);
    if (timesList.isEmpty) timesList = ['09:00'];

    final sd = _start.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(sd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use start date yyyy-mm-dd (e.g. 2026-05-01).')),
      );
      return;
    }

    final cdRaw = _courseDays.text.trim();
    var endResolved = _end.text.trim();
    if (cdRaw.isNotEmpty && endResolved.isEmpty) {
      final n = int.tryParse(cdRaw);
      if (n == null || n <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Course days must be a positive integer.')));
        return;
      }
      endResolved = _isoEndFromStartAndDays(sd, n) ?? '';
    }

    setState(() => _busy = true);
    try {
      if (_isEdit) {
        final id = widget.existing!['id']?.toString() ?? '';
        final patch = <String, dynamic>{
          'medication_name': name,
          'start_date': sd,
          'time_points': timesList,
          'dosage_text': _dosage.text.trim().isEmpty ? null : _dosage.text.trim(),
          'meal_instruction': _meal.text.trim().isEmpty ? null : _meal.text.trim(),
        };

        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(endResolved)) {
          patch['end_date'] = endResolved;
        } else {
          patch['end_date'] = null;
        }

        if (_familyId != null && _familyId!.isNotEmpty) {
          patch['family_member_id'] = _familyId;
        } else {
          patch['family_member_id'] = null;
        }

        await widget.api.updateMedicineSchedule(id, patch);
      } else {
        final body = <String, dynamic>{
          'medication_name': name,
          'source': 'manual',
          'schedule_kind': 'daily',
          'start_date': sd,
          'time_points': timesList,
        };
        final d = _dosage.text.trim();
        if (d.isNotEmpty) body['dosage_text'] = d;
        final ml = _meal.text.trim();
        if (ml.isNotEmpty) body['meal_instruction'] = ml;

        if (cdRaw.isNotEmpty) {
          final n = int.tryParse(cdRaw);
          if (n != null && n > 0) body['course_days'] = n;
        } else if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_end.text.trim())) {
          body['end_date'] = _end.text.trim();
        }

        if (_familyId != null && _familyId!.isNotEmpty) body['family_member_id'] = _familyId;

        await widget.api.createMedicineSchedule(body);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom.clamp(0.0, double.infinity));
    return Padding(
      padding: pad,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, -8))],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      _isEdit ? 'Edit reminder' : 'Custom reminder',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Medication name')),
                const SizedBox(height: 16),
                TextField(controller: _dosage, decoration: const InputDecoration(labelText: 'Dosage (optional)')),
                const SizedBox(height: 16),
                TextField(controller: _meal, decoration: const InputDecoration(labelText: 'With food / cue (optional)')),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Household profile (optional)'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: (_familyId != null &&
                              widget.familyMembers.any((m) => m['id']?.toString() == _familyId))
                          ? _familyId
                          : '',
                      items: [
                        const DropdownMenuItem(value: '', child: Text('— None —')),
                        ...widget.familyMembers.where((m) => m['id'] != null).map(
                              (m) => DropdownMenuItem<String>(
                                value: m['id'].toString(),
                                child: Text(m['display_name']?.toString() ?? 'Member'),
                              ),
                            ),
                      ],
                      onChanged: (v) => setState(() => _familyId = (v != null && v.isNotEmpty) ? v : null),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(controller: _start, decoration: const InputDecoration(labelText: 'Start date (yyyy-mm-dd)')),
                const SizedBox(height: 16),
                TextField(controller: _courseDays, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Course length (days, optional)', hintText: 'Derives end from start')),
                const SizedBox(height: 16),
                TextField(
                  controller: _end,
                  decoration: const InputDecoration(
                    labelText: 'End date (yyyy-mm-dd, optional)',
                    hintText: 'Leave blank for open-ended',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(controller: _times, decoration: const InputDecoration(labelText: 'Times (comma-separated HH:mm)', hintText: '08:00, 20:00')),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: Text(_busy ? 'Saving…' : 'Save reminder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
