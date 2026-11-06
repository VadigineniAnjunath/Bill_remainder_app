// Bill Radar rules, ported from the web version.
// All dates are plain yyyy-mm-dd strings; date math uses UTC to avoid
// daylight-saving surprises.

import 'dart:math';

import 'package:intl/intl.dart';

import 'models.dart';

// ---------- formatting ----------
final _eur = NumberFormat.currency(locale: 'de_DE', symbol: '€');
String eur(double n) => _eur.format(n);
String fmtDate(String s) => DateFormat('dd.MM.yyyy').format(parseD(s));
String monYr(String s) => DateFormat('MMM yyyy').format(parseD(s));

const accName = {'cb': 'Commerzbank', 'n26': 'N26', 'cash': 'Cash'};
const typeLabel = {'sub': 'Subscription', 'emi': 'EMI', 'chit': 'Chitti', 'ins': 'Insurance', 'bill': 'Bill'};
const repLabel = {'none': 'Once', 'weekly': 'Weekly', 'monthly': 'Monthly', 'quarterly': 'Quarterly', 'yearly': 'Yearly'};

// ---------- dates ----------
DateTime parseD(String s) {
  final p = s.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime todayD() {
  final n = DateTime.now();
  return DateTime.utc(n.year, n.month, n.day);
}

String todayS() => iso(todayD());
String ym(String s) => s.substring(0, 7);
double r2(double n) => n.isFinite ? (n * 100).roundToDouble() / 100 : n;
int daysUntil(String s) => parseD(s).difference(todayD()).inDays;

const _monthsOf = {'monthly': 1, 'quarterly': 3, 'yearly': 12};
const periodM = {'quarterly': 3, 'yearly': 12};
const perMonth = {'none': 0.0, 'weekly': 52 / 12, 'monthly': 1.0, 'quarterly': 1 / 3, 'yearly': 1 / 12};

/// Same day of the month, [m] months later (clamped to the month's last day).
DateTime _addMonths(DateTime d, int m) {
  final first = DateTime.utc(d.year, d.month + m, 1);
  final last = DateTime.utc(first.year, first.month + 1, 0).day;
  return DateTime.utc(first.year, first.month, min(d.day, last));
}

/// The next due date after [s] for a repeat setting.
String advance(String s, String rep) {
  final d = parseD(s);
  if (rep == 'weekly') return iso(d.add(const Duration(days: 7)));
  return iso(_addMonths(d, _monthsOf[rep] ?? 0));
}

/// The 1st of the month after [s].
String nextFirst(String s) {
  final d = parseD(s);
  return iso(DateTime.utc(d.year, d.month + 1, 1));
}

String firstOfThisMonth() {
  final t = todayD();
  return iso(DateTime.utc(t.year, t.month, 1));
}

// ---------- your month: from the rent/salary day to the day before the next one ----------
/// The day your month starts (set from the saved data). 30 = 30th → 29th.
int cycleDay = 30;

DateTime _startIn(int y, int m) {
  final first = DateTime.utc(y, m, 1); // normalises month 0 / 13
  final last = DateTime.utc(first.year, first.month + 1, 0).day;
  return DateTime.utc(first.year, first.month, min(cycleDay, last));
}

/// (start, end) of the month that contains [day].
(String, String) periodOf(String day) {
  final d = parseD(day);
  var s = _startIn(d.year, d.month);
  if (d.isBefore(s)) s = _startIn(d.year, d.month - 1);
  final ns = _startIn(s.year, s.month + 1);
  return (iso(s), iso(ns.subtract(const Duration(days: 1))));
}

(String, String) currentPeriod() => periodOf(todayS());

(String, String) periodAfter((String, String) p) =>
    periodOf(iso(parseD(p.$2).add(const Duration(days: 1))));

(String, String) nextPeriod() => periodAfter(currentPeriod());

/// Name of the month a day belongs to, as yyyy-mm of the month it ends in
/// (30 Oct – 29 Nov is "2026-11").
String periodKey(String day) => ym(periodOf(day).$2);

String periodRange((String, String) p) {
  final f = DateFormat('d MMM');
  return '${f.format(parseD(p.$1))} – ${f.format(parseD(p.$2))}';
}

/// Last day of your current month (e.g. 29 Nov).
String endOfThisMonth() => currentPeriod().$2;

/// ('over' | 'soon' | 'ok', label) for a number of days until a date.
(String, String) status(int n) {
  if (n < 0) return ('over', '${-n} day${n == -1 ? '' : 's'} overdue');
  if (n == 0) return ('over', 'Due today');
  if (n <= 3) return ('soon', 'In $n day${n == 1 ? '' : 's'}');
  return ('ok', 'In $n days');
}

// ---------- EMIs and chitti ----------
bool isLoan(Bill b) => b.type == 'emi' && b.owed != null;
bool isChit(Bill b) => b.type == 'chit' && (b.monthsLeft ?? 0) > 0;

/// What the next payment is: for a loan the last one can be smaller.
double nextAmt(Bill b) => isLoan(b) ? min(b.amt, b.owed!) : b.amt;

int paysLeft(Bill b) => b.amt <= 0 ? 0 : (r2(b.owed! / b.amt) - 1e-9).ceil();

String emiEnd(Bill b) {
  var d = b.date;
  for (var i = 1; i < paysLeft(b); i++) {
    d = advance(d, b.rep);
  }
  return d;
}

String chitEnd(Bill b) {
  var d = b.date;
  for (var i = 1; i < (b.monthsLeft ?? 1); i++) {
    d = advance(d, b.rep);
  }
  return d;
}

// ---------- set-aside savings (quarterly / yearly) ----------
bool canSetAside(Bill b) =>
    periodM.containsKey(b.rep) && b.type != 'emi' && b.type != 'chit' && b.saveTo != '';

String placeOf(Bill b) {
  if (b.saveTo == 'n26space') return 'N26 Space${b.space != null ? ' "${b.space}"' : ''}';
  return accName[b.saveTo] ?? 'savings';
}

class SavePlan {
  final double saved; // saved so far
  final double remain; // still to save
  final String next; // next saving date
  final int n; // savings left before the due date
  final double amt; // amount per saving
  const SavePlan(this.saved, this.remain, this.next, this.n, this.amt);
}

/// Save on the 1st of each month until the due date.
SavePlan? savePlan(Bill b) {
  if (!canSetAside(b)) return null;
  final remain = r2(b.amt - b.saved);
  final next = b.saveNext ?? firstOfThisMonth();
  var d = next;
  var n = 0;
  var g = 0;
  while (d.compareTo(b.date) <= 0 && g++ < 24) {
    n++;
    d = nextFirst(d);
  }
  final nn = max(1, n);
  return SavePlan(b.saved, remain, next, nn, r2(remain / nn));
}

// ---------- totals ----------
/// Average fixed cost per month.
double monthlyFixed(AppState s) =>
    s.bills.fold(0.0, (double sum, Bill b) => sum + b.amt * (perMonth[b.rep] ?? 0.0));

/// Money still to pay from today to the end of this month (overdue included).
double dueThisMonth(Bill b) {
  final end = endOfThisMonth();
  var d = b.date;
  var sum = 0.0;
  var owed = isLoan(b) ? b.owed! : double.infinity;
  var cnt = isChit(b) ? b.monthsLeft! : 1 << 30;
  var g = 0;
  while (d.compareTo(end) <= 0 && owed > 0.005 && cnt > 0 && g++ < 60) {
    final p = min(b.amt, owed);
    sum += p;
    owed = r2(owed - p);
    cnt--;
    if (b.rep == 'none') break;
    d = advance(d, b.rep);
  }
  return sum;
}

// ---------- the list on the home screen ----------
/// A row on the home screen: a payment, or a monthly "save for" reminder.
class Entry {
  final Bill bill;
  final String date;
  final SavePlan? save; // set when this row is a saving reminder
  const Entry(this.bill, this.date, [this.save]);
  String get group => status(daysUntil(date)).$1;
}

List<Entry> buildEntries(AppState s) {
  final out = <Entry>[];
  for (final b in s.bills) {
    out.add(Entry(b, b.date));
    final p = savePlan(b);
    if (p != null && p.remain > 0.005) out.add(Entry(b, p.next, p));
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

// ---------- actions ----------
/// An EMI or chitti finished: remove it and remember the freed money.
void finish(AppState s, Bill b) {
  s.bills.remove(b);
  if (!b.example) {
    s.freed.add(Freed(
      id: '${DateTime.now().microsecondsSinceEpoch}f',
      name: b.name,
      amt: b.amt,
      type: b.type,
      from: nextFirst(b.date),
    ));
  }
}

/// "Paid → next". Returns the message to show.
String pay(AppState s, Bill b) {
  if (isLoan(b)) {
    final p = nextAmt(b);
    b.owed = r2(b.owed! - p);
    if (b.owed! <= 0.005) {
      finish(s, b);
      return '${b.name} fully paid off 🎉';
    }
    b.date = advance(b.date, b.rep);
    return '${b.name}: paid ${eur(p)} · next ${eur(nextAmt(b))} on ${fmtDate(b.date)}';
  }
  if (isChit(b)) {
    b.monthsLeft = b.monthsLeft! - 1;
    if (b.monthsLeft! <= 0) {
      finish(s, b);
      return '${b.name} complete 🎉';
    }
    b.date = advance(b.date, b.rep);
    return '${b.name} paid · ${b.monthsLeft} months left';
  }
  if (b.rep == 'none') {
    s.bills.remove(b);
    return '${b.name} paid';
  }
  if (savePlan(b) != null) {
    b.saveLog.add(SaveLogEntry(k: 'paid', d: b.date, a: b.amt, from: b.saved, on: todayS()));
    b.saved = 0;
    b.saveNext = nextFirst(b.date);
  }
  b.date = advance(b.date, b.rep);
  return '${b.name} paid · next ${fmtDate(b.date)}';
}

/// "Paid" with a record of it, so it shows under "Paid this month" and can be undone.
String payAndLog(AppState s, Bill b) {
  final entry = PaidEntry(
    id: '${DateTime.now().microsecondsSinceEpoch}p',
    billId: b.id,
    name: b.name,
    type: b.type,
    acc: b.acc,
    amt: nextAmt(b),
    due: b.date,
    on: todayS(),
    before: b.toJson(),
  );
  final msg = pay(s, b);
  s.paid.add(entry);
  if (s.paid.length > 300) s.paid.removeRange(0, s.paid.length - 300);
  return msg;
}

/// Undo is only possible for the most recent payment of an item.
bool canUndo(AppState s, PaidEntry e) => s.paid.lastWhere((p) => p.billId == e.billId) == e;

String undoPaid(AppState s, PaidEntry e) {
  final restored = Bill.fromJson(e.before);
  final i = s.bills.indexWhere((x) => x.id == e.billId);
  if (i >= 0) {
    s.bills[i] = restored;
  } else {
    // it had finished and was removed: bring it back
    s.bills.add(restored);
    final f = s.freed.where((x) => x.name == e.name).toList();
    if (f.isNotEmpty) s.freed.remove(f.last);
  }
  s.paid.remove(e);
  return '${e.name} is pending again';
}

/// One payment (or monthly saving) on one day.
class Occ {
  final Bill bill;
  final String date;
  final double amt;
  final bool saving;
  const Occ(this.bill, this.date, this.amt, {this.saving = false});
}

/// Every payment and saving due between [from] and [to] (inclusive).
List<Occ> occurrencesIn(AppState s, String from, String to) {
  final out = <Occ>[];
  for (final b in s.bills) {
    var d = b.date;
    var owed = isLoan(b) ? b.owed! : double.infinity;
    var cnt = isChit(b) ? b.monthsLeft! : 1 << 30;
    var g = 0;
    while (d.compareTo(to) <= 0 && owed > 0.005 && cnt > 0 && g++ < 400) {
      final a = min(b.amt, owed);
      if (d.compareTo(from) >= 0) out.add(Occ(b, d, a));
      owed = r2(owed - a);
      cnt--;
      if (b.rep == 'none') break;
      d = advance(d, b.rep);
    }
    final p = savePlan(b);
    if (p != null) {
      var sd = p.remain > 0.005 ? p.next : nextFirst(b.date);
      var g2 = 0;
      while (sd.compareTo(to) <= 0 && g2++ < 40) {
        final a = sd.compareTo(b.date) <= 0 ? p.amt : r2(b.amt / periodM[b.rep]!);
        if (sd.compareTo(from) >= 0 && a > 0.005) out.add(Occ(b, sd, a, saving: true));
        sd = nextFirst(sd);
      }
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// "Saved ✓" on a monthly saving reminder.
String markSaved(Bill b, SavePlan p) {
  b.saved = r2(b.saved + p.amt);
  b.saveNext = nextFirst(p.next);
  b.saveLog.add(SaveLogEntry(k: 'save', d: p.next, a: p.amt, on: todayS()));
  return b.saved >= b.amt - 0.005
      ? '${b.name} fully saved ✓'
      : 'Saved ${eur(p.amt)} · ${eur(b.saved)} of ${eur(b.amt)}';
}

/// Number of payments from [start] up to and including [end].
int countUntil(String start, String rep, String end) {
  var d = start;
  var n = 0;
  var g = 0;
  while (d.compareTo(end) <= 0 && g++ < 600) {
    n++;
    d = advance(d, rep);
  }
  return n;
}

/// The due date before [s] (null for one-off payments).
String? back(String s, String rep) {
  final d = parseD(s);
  if (rep == 'weekly') return iso(d.subtract(const Duration(days: 7)));
  final m = _monthsOf[rep];
  if (m == null) return null;
  return iso(_addMonths(d, -m));
}

// ---------- accounts ----------
class AccTotal {
  double avg = 0; // average per month
  double month = 0; // still due this month
}

Map<String, AccTotal> accountTotals(AppState s) {
  final m = <String, AccTotal>{'cb': AccTotal(), 'n26': AccTotal(), 'cash': AccTotal()};
  for (final b in s.bills) {
    final a = m[b.acc] ?? m['cb']!;
    a.avg += b.amt * (perMonth[b.rep] ?? 0.0);
    a.month += dueThisMonth(b);
  }
  if (m['cash']!.avg == 0 && m['cash']!.month == 0) m.remove('cash');
  return m;
}

/// "Move X from Commerzbank to N26 …" and set-aside instructions.
List<String> transferLines(AppState s) {
  final t = accountTotals(s);
  final from = accName[s.salaryAcc] ?? 'Commerzbank';
  final lines = <String>[];
  for (final k in ['cb', 'n26']) {
    if (k == s.salaryAcc) continue;
    final a = t[k]!;
    if (a.avg > 0 || a.month > 0) {
      lines.add('Move ${eur(a.month)} from $from to ${accName[k]} this month, and about ${eur(a.avg)} every month after that.');
    }
  }
  final cash = t['cash'];
  if (cash != null && cash.month > 0) lines.add('Withdraw ${eur(cash.month)} cash for payments still due this month.');
  final end = endOfThisMonth();
  final places = <String, List<double>>{};
  final names = <String, List<String>>{};
  for (final b in s.bills) {
    final p = savePlan(b);
    if (p == null) continue;
    final k = placeOf(b);
    final v = places.putIfAbsent(k, () => [0.0, 0.0, 0.0]);
    if (p.remain > 0.005 && p.next.compareTo(end) <= 0) v[0] += p.amt;
    v[1] += p.saved;
    v[2] += b.amt;
    names.putIfAbsent(k, () => []).add(b.name);
  }
  places.forEach((k, v) {
    final n = names[k]!.join(', ');
    lines.add(v[0] > 0.005
        ? 'Move ${eur(v[0])} to $k this month for $n. Saved so far ${eur(v[1])} of ${eur(v[2])}.'
        : '$k is done for this month for $n. Saved ${eur(v[1])} of ${eur(v[2])}.');
  });
  return lines;
}

// ---------- 12-month summary ----------
const sumCols = [('emi', 'EMIs'), ('chit', 'Chitti'), ('ins', 'Insurance'), ('sub', 'Subs'), ('bill', 'Bills')];

class MonthRow {
  final String month; // yyyy-mm
  final Map<String, double> by = {'emi': 0, 'chit': 0, 'ins': 0, 'sub': 0, 'bill': 0};
  final List<String> ends = [];
  MonthRow(this.month);
  double get out => by.values.fold(0.0, (double a, double b) => a + b);
}

List<MonthRow> summaryRows(AppState s) {
  final t = todayD();
  final today = todayS();
  final months = <String>[];
  final rows = <String, MonthRow>{};
  for (var i = 0; i < 12; i++) {
    final m = iso(DateTime.utc(t.year, t.month + i, 1)).substring(0, 7);
    months.add(m);
    rows[m] = MonthRow(m);
  }
  final cur = months.first;
  final last = months.last;
  void add(String d, String type, double a) {
    var m = ym(d);
    if (m.compareTo(cur) < 0) m = cur;
    final r = rows[m];
    if (r != null) r.by[type] = (r.by[type] ?? 0) + a;
  }

  for (final b in s.bills) {
    final p = savePlan(b);
    if (p != null) {
      // set-aside items count the monthly saving, not the big payment
      for (final e in b.saveLog) {
        if (e.k == 'save' && ym(e.d) == cur) add(e.d, b.type, e.a);
      }
      if (p.remain > 0.005) {
        var d = p.next;
        var g = 0;
        while (d.compareTo(b.date) <= 0 && g++ < 24) {
          add(d, b.type, p.amt);
          d = nextFirst(d);
        }
      }
      final st = r2(b.amt / periodM[b.rep]!);
      var d = nextFirst(b.date);
      var g = 0;
      while (ym(d).compareTo(last) <= 0 && g++ < 24) {
        add(d, b.type, st);
        d = nextFirst(d);
      }
      continue;
    }
    // a payment made earlier this month (its date has already moved on)
    if (b.rep != 'none') {
      var pd = back(b.date, b.rep);
      var g = 0;
      while (pd != null && ym(pd) == cur && pd.compareTo(today) < 0 && g++ < 6) {
        add(pd, b.type, b.amt);
        pd = back(pd, b.rep);
      }
    }
    var owed = isLoan(b) ? b.owed! : double.infinity;
    var cnt = isChit(b) ? b.monthsLeft! : 1 << 30;
    var d = b.date;
    var g = 0;
    String? lastPay;
    while (ym(d).compareTo(last) <= 0 && owed > 0.005 && cnt > 0 && g++ < 400) {
      final a = min(b.amt, owed);
      add(d, b.type, a);
      owed = r2(owed - a);
      cnt--;
      lastPay = d;
      if (b.rep == 'none') break;
      d = advance(d, b.rep);
    }
    if ((isLoan(b) || isChit(b)) && lastPay != null && (owed <= 0.005 || cnt <= 0)) {
      var m = ym(lastPay);
      if (m.compareTo(cur) < 0) m = cur;
      rows[m]?.ends.add('${b.name} ends, +${eur(b.amt)}/mo after');
    }
  }
  return [for (final m in months) rows[m]!];
}

/// "Skip this month" on a saving reminder.
String skipSaving(Bill b, SavePlan p) {
  b.saveNext = nextFirst(p.next);
  final np = savePlan(b)!;
  return 'Skipped · next saving ${eur(np.amt)} on ${fmtDate(np.next)}';
}
