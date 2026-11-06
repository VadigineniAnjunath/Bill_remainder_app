// Excel report: months, payments, spending, upcoming.

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'logic.dart';
import 'models.dart';

String _monthName((String, String) p) => DateFormat('MMM yyyy').format(parseD(p.$2));

void _header(Sheet sh, List<String> cols) {
  sh.appendRow([for (final c in cols) TextCellValue(c)]);
  for (var i = 0; i < cols.length; i++) {
    sh.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle = CellStyle(bold: true);
  }
}

CellValue _t(String v) => TextCellValue(v);
CellValue _m(double v) => DoubleCellValue(r2(v));

List<int> buildReport(AppState s) {
  final x = Excel.createExcel();
  final def = x.getDefaultSheet() ?? 'Sheet1';
  x.rename(def, 'Months');
  final months = x['Months'];
  final payments = x['Payments'];
  final spending = x['Spending'];
  final upcoming = x['Upcoming'];

  // savings done (insurance etc.), from each item's saving history
  final saves = <(Bill, SaveLogEntry)>[
    for (final b in s.bills)
      for (final e in b.saveLog)
        if (e.k == 'save') (b, e),
  ];

  // ---- Months ----
  final cur = currentPeriod();
  var first = cur.$1;
  for (final e in s.paid) {
    if (e.on.compareTo(first) < 0) first = e.on;
  }
  for (final sp in s.spends) {
    if (sp.date.compareTo(first) < 0) first = sp.date;
  }
  for (final v in saves) {
    final d = v.$2.on ?? v.$2.d;
    if (d.compareTo(first) < 0) first = d;
  }
  _header(months, ['Month', 'From', 'To', 'Salary', 'Payments paid', 'Saved (insurance)', 'Spending', 'Still to pay', 'Left']);
  var p = periodOf(first);
  var guard = 0;
  while (p.$1.compareTo(cur.$1) <= 0 && guard++ < 240) {
    final paid = s.paid.where((e) => inPeriod(e.on, p)).fold<double>(0.0, (t, e) => t + e.amt);
    final saved = saves.where((v) => inPeriod(v.$2.on ?? v.$2.d, p)).fold<double>(0.0, (t, v) => t + v.$2.a);
    final spent = spentIn(s, p);
    final coming = p == cur
        ? occurrencesIn(s, '0000-01-01', cur.$2).fold<double>(0.0, (t, o) => t + o.amt)
        : 0.0;
    months.appendRow([
      _t(_monthName(p)),
      _t(fmtDate(p.$1)),
      _t(fmtDate(p.$2)),
      _m(s.salary),
      _m(paid),
      _m(saved),
      _m(spent),
      _m(coming),
      _m(s.salary - paid - saved - spent - coming),
    ]);
    p = periodAfter(p);
  }

  // ---- Payments ----
  _header(payments, ['Month', 'Due date', 'Paid on', 'Name', 'Type', 'Account', 'Amount']);
  final rows = <(String, List<CellValue>)>[
    for (final e in s.paid)
      (
        e.on,
        [
          _t(_monthName(periodOf(e.on))),
          _t(fmtDate(e.due)),
          _t(fmtDate(e.on)),
          _t(e.name),
          _t(typeLabel[e.type] ?? e.type),
          _t(accName[e.acc] ?? e.acc),
          _m(e.amt),
        ]
      ),
    for (final v in saves)
      (
        v.$2.on ?? v.$2.d,
        [
          _t(_monthName(periodOf(v.$2.on ?? v.$2.d))),
          _t(fmtDate(v.$2.d)),
          _t(fmtDate(v.$2.on ?? v.$2.d)),
          _t('Save for ${v.$1.name}'),
          _t('Saving'),
          _t(placeOf(v.$1)),
          _m(v.$2.a),
        ]
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  for (final r in rows) {
    payments.appendRow(r.$2);
  }

  // ---- Spending ----
  _header(spending, ['Month', 'Date', 'Category', 'Account', 'Note', 'Amount']);
  final sp = [...s.spends]..sort((a, b) => a.date.compareTo(b.date));
  for (final e in sp) {
    spending.appendRow([
      _t(_monthName(periodOf(e.date))),
      _t(fmtDate(e.date)),
      _t(spendCats[e.cat] ?? e.cat),
      _t(accName[e.acc] ?? e.acc),
      _t(e.note ?? ''),
      _m(e.amt),
    ]);
  }

  // ---- Upcoming ----
  _header(upcoming, ['Month', 'Date', 'Name', 'Type', 'Account', 'Amount']);
  for (final o in occurrencesIn(s, '0000-01-01', nextPeriod().$2)) {
    upcoming.appendRow([
      _t(_monthName(periodOf(o.date))),
      _t(fmtDate(o.date)),
      _t(o.saving ? 'Save for ${o.bill.name}' : o.bill.name),
      _t(o.saving ? 'Saving' : (typeLabel[o.bill.type] ?? o.bill.type)),
      _t(o.saving ? placeOf(o.bill) : (accName[o.bill.acc] ?? o.bill.acc)),
      _m(o.amt),
    ]);
  }

  x.setDefaultSheet('Months');
  return x.encode()!;
}

/// Builds the report and opens the phone's share sheet (save to Files / Drive, WhatsApp, email …).
Future<void> shareReport(AppState s) async {
  final bytes = buildReport(s);
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/BillRadar_${todayS()}.xlsx');
  await f.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(f.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
    subject: 'Bill Radar report ${todayS()}',
  ));
}
