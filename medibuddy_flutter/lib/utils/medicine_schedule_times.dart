import 'package:flutter/material.dart';

/// Backend stores [time_points] as UTC clock times on each UTC calendar day.
/// These helpers convert for display/editing in the user's local timezone.

DateTime? _parseYmd(String ymd) {
  final p = ymd.trim().split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime.utc(y, m, d);
}

(int hh, int mm)? _parseHm(String hm) {
  final parts = hm.trim().split(':');
  if (parts.length < 2) return null;
  final hh = int.tryParse(parts[0].trim());
  final mm = int.tryParse(parts[1].trim());
  if (hh == null || mm == null) return null;
  return (hh, mm);
}

/// Single instant: UTC wall clock [hm] on calendar day [referenceYmd] (UTC date), shown in local.
DateTime? utcHmOnUtcDayToLocal(String referenceYmd, String hmUtc) {
  final day = _parseYmd(referenceYmd);
  final parsed = _parseHm(hmUtc);
  if (day == null || parsed == null) return null;
  final utc = DateTime.utc(day.year, day.month, day.day, parsed.$1, parsed.$2);
  return utc.toLocal();
}

TimeOfDay? utcHmOnUtcDayToLocalTimeOfDay(String referenceYmd, String hmUtc) {
  final local = utcHmOnUtcDayToLocal(referenceYmd, hmUtc);
  if (local == null) return null;
  return TimeOfDay(hour: local.hour, minute: local.minute);
}

/// Local wall clock on [startYmd] (interpreted as local calendar date) → UTC HH:mm for API.
String localTimeOfDayToUtcHm(String startYmd, TimeOfDay tod) {
  final p = startYmd.trim().split('-');
  if (p.length != 3) return '09:00';
  final y = int.tryParse(p[0]) ?? 2000;
  final m = int.tryParse(p[1]) ?? 1;
  final d = int.tryParse(p[2]) ?? 1;
  final local = DateTime(y, m, d, tod.hour, tod.minute);
  final u = local.toUtc();
  return '${u.hour.toString().padLeft(2, '0')}:${u.minute.toString().padLeft(2, '0')}';
}

List<TimeOfDay> allHalfHourSlots() {
  final out = <TimeOfDay>[];
  for (var h = 0; h < 24; h++) {
    out.add(TimeOfDay(hour: h, minute: 0));
    out.add(TimeOfDay(hour: h, minute: 30));
  }
  return out;
}

bool sameTimeOfDay(TimeOfDay a, TimeOfDay b) => a.hour == b.hour && a.minute == b.minute;

List<TimeOfDay> slotChoicesIncluding(TimeOfDay current) {
  final out = List<TimeOfDay>.from(allHalfHourSlots());
  if (!out.any((t) => sameTimeOfDay(t, current))) {
    out.add(current);
  }
  out.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
  return out;
}

String formatTimeOfDay(BuildContext context, TimeOfDay t) {
  return MaterialLocalizations.of(context).formatTimeOfDay(
    t,
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

String scheduleKindLabel(String? raw) {
  switch (raw) {
    case 'weekly':
      return 'Weekly';
    case 'one_off':
      return 'One-time';
    case 'daily':
    default:
      return 'Daily';
  }
}
