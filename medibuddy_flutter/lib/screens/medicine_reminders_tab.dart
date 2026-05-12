import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/medibuddy_api.dart';
import '../services/medicine_reminder_notifications.dart';
import '../theme/medisathi_colors.dart';
import '../utils/medicine_schedule_times.dart';

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

(String label, Color fg) _adherenceLabel(String? raw) {
  switch (raw) {
    case 'taken':
      return ('Taken', Colors.green.shade800);
    case 'missed':
      return ('Missed', Colors.deepOrange.shade800);
    case 'auto_taken':
      return ('Missed · auto-logged', Colors.blueGrey.shade700);
    default:
      return ('', Colors.black54);
  }
}

Future<void> _markDoseTaken(
  BuildContext context,
  MediBuddyApi api,
  Future<void> Function() onRefresh,
  String occurrenceKey, {
  Future<void> Function(String occurrenceKey)? delegate,
}) async {
  if (delegate != null) {
    await delegate(occurrenceKey);
    return;
  }
  try {
    await api.markMedicineDoseTaken(occurrenceKey);
    if (!kIsWeb) await MedicineReminderNotifications.instance.cancelForOccurrence(occurrenceKey);
    await onRefresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked taken.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }
}

class MedicineRemindersTab extends StatelessWidget {
  const MedicineRemindersTab({
    super.key,
    required this.occurrences,
    required this.schedules,
    required this.familyMembers,
    required this.api,
    required this.onRefresh,
    this.onMarkMedicineTaken,
  });

  final List<Map<String, dynamic>> occurrences;
  final List<Map<String, dynamic>> schedules;
  final List<Map<String, dynamic>> familyMembers;
  final MediBuddyApi api;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String occurrenceKey)? onMarkMedicineTaken;

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
      final occId = m['id']?.toString() ?? '';
      final status = m['adherence_status']?.toString() ?? 'upcoming';
      final ad = _adherenceLabel(status);
      final showMark = occId.isNotEmpty && status != 'taken' && status != 'auto_taken';
      final subParts = <String>[
        if ((m['dosage_text'] ?? '').toString().trim().isNotEmpty) m['dosage_text'].toString(),
        if ((m['meal_instruction'] ?? '').toString().trim().isNotEmpty) m['meal_instruction'].toString(),
      ];
      yield Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.notifications_active_outlined, color: MediSathiColors.brandBlue, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['medication_name']?.toString() ?? 'Medicine',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    if (subParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subParts.join(' · '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black87, height: 1.25),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  if (ad.$1.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(ad.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ad.$2)),
                  ],
                  if (showMark) ...[
                    const SizedBox(height: 2),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: MediSathiColors.brandBlue,
                      ),
                      onPressed: () => _markDoseTaken(context, api, onRefresh, occId, delegate: onMarkMedicineTaken),
                      child: const Text('Taken', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ],
          ),
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
      final sd = sch['start_date']?.toString() ?? '';
      final tps = _timePointsFromRow(sch['time_points']);
      final jm = DateFormat.jm();
      final sortedLocal = <({String hmUtc, DateTime local})>[];
      for (final hm in tps) {
        final loc = utcHmOnUtcDayToLocal(sd, hm);
        if (loc != null) sortedLocal.add((hmUtc: hm, local: loc));
      }
      sortedLocal.sort((a, b) => a.local.compareTo(b.local));
      final timesLocal =
          sortedLocal.isEmpty ? tps.join(', ') : sortedLocal.map((e) => jm.format(e.local)).join(', ');
      final freq = scheduleKindLabel(sch['schedule_kind']?.toString());
      final n = tps.length;
      final ed = sch['end_date']?.toString();
      final range = ed != null && ed.toString().isNotEmpty ? '$sd → $ed' : '$sd → open-ended';
      yield Card(
        child: ListTile(
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '$badge · $freq · $n×/day\n$range\nLocal times: $timesLocal',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
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
                'Only shows what is due today (your device time). Times match the schedule list below.',
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
  String? _familyId;

  int _dosesPerDay = 1;
  late List<TimeOfDay> _slotTimes;

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
    final sd = e == null ? now : (e['start_date'] != null ? e['start_date'].toString() : now);
    _start = TextEditingController(text: sd);
    _end = TextEditingController(text: e != null && e['end_date'] != null ? e['end_date'].toString() : '');
    _courseDays = TextEditingController();

    final tps = e == null ? <String>['09:00'] : _timePointsFromRow(e['time_points']);
    _dosesPerDay = tps.isEmpty ? 1 : tps.length.clamp(1, 12);
    _slotTimes = <TimeOfDay>[];
    for (final hm in tps.take(_dosesPerDay)) {
      _slotTimes.add(utcHmOnUtcDayToLocalTimeOfDay(sd, hm) ?? const TimeOfDay(hour: 9, minute: 0));
    }
    while (_slotTimes.length < _dosesPerDay) {
      _slotTimes.add(_slotTimes.isNotEmpty ? _slotTimes.last : const TimeOfDay(hour: 9, minute: 0));
    }

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
    super.dispose();
  }

  void _onDosesPerDayChanged(int? v) {
    if (v == null || v == _dosesPerDay) return;
    setState(() {
      final old = [..._slotTimes];
      _dosesPerDay = v;
      _slotTimes = List.generate(v, (i) {
        if (i < old.length) return old[i];
        return old.isNotEmpty ? old.last : const TimeOfDay(hour: 9, minute: 0);
      });
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final sd = _start.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(sd)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use start date yyyy-mm-dd (e.g. 2026-05-01).')),
      );
      return;
    }

    final timesList = _slotTimes.take(_dosesPerDay).map((t) => localTimeOfDayToUtcHm(sd, t)).toList();
    if (timesList.toSet().length != timesList.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Each dose time must be different.')),
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
                Text(
                  'Doses use your phone\'s local time. Pick how many times per day, then each time (30-minute steps).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.35),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Times per day'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _dosesPerDay,
                      items: [
                        for (var i = 1; i <= 12; i++)
                          DropdownMenuItem(value: i, child: Text('$i× per day')),
                      ],
                      onChanged: _onDosesPerDayChanged,
                    ),
                  ),
                ),
                for (var i = 0; i < _dosesPerDay; i++) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text('Dose ${i + 1}', style: Theme.of(context).textTheme.labelLarge),
                      ),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<TimeOfDay>(
                              isExpanded: true,
                              isDense: true,
                              value: _slotTimes[i],
                              items: [
                                for (final t in slotChoicesIncluding(_slotTimes[i]))
                                  DropdownMenuItem<TimeOfDay>(
                                    value: t,
                                    child: Text(formatTimeOfDay(context, t)),
                                  ),
                              ],
                              onChanged: (t) {
                                if (t == null) return;
                                setState(() => _slotTimes[i] = t);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
