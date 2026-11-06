// Bill Radar — v7: spending tab, Excel report, paid history.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'forms.dart';
import 'logic.dart';
import 'models.dart';
import 'notifications.dart';
import 'report.dart';
import 'store.dart';

void main() => runApp(const BillRadarApp());

class BillRadarApp extends StatelessWidget {
  const BillRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2347C7);
    return MaterialApp(
      title: 'Bill Radar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppState? _s;
  int _tab = 0;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var s = await Store.load();
    String? msg;
    if (s == null) {
      s = await Store.bundledBackup();
      if (s != null) {
        await Store.save(s);
        msg = 'Imported your backup: ${s.bills.length} payments, ${s.debts.length} debts';
      }
    }
    if (!mounted) return;
    cycleDay = (s ?? AppState.empty()).cycleDay;
    setState(() => _s = s ?? AppState.empty());
    if (msg != null) _toast(msg);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('backfill.v1') ?? false)) {
        if (backfillPaid(_s!) > 0) {
          await Store.save(_s!);
          if (mounted) setState(() {});
        }
        await prefs.setBool('backfill.v1', true);
      }
    } catch (e) {
      debugPrint('backfill: $e');
    }
    try {
      await Notifier.init();
      await Notifier.requestPermission();
    } catch (e) {
      debugPrint('notifications: $e');
    }
    await _resched();
  }

  int _scheduled = 0;

  /// Rebuild all phone reminders from the current data.
  Future<void> _resched() async {
    try {
      _scheduled = await Notifier.reschedule(_s!);
    } catch (e) {
      debugPrint('notifications: $e');
    }
  }

  void _reminderSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> apply() async {
            await Notifier.saveSettings();
            await _resched();
            setSheet(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Reminders'),
                    subtitle: Text(Notifier.enabled ? '$_scheduled reminders scheduled for the next 5 weeks' : 'Off'),
                    value: Notifier.enabled,
                    onChanged: (v) {
                      Notifier.enabled = v;
                      apply();
                    },
                  ),
                  ListTile(
                    title: const Text('Reminder time'),
                    subtitle: Text(Notifier.timeLabel()),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(hour: Notifier.hour, minute: Notifier.minute),
                      );
                      if (t == null) return;
                      Notifier.hour = t.hour;
                      Notifier.minute = t.minute;
                      apply();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Also remind the day before'),
                    value: Notifier.dayBefore,
                    onChanged: (v) {
                      Notifier.dayBefore = v;
                      apply();
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    FilledButton.tonal(
                      onPressed: () async {
                        final ok = await Notifier.requestPermission();
                        await Notifier.test();
                        if (!ok && mounted) _toast('If nothing appears, allow notifications for Bill Radar in phone Settings');
                      },
                      child: const Text('Send test notification'),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Change the data, save it, and show a message.
  Future<void> _change(String? Function() fn) async {
    final msg = fn();
    setState(() {});
    await Store.save(_s!);
    if (mounted && msg != null) _toast(msg);
    await _resched();
  }

  // ---------------- actions ----------------
  Future<void> _addBill() async {
    final b = await Navigator.push<Bill>(context, MaterialPageRoute(builder: (_) => const BillForm()));
    if (b == null) return;
    _change(() {
      _s!.bills.add(b);
      return '${b.name} added';
    });
  }

  Future<void> _editBill(Bill b) async {
    final nb = await Navigator.push<Bill>(context, MaterialPageRoute(builder: (_) => BillForm(bill: b)));
    if (nb == null) return;
    _change(() {
      final s = _s!;
      final i = s.bills.indexOf(b);
      if (i < 0) return null;
      s.bills[i] = nb;
      if (nb.type == 'emi' && (nb.owed ?? 1) <= 0.005) {
        finish(s, nb);
        return '${nb.name} marked as paid off';
      }
      if (nb.type == 'chit' && (nb.monthsLeft ?? 1) <= 0) {
        finish(s, nb);
        return '${nb.name} marked as complete';
      }
      return '${nb.name} updated';
    });
  }

  Future<void> _deleteBill(Bill b) async {
    if (!await askConfirm(context, 'Delete ${b.name}?', 'Delete')) return;
    _change(() {
      _s!.bills.remove(b);
      return '${b.name} removed';
    });
  }

  Future<void> _editSalary() async {
    final r = await askSalary(context, _s!.salary, _s!.salaryAcc, _s!.cycleDay);
    if (r == null) return;
    _change(() {
      _s!.salary = r2(r.$1);
      _s!.salaryAcc = r.$2;
      _s!.cycleDay = r.$3;
      cycleDay = r.$3;
      _s!.salaryExample = false;
      return 'Salary saved';
    });
  }

  Future<void> _addDebt() async {
    final d = await Navigator.push<Debt>(context, MaterialPageRoute(builder: (_) => const DebtForm()));
    if (d == null) return;
    _change(() {
      _s!.debts.add(d);
      return '${d.name} added';
    });
  }

  Future<void> _editDebt(Debt d) async {
    final nd = await Navigator.push<Debt>(context, MaterialPageRoute(builder: (_) => DebtForm(debt: d)));
    if (nd == null) return;
    _change(() {
      final s = _s!;
      final i = s.debts.indexOf(d);
      if (i < 0) return null;
      if (nd.amt <= 0.005) {
        s.debts.removeAt(i);
        return '${nd.name} settled';
      }
      s.debts[i] = nd;
      return '${nd.name} updated';
    });
  }

  Future<void> _partPaid(Debt d) async {
    final v = await askAmount(context, 'Part paid · ${d.name}', 'Amount paid back (€)');
    if (v == null || v <= 0) return;
    _change(() {
      d.amt = r2(d.amt - v);
      if (d.amt <= 0.005) {
        _s!.debts.remove(d);
        return '${d.name} settled';
      }
      return '${eur(v)} recorded · ${eur(d.amt)} left';
    });
  }

  Future<void> _settle(Debt d) async {
    if (!await askConfirm(context, 'Mark ${d.name} as settled?', 'Settled')) return;
    _change(() {
      _s!.debts.remove(d);
      return '${d.name} settled';
    });
  }

  void _history(Bill b) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final total = b.saveLog.where((e) => e.k == 'save').fold(0.0, (double t, e) => t + e.a);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text('Saving history · ${b.name}', style: Theme.of(ctx).textTheme.titleMedium),
              for (final e in b.saveLog.reversed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.k == 'save' ? monYr(e.d) : fmtDate(e.d)),
                  subtitle: Text(e.k == 'save' ? 'Saved' : 'Paid from ${placeOf(b)}'),
                  trailing: Text(
                    '${e.k == 'save' ? '+' : '−'}${eur(e.a)}',
                    style: _tabular.copyWith(color: e.k == 'save' ? Colors.green.shade600 : Theme.of(ctx).colorScheme.error),
                  ),
                ),
              const Divider(),
              Text('Total saved so far: ${eur(total)}'),
              if (b.saveLog.isNotEmpty && b.saveLog.last.k == 'save')
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _change(() {
                        final e = b.saveLog.removeLast();
                        b.saved = r2(max(0.0, b.saved - e.a));
                        b.saveNext = e.d;
                        return 'Removed saving of ${eur(e.a)}';
                      });
                    },
                    child: const Text('Undo last saving'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- spending + report ----------------
  Future<void> _addSpend() async {
    final x = await Navigator.push<Spend>(context, MaterialPageRoute(builder: (_) => const SpendForm()));
    if (x == null) return;
    _change(() {
      _s!.spends.add(x);
      return '${eur(x.amt)} added to ${spendCats[x.cat] ?? x.cat}';
    });
  }

  Future<void> _editSpend(Spend x) async {
    final nx = await Navigator.push<Spend>(context, MaterialPageRoute(builder: (_) => SpendForm(spend: x)));
    if (nx == null) return;
    _change(() {
      final i = _s!.spends.indexOf(x);
      if (i < 0) return null;
      _s!.spends[i] = nx;
      return 'Spending updated';
    });
  }

  Future<void> _deleteSpend(Spend x) async {
    if (!await askConfirm(context, 'Delete ${eur(x.amt)} (${spendCats[x.cat] ?? x.cat})?', 'Delete')) return;
    _change(() {
      _s!.spends.remove(x);
      return 'Spending deleted';
    });
  }

  Future<void> _exportReport() async {
    try {
      await shareReport(_s!);
    } catch (e) {
      _toast("Couldn't create the report: $e");
    }
  }

  Widget _spendingTab(AppState s) {
    final text = Theme.of(context).textTheme;
    final cur = currentPeriod();
    final list = s.spends.where((x) => inPeriod(x.date, cur)).toList()..sort((a, b) => b.date.compareTo(a.date));
    final total = list.fold<double>(0.0, (t, x) => t + x.amt);
    final byCat = <String, double>{};
    for (final x in list) {
      byCat[x.cat] = (byCat[x.cat] ?? 0) + x.amt;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final earlier = <String, double>{};
    for (final x in s.spends) {
      if (x.date.compareTo(cur.$1) < 0) {
        final k = periodKey(x.date);
        earlier[k] = (earlier[k] ?? 0) + x.amt;
      }
    }
    final earlierKeys = earlier.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SPENT THIS MONTH · ${periodRange(cur).toUpperCase()}', style: text.labelSmall),
                const SizedBox(height: 4),
                Text(eur(total), style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                for (final c in cats) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text(spendCats[c.key] ?? c.key)),
                    Text(eur(c.value), style: _tabular),
                  ]),
                  const SizedBox(height: 4),
                  _bar([
                    (c.value / (total > 0 ? total : 1), Colors.purple.shade400),
                    (1 - c.value / (total > 0 ? total : 1), Theme.of(context).colorScheme.surfaceContainerHighest),
                  ]),
                ],
              ],
            ),
          ),
        ),
        _section('This month', '${list.length} entr${list.length == 1 ? 'y' : 'ies'}', total),
        if (list.isEmpty) _emptyNote('Tap Add spending when you buy something: groceries, eating out, shopping …'),
        for (final x in list)
          Card(
            child: ListTile(
              onTap: () => _editSpend(x),
              leading: Text((spendCats[x.cat] ?? '📦').split(' ').first, style: const TextStyle(fontSize: 22)),
              title: Text(x.note ?? (spendCats[x.cat] ?? x.cat).split(' ').skip(1).join(' ')),
              subtitle: Text('${fmtDate(x.date)} · ${accName[x.acc] ?? x.acc}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(eur(x.amt), style: _tabular.copyWith(fontWeight: FontWeight.w600)),
                IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _deleteSpend(x)),
              ]),
            ),
          ),
        if (earlierKeys.isNotEmpty) ...[
          _section('Earlier months', '', earlier.values.fold<double>(0.0, (t, v) => t + v)),
          Card(
            child: Column(children: [
              for (final k in earlierKeys)
                ListTile(
                  dense: true,
                  title: Text(DateFormat('MMMM yyyy').format(DateTime.parse('$k-01'))),
                  trailing: Text(eur(earlier[k]!), style: _tabular),
                ),
            ]),
          ),
        ],
      ],
    );
  }

  // ---------------- layout ----------------
  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final body = switch (_tab) {
      0 => _paymentsTab(s),
      1 => _spendingTab(s),
      2 => _summaryTab(s),
      _ => _debtsTab(s),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(const ['Bill Radar', 'Spending', 'Summary', 'Debts'][_tab]),
        actions: [
          IconButton(
            tooltip: 'Reminders',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: _reminderSettings,
          ),
        ],
      ),
      body: body,
      floatingActionButton: _tab == 2
          ? null
          : FloatingActionButton.extended(
              onPressed: switch (_tab) {
                0 => _addBill,
                1 => _addSpend,
                _ => _addDebt,
              },
              icon: const Icon(Icons.add),
              label: Text(const ['Add payment', 'Add spending', '', 'Add debt'][_tab]),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Payments'),
          NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), selectedIcon: Icon(Icons.shopping_bag), label: 'Spending'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Summary'),
          NavigationDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: 'Debts'),
        ],
      ),
    );
  }

  Color _kindColor(String kind) => switch (kind) {
        'over' => Theme.of(context).colorScheme.error,
        'soon' => Colors.orange.shade800,
        _ => Theme.of(context).colorScheme.onSurfaceVariant,
      };

  Widget _pill(String kind, String label) {
    final c = _kindColor(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  // ---------------- Payments tab ----------------
  bool _showNext = true;
  bool _showLater = false;

  Widget _section(String title, String sub, double total, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (sub.isNotEmpty) Text(sub, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          Text(eur(total), style: _tabular.copyWith(fontWeight: FontWeight.w700)),
          if (trailing != null) trailing,
        ]),
      );

  Widget _paymentsTab(AppState s) {
    bool keep(Bill b) => _filter == 'all' || b.type == _filter;
    final cur = currentPeriod();
    final nxt = nextPeriod();
    const filters = {'all': 'All', 'sub': 'Subscriptions', 'emi': 'EMIs', 'chit': 'Chitti', 'ins': 'Insurance', 'bill': 'Bills'};

    // coming this month: every unpaid row due up to the end of this month (overdue included)
    final coming = buildEntries(s).where((e) => keep(e.bill) && e.date.compareTo(cur.$2) <= 0).toList();
    final comingTotal = occurrencesIn(s, '0000-01-01', cur.$2).where((o) => keep(o.bill)).fold(0.0, (double t, o) => t + o.amt);

    // paid this month
    final paid = s.paid.where((e) => e.on.compareTo(cur.$1) >= 0 && (_filter == 'all' || e.type == _filter)).toList().reversed.toList();
    final saves = <(Bill, SaveLogEntry)>[
      for (final b in s.bills)
        if (keep(b))
          for (final e in b.saveLog)
            if (e.k == 'save' && (e.on ?? e.d).compareTo(cur.$1) >= 0) (b, e),
    ];
    final paidTotal = paid.fold<double>(0.0, (t, e) => t + e.amt) + saves.fold<double>(0.0, (t, x) => t + x.$2.a);
    final spent = spentIn(s, cur);

    // next month: everything due in it (quarterly ones only when they fall in it)
    final next = occurrencesIn(s, nxt.$1, nxt.$2).where((o) => keep(o.bill)).toList();
    final nextTotal = next.fold(0.0, (double t, o) => t + o.amt);

    // later: items whose next date is after next month (yearly, far quarterly)
    final later = s.bills.where((b) => keep(b) && b.date.compareTo(nxt.$2) > 0).toList()..sort((a, b) => a.date.compareTo(b.date));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        _monthCard(s, cur, paidTotal, comingTotal, spent),
        for (final f in s.freed) _freedCard(f),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final f in filters.entries)
            ChoiceChip(label: Text(f.value), selected: _filter == f.key, onSelected: (_) => setState(() => _filter = f.key)),
        ]),

        _section('⏳ Coming this month', 'Still to pay until ${fmtDate(cur.$2)}', comingTotal),
        if (coming.isEmpty) _emptyNote('Nothing left to pay this month 🎉'),
        for (final e in coming) e.save == null ? _billCard(e.bill) : _saveCard(e.bill, e.save!),

        _section('✅ Paid this month', periodRange(cur), paidTotal),
        if (paid.isEmpty && saves.isEmpty) _emptyNote('Payments you mark as Paid show up here.'),
        for (final e in paid) _paidRow(s, e),
        for (final x in saves) _savedRow(x.$1, x.$2),

        _section('📅 Next month', periodRange(nxt), nextTotal,
            trailing: IconButton(
              icon: Icon(_showNext ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _showNext = !_showNext),
            )),
        if (_showNext) ...[
          if (next.isEmpty) _emptyNote('Nothing due next month.'),
          Card(
            child: Column(children: [for (final o in next) _occRow(o)]),
          ),
        ],

        if (later.isNotEmpty) ...[
          _section('🗓 Later', 'After ${fmtDate(nxt.$2)}', later.fold(0.0, (double t, b) => t + nextAmt(b)),
              trailing: IconButton(
                icon: Icon(_showLater ? Icons.expand_less : Icons.expand_more),
                onPressed: () => setState(() => _showLater = !_showLater),
              )),
          if (_showLater) for (final b in later) _billCard(b),
        ],
      ],
    );
  }

  Widget _emptyNote(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(t, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _paidRow(AppState s, PaidEntry e) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: Icon(Icons.check_circle, color: Colors.green.shade600),
        title: Text(e.name, style: const TextStyle(decoration: TextDecoration.lineThrough)),
        subtitle: Text('Due ${fmtDate(e.due)} · paid ${fmtDate(e.on)} · ${accName[e.acc] ?? e.acc}', style: text.bodySmall),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(eur(e.amt), style: _tabular.copyWith(fontWeight: FontWeight.w600)),
          if (canUndo(s, e))
            TextButton(
              onPressed: () => _change(() => undoPaid(_s!, e)),
              child: const Text('Undo'),
            ),
        ]),
      ),
    );
  }

  Widget _savedRow(Bill b, SaveLogEntry e) => Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          leading: Icon(Icons.savings, color: Colors.green.shade600),
          title: Text('Saved for ${b.name}'),
          subtitle: Text('${fmtDate(e.on ?? e.d)} · ${placeOf(b)}', style: Theme.of(context).textTheme.bodySmall),
          trailing: Text(eur(e.a), style: _tabular.copyWith(fontWeight: FontWeight.w600)),
        ),
      );

  Widget _occRow(Occ o) {
    final b = o.bill;
    final extra = o.saving
        ? 'save to ${placeOf(b)}'
        : '${typeLabel[b.type] ?? b.type}${periodM.containsKey(b.rep) ? ' · ${repLabel[b.rep]}' : ''}';
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 44,
        child: Text(DateFormat('d MMM').format(parseD(o.date)), style: Theme.of(context).textTheme.bodySmall),
      ),
      title: Text(o.saving ? 'Save for ${b.name}' : b.name),
      subtitle: Text('$extra · ${accName[b.acc] ?? b.acc}'),
      trailing: Text(eur(o.amt), style: _tabular.copyWith(fontWeight: FontWeight.w600)),
    );
  }

  Widget _bar(List<(double, Color)> parts) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 8,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final p in parts)
              if (p.$1 > 0) Expanded(flex: max(1, (p.$1 * 1000).round()), child: ColoredBox(color: p.$2)),
          ]),
        ),
      );

  Widget _monthCard(AppState s, (String, String) cur, double paidTotal, double comingTotal, double spent) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final left = s.salary - paidTotal - comingTotal - spent;
    final sal = s.salary > 0 ? s.salary : 1.0;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _editSalary,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text('THIS MONTH · ${periodRange(cur).toUpperCase()}', style: text.labelSmall)),
                const Icon(Icons.edit_outlined, size: 16),
              ]),
              const SizedBox(height: 4),
              Text(
                s.salary > 0 ? eur(left) : 'Tap to add salary',
                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: left < 0 ? cs.error : null),
              ),
              Text('left this month after payments and spending', style: text.bodySmall),
              if (s.salary > 0) ...[
                const SizedBox(height: 12),
                _bar([
                  (paidTotal / sal, Colors.green.shade600),
                  (comingTotal / sal, Colors.orange.shade700),
                  (spent / sal, Colors.purple.shade400),
                  (max(0.0, left) / sal, cs.surfaceContainerHighest),
                ]),
                const SizedBox(height: 8),
                Text('✅ Paid ${eur(paidTotal)}   ⏳ Coming ${eur(comingTotal)}   💸 Spent ${eur(spent)}   of ${eur(s.salary)}', style: text.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _overviewCard(AppState s) {
    final cs = Theme.of(context).colorScheme;
    final overdue = s.bills.where((b) => daysUntil(b.date) < 0).length;
    final emiLeft = s.bills.where(isLoan).fold<double>(0.0, (t, b) => t + b.owed!);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _editSalary,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: _stat(eur(s.salary), 'Salary → ${accName[s.salaryAcc]}', null)),
            Expanded(child: _stat(eur(monthlyFixed(s)), 'Avg fixed / month', null)),
            Expanded(child: _stat(eur(emiLeft), 'EMI balance left', null)),
            if (overdue > 0) Expanded(child: _stat('$overdue', 'Overdue', cs.error)),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String value, String label, Color? color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: _tabular.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );

  Widget _accountsCard(AppState s) {
    final t = accountTotals(s);
    final lines = transferLines(s);
    final small = Theme.of(context).textTheme.labelSmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accounts', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
              children: [
                TableRow(children: [
                  Text('ACCOUNT', style: small),
                  Text('AVG / MONTH', style: small, textAlign: TextAlign.right),
                  Text('DUE THIS MONTH', style: small, textAlign: TextAlign.right),
                ]),
                for (final k in t.keys)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${accName[k]}${k == s.salaryAcc ? ' (salary)' : ''}'),
                    ),
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(eur(t[k]!.avg), style: _tabular, textAlign: TextAlign.right)),
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(eur(t[k]!.month), style: _tabular, textAlign: TextAlign.right)),
                  ]),
              ],
            ),
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l))],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _billCard(Bill b) {
    final (kind, label) = status(daysUntil(b.date));
    final text = Theme.of(context).textTheme;
    final green = TextStyle(color: Colors.green.shade600);
    final details = <Widget>[];
    if (isLoan(b)) {
      final n = paysLeft(b);
      final rem = r2(b.owed! - b.amt * (n - 1));
      final plan = n == 1
          ? eur(b.owed!)
          : (rem < b.amt - 0.005 ? '${n - 1} × ${eur(b.amt)} + ${eur(rem)}' : '$n × ${eur(b.amt)}');
      final end = emiEnd(b);
      if (b.orig != null && b.orig! >= b.owed!) {
        details.add(LinearProgressIndicator(value: (b.orig! - b.owed!) / b.orig!));
      }
      details.add(Text('$n payment${n == 1 ? '' : 's'} left ($plan) · ends ${monYr(end)} · balance ${eur(b.owed!)}'));
      details.add(Text('From ${monYr(nextFirst(end))} you get +${eur(b.amt)}/month free', style: green));
      if (b.endDate != null && ym(b.endDate!) != ym(end)) {
        details.add(Text(
          'Your end date is ${monYr(b.endDate!)}, but this balance is paid off by ${monYr(end)}. Check with your bank.',
          style: TextStyle(color: Colors.orange.shade700),
        ));
      }
    }
    if (isChit(b)) {
      final end = chitEnd(b);
      details.add(Text('${b.monthsLeft} month${b.monthsLeft == 1 ? '' : 's'} left · last payment ${fmtDate(end)} · remaining ${eur(b.amt * b.monthsLeft!)}'));
      details.add(Text('From ${monYr(nextFirst(end))} you get +${eur(b.amt)}/month free', style: green));
    }
    final p = savePlan(b);
    if (p != null) {
      details.add(LinearProgressIndicator(value: b.amt > 0 ? min(1.0, p.saved / b.amt) : 0));
      details.add(Text('Saved ${eur(p.saved)} of ${eur(b.amt)} in ${placeOf(b)}'
          '${p.remain > 0.005 ? ' · next: save ${eur(p.amt)} on ${fmtDate(p.next)}' : ' · fully saved ✓'}'));
    }
    if (b.note != null) {
      details.add(Text(b.note!, style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic)));
    }
    final last = (isLoan(b) && b.owed! <= b.amt + 0.005) || (isChit(b) && b.monthsLeft == 1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(b.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
              Text(eur(nextAmt(b)), style: _tabular.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
            ]),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _pill(kind, label),
                Text(fmtDate(b.date), style: text.bodySmall),
                Text('${typeLabel[b.type] ?? b.type} · ${repLabel[b.rep] ?? b.rep}', style: text.bodySmall),
                _chip(accName[b.acc] ?? b.acc),
              ],
            ),
            for (final w in details) Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: w),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (b.saveLog.isNotEmpty) TextButton(onPressed: () => _history(b), child: const Text('History')),
                TextButton(onPressed: () => _editBill(b), child: const Text('Edit')),
                FilledButton.tonal(
                  onPressed: () => _change(() => payAndLog(_s!, b)),
                  child: Text(b.rep == 'none' || last ? 'Paid' : 'Paid → next'),
                ),
                IconButton(tooltip: 'Delete', onPressed: () => _deleteBill(b), icon: const Icon(Icons.delete_outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveCard(Bill b, SavePlan p) {
    final (kind, label) = status(daysUntil(p.next));
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.savings_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Save for ${b.name}', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
              Text(eur(p.amt), style: _tabular.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _pill(kind, label),
              Text(fmtDate(p.next), style: text.bodySmall),
              Text('move to ${placeOf(b)}', style: text.bodySmall),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Saved ${eur(p.saved)} of ${eur(b.amt)} · ${p.n} saving${p.n == 1 ? '' : 's'} left before ${fmtDate(b.date)}'),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (p.n > 1) TextButton(onPressed: () => _change(() => skipSaving(b, p)), child: const Text('Skip this month')),
              FilledButton.tonal(onPressed: () => _change(() => markSaved(b, p)), child: const Text('Saved ✓')),
              const SizedBox(width: 8),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _freedCard(Freed f) => Card(
        color: Colors.green.withValues(alpha: 0.15),
        child: ListTile(
          leading: const Text('🎉', style: TextStyle(fontSize: 22)),
          title: Text('${f.name} is finished'),
          subtitle: Text('From ${monYr(f.from)} you have ${eur(f.amt)} more every month. Move it to savings before it gets spent.'),
          trailing: TextButton(
            onPressed: () => _change(() {
              _s!.freed.remove(f);
              return null;
            }),
            child: const Text('Got it'),
          ),
        ),
      );

  // ---------------- Summary tab ----------------
  Widget _summaryTab(AppState s) {
    final rows = summaryRows(s);
    final sal = s.salary;
    final used = [for (final c in sumCols) if (rows.any((r) => (r.by[c.$1] ?? 0) > 0.005)) c];
    final totOut = rows.fold(0.0, (double t, r) => t + r.out);
    final totLeft = sal * 12 - totOut;
    final cs = Theme.of(context).colorScheme;
    final bold = _tabular.copyWith(fontWeight: FontWeight.w700);
    String monthLabel(String m) => DateFormat('MMM yyyy').format(DateTime.parse('$m-01'));
    String money(double v) => v > 0.005 ? eur(v) : '–';

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: FilledButton.icon(
            onPressed: _exportReport,
            icon: const Icon(Icons.download),
            label: const Text('Download Excel report'),
          ),
        ),
        _overviewCard(s),
        _accountsCard(s),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 72,
              columns: [
                const DataColumn(label: Text('Month')),
                if (sal > 0) const DataColumn(label: Text('Salary'), numeric: true),
                for (final c in used) DataColumn(label: Text(c.$2), numeric: true),
                DataColumn(label: Text(sal > 0 ? 'Left' : 'Total out'), numeric: true),
                const DataColumn(label: Text('Changes')),
              ],
              rows: [
                for (var i = 0; i < rows.length; i++)
                  DataRow(
                    color: i == 0 ? WidgetStatePropertyAll(cs.surfaceContainerHigh) : null,
                    cells: [
                      DataCell(Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i == 0 ? '${monthLabel(rows[i].month)} · now' : monthLabel(rows[i].month)),
                          Text(rows[i].range, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      )),
                      if (sal > 0) DataCell(Text(eur(sal), style: _tabular)),
                      for (final c in used) DataCell(Text(money(rows[i].by[c.$1] ?? 0), style: _tabular)),
                      DataCell(Text(
                        eur(sal > 0 ? sal - rows[i].out : rows[i].out),
                        style: bold.copyWith(color: sal > 0 && sal - rows[i].out < 0 ? cs.error : null),
                      )),
                      DataCell(SizedBox(
                        width: 190,
                        child: Text(rows[i].ends.join('\n'), style: TextStyle(color: Colors.green.shade600, fontSize: 12)),
                      )),
                    ],
                  ),
                DataRow(cells: [
                  DataCell(Text('12 months', style: bold)),
                  if (sal > 0) DataCell(Text(eur(sal * 12), style: bold)),
                  for (final c in used) DataCell(Text(eur(rows.fold(0.0, (double t, r) => t + (r.by[c.$1] ?? 0))), style: bold)),
                  DataCell(Text(eur(sal > 0 ? totLeft : totOut), style: bold.copyWith(color: sal > 0 && totLeft < 0 ? cs.error : null))),
                  const DataCell(SizedBox.shrink()),
                ]),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${sal > 0 ? 'If you keep these payments, you have about ${eur(totLeft)} left over the next 12 months. ' : 'Add your salary to see what is left each month. '}'
            'Each month runs from day ${s.cycleDay} to the day before. Insurance and other set-aside items count the monthly saving, not the big payment. Debts are not included. Swipe the table sideways to see all columns.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  // ---------------- Debts tab ----------------
  Widget _debtsTab(AppState s) {
    final cs = Theme.of(context).colorScheme;
    final owe = s.debts.where((d) => d.dir == 'owe').fold(0.0, (double t, d) => t + d.amt);
    final owed = s.debts.where((d) => d.dir == 'owed').fold(0.0, (double t, d) => t + d.amt);
    final list = [...s.debts]..sort((a, b) => (a.due ?? '9999').compareTo(b.due ?? '9999'));
    Widget total(String label, double v, Color c) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _stat(eur(v), label, c),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Row(children: [
          Expanded(child: total('I OWE', owe, cs.error)),
          Expanded(child: total('OWED TO ME', owed, Colors.green.shade600)),
        ]),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('No debts. Tap Add debt for money you borrowed or lent.', textAlign: TextAlign.center),
          ),
        for (final d in list) _debtCard(d),
      ],
    );
  }

  Widget _debtCard(Debt d) {
    final text = Theme.of(context).textTheme;
    final owe = d.dir == 'owe';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(d.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
              Text(eur(d.amt),
                  style: _tabular.copyWith(
                      fontSize: 16, fontWeight: FontWeight.w600, color: owe ? Theme.of(context).colorScheme.error : Colors.green.shade600)),
              const SizedBox(width: 8),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(owe ? 'I owe' : 'Owes me', style: text.bodySmall),
              if (d.due != null) ...[
                _pill(status(daysUntil(d.due!)).$1, status(daysUntil(d.due!)).$2),
                Text('by ${fmtDate(d.due!)}', style: text.bodySmall),
              ],
            ]),
            if (d.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(d.note!, style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => _editDebt(d), child: const Text('Edit')),
              TextButton(onPressed: () => _partPaid(d), child: const Text('Part paid')),
              FilledButton.tonal(onPressed: () => _settle(d), child: const Text('Settled')),
              const SizedBox(width: 8),
            ]),
          ],
        ),
      ),
    );
  }
}
