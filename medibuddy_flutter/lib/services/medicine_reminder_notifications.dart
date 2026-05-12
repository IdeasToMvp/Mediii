import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _prefsScheduledKeys = 'medicine_reminder_scheduled_occurrence_keys';

int _stableNotifHash31(String input) {
  var h = 0;
  for (final c in input.codeUnits) {
    h = 0x1fffffff & (h + c);
    h = 0x1fffffff & (h + ((h & 0xffff) << 10));
    h ^= h >> 6;
  }
  h = 0x1fffffff & (h + ((h & 0xfffffff) << 3));
  h ^= h >> 11;
  h = 0x1fffffff & (h + ((h & 0x3fff) << 15));
  h ^= h >> 10;
  final v = h & 0x7fffffff;
  return v == 0 ? 1 : v;
}

/// Three stable Android/iOS notification IDs per occurrence (T−10m, T−5m, T).
List<int> reminderNotificationIds(String occurrenceKey) => [
      _stableNotifHash31('$occurrenceKey|t10'),
      _stableNotifHash31('$occurrenceKey|t5'),
      _stableNotifHash31('$occurrenceKey|t0'),
    ];

/// Three reminders per dose: 10 min before, 5 min before, at due time (local clock).
class MedicineReminderNotifications {
  MedicineReminderNotifications._();
  static final MedicineReminderNotifications instance = MedicineReminderNotifications._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (kIsWeb) return;
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    _initialized = true;
  }

  Future<bool> requestPermissionsIfNeeded() async {
    if (kIsWeb) return false;
    await ensureInitialized();
    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission();
      return granted ?? false;
    }
    if (Platform.isIOS) {
      final r = await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return r ?? false;
    }
    return false;
  }

  Future<void> cancelForOccurrence(String occurrenceKey) async {
    if (kIsWeb) return;
    await ensureInitialized();
    for (final id in reminderNotificationIds(occurrenceKey)) {
      await _plugin.cancel(id);
    }
  }

  /// Schedules local notifications from API occurrence maps (expects `id`, `due_at_iso`,
  /// `medication_name`, optional `adherence_status`).
  Future<void> syncFromOccurrences(List<Map<String, dynamic>> occurrences) async {
    if (kIsWeb) return;
    await ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getStringList(_prefsScheduledKeys) ?? [];
    final nextKeys = <String>{};

    final androidDetails = AndroidNotificationDetails(
      'medicine_reminders',
      'Medicine reminders',
      channelDescription: 'Reminders before each scheduled dose',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final now = tz.TZDateTime.now(tz.local);

    for (final o in occurrences) {
      final key = o['id']?.toString();
      if (key == null || key.isEmpty) continue;
      final status = o['adherence_status']?.toString() ?? 'upcoming';
      if (status == 'taken' || status == 'auto_taken') continue;

      final dueRaw = o['due_at_iso']?.toString();
      if (dueRaw == null) continue;
      final dueUtc = DateTime.tryParse(dueRaw);
      if (dueUtc == null) continue;
      final due = tz.TZDateTime.from(dueUtc, tz.local);
      if (!due.isAfter(now)) continue;

      final name = o['medication_name']?.toString().trim().isNotEmpty == true
          ? o['medication_name'].toString()
          : 'Medicine';
      nextKeys.add(key);

      final times = <({tz.TZDateTime at, String title, String body})>[
        (at: due.subtract(const Duration(minutes: 10)), title: 'Dose soon', body: '$name in 10 minutes'),
        (at: due.subtract(const Duration(minutes: 5)), title: 'Dose soon', body: '$name in 5 minutes'),
        (at: due, title: 'Time for medicine', body: name),
      ];

      final ids = reminderNotificationIds(key);
      for (var i = 0; i < times.length; i++) {
        final t = times[i];
        if (!t.at.isAfter(now)) continue;
        try {
          await _plugin.zonedSchedule(
            ids[i],
            t.title,
            t.body,
            t.at,
            details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: key,
          );
        } catch (e, st) {
          debugPrint('medicine_reminder schedule failed: $e\n$st');
        }
      }
    }

    for (final old in prev) {
      if (!nextKeys.contains(old)) {
        await cancelForOccurrence(old);
      }
    }
    await prefs.setStringList(_prefsScheduledKeys, nextKeys.toList());
  }
}
