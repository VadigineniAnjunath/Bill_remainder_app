// Phone reminders for Bill Radar.
// Every time the data changes (or the app opens) all reminders for the next
// 35 days are rebuilt and handed to Android, which shows them even when the
// app is closed.

import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'logic.dart';
import 'models.dart';

class _Reminder {
  final tz.TZDateTime when;
  final String title;
  final String body;
  _Reminder(this.when, this.title, this.body);
}

class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  // settings (kept on the phone)
  static bool enabled = true;
  static bool dayBefore = true;
  static int hour = 9;
  static int minute = 0;

  static const _maxScheduled = 60;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'bill_radar_reminders',
      'Payment reminders',
      channelDescription: 'Due dates, savings and transfers',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static String timeLabel() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('notify.enabled') ?? true;
    dayBefore = p.getBool('notify.dayBefore') ?? true;
    hour = p.getInt('notify.hour') ?? 9;
    minute = p.getInt('notify.minute') ?? 0;
    _ready = true;
  }

  static Future<void> saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('notify.enabled', enabled);
    await p.setBool('notify.dayBefore', dayBefore);
    await p.setInt('notify.hour', hour);
    await p.setInt('notify.minute', minute);
  }

  /// Asks Android 13+ for permission. Returns true when allowed.
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static Future<void> test() async {
    await init();
    await _plugin.show(9999, 'Bill Radar', 'Notifications work ✓ Reminders come at ${timeLabel()}.', _details);
  }

  /// Cancels all reminders and schedules the upcoming ones. Returns how many.
  static Future<int> reschedule(AppState s) async {
    await init();
    await _plugin.cancelAll();
    if (!enabled) return 0;
    final list = plan(s);
    final n = min(list.length, _maxScheduled);
    for (var i = 0; i < n; i++) {
      final r = list[i];
      await _plugin.zonedSchedule(
        i + 1,
        r.title,
        r.body,
        r.when,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    return n;
  }

  /// All reminders for the next 35 days, earliest first.
  static List<_Reminder> plan(AppState s) {
    final now = tz.TZDateTime.now(tz.local);
    final horizon = iso(todayD().add(const Duration(days: 35)));
    final out = <_Reminder>[];

    void at(String day, String title, String body) {
      final d = parseD(day);
      final t = tz.TZDateTime(tz.local, d.year, d.month, d.day, hour, minute);
      if (t.isAfter(now)) out.add(_Reminder(t, title, body));
    }

    String dayBeforeOf(String day) => iso(parseD(day).subtract(const Duration(days: 1)));

    for (final b in s.bills) {
      final acc = accName[b.acc] ?? b.acc;
      var d = b.date;
      var owed = isLoan(b) ? b.owed! : double.infinity;
      var cnt = isChit(b) ? b.monthsLeft! : 1 << 30;
      var g = 0;
      while (d.compareTo(horizon) <= 0 && owed > 0.005 && cnt > 0 && g++ < 10) {
        final amt = min(b.amt, owed);
        if (dayBefore) at(dayBeforeOf(d), '${b.name} due tomorrow', '${eur(amt)} from $acc');
        at(d, '${b.name} due today', '${eur(amt)} from $acc');
        owed = r2(owed - amt);
        cnt--;
        if (b.rep == 'none') break;
        d = advance(d, b.rep);
      }

      // monthly saving for quarterly / yearly payments
      final p = savePlan(b);
      if (p != null && p.remain > 0.005) {
        at(p.next, 'Save for ${b.name}', 'Move ${eur(p.amt)} to ${placeOf(b)} · saved ${eur(p.saved)} of ${eur(b.amt)}');
      }

      // an EMI or chitti that ends soon
      if (isLoan(b) || isChit(b)) {
        final free = nextFirst(isLoan(b) ? emiEnd(b) : chitEnd(b));
        if (free.compareTo(horizon) <= 0) {
          at(free, '${b.name} is finished 🎉', '+${eur(b.amt)}/month is free now. Move it to savings.');
        }
      }
    }

    // already finished, money free from a future month
    for (final f in s.freed) {
      if (f.from.compareTo(horizon) <= 0) {
        at(f.from, '${f.name} is finished 🎉', '+${eur(f.amt)}/month is free now. Move it to savings.');
      }
    }

    // overdue payments: one reminder today
    final overdue = s.bills.where((b) => daysUntil(b.date) < 0).toList();
    if (overdue.isNotEmpty) {
      at(todayS(), '${overdue.length} payment${overdue.length == 1 ? '' : 's'} overdue',
          overdue.map((b) => b.name).join(', '));
    }

    // transfer reminder on the 1st of next month
    final t = todayD();
    final first = iso(DateTime.utc(t.year, t.month + 1, 1));
    final totals = accountTotals(s);
    for (final k in ['cb', 'n26']) {
      if (k == s.salaryAcc) continue;
      final a = totals[k]!;
      if (a.avg > 0) {
        at(first, 'Transfer to ${accName[k]}', 'Move about ${eur(a.avg)} from ${accName[s.salaryAcc]} to ${accName[k]} this month');
      }
    }

    out.sort((a, b) => a.when.compareTo(b.when));
    return out;
  }
}
