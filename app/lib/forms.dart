// Add / edit screens and small dialogs.

import 'package:flutter/material.dart';

import 'logic.dart';
import 'models.dart';

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String numText(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

const _border = OutlineInputBorder();

Widget textField(TextEditingController c, String label, {bool number = false, String? hint}) => TextField(
      controller: c,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      textCapitalization: number ? TextCapitalization.none : TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, hintText: hint, border: _border),
    );

Widget dropField(String label, String value, Map<String, String> items, ValueChanged<String> onChanged) =>
    DropdownButtonFormField<String>(
      key: ValueKey('$label|$value'),
      initialValue: items.containsKey(value) ? value : items.keys.first,
      decoration: InputDecoration(labelText: label, border: _border),
      items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );

Widget dateField(BuildContext context, String label, String? value, ValueChanged<String?> onChanged,
    {bool clearable = false}) {
  return InkWell(
    onTap: () async {
      final init = value != null ? parseD(value) : todayD();
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(init.year, init.month, init.day),
        firstDate: DateTime(2020),
        lastDate: DateTime(2045),
      );
      if (picked != null) onChanged(iso(DateTime.utc(picked.year, picked.month, picked.day)));
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: _border,
        suffixIcon: clearable && value != null
            ? IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
            : const Icon(Icons.calendar_today_outlined),
      ),
      child: Text(value == null ? 'Not set' : fmtDate(value)),
    ),
  );
}

void showError(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

// ---------------------------------------------------------------------------
// Add / edit a payment
// ---------------------------------------------------------------------------
class BillForm extends StatefulWidget {
  const BillForm({super.key, this.bill});
  final Bill? bill;

  @override
  State<BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<BillForm> {
  final _name = TextEditingController();
  final _amt = TextEditingController();
  final _owed = TextEditingController();
  final _orig = TextEditingController();
  final _months = TextEditingController();
  final _space = TextEditingController();
  final _note = TextEditingController();
  String _type = 'sub';
  String _rep = 'monthly';
  String _acc = 'n26';
  String _saveTo = 'n26space';
  String _date = todayS();
  String? _end;

  bool get _isEmi => _type == 'emi';
  bool get _isChit => _type == 'chit';
  bool get _canSave => periodM.containsKey(_rep) && !_isEmi && !_isChit;

  @override
  void initState() {
    super.initState();
    final b = widget.bill;
    if (b != null) {
      _name.text = b.name;
      _amt.text = numText(b.amt);
      _type = b.type;
      _rep = b.rep;
      _acc = b.acc;
      _date = b.date;
      _owed.text = numText(b.owed);
      _orig.text = numText(b.orig);
      _end = b.endDate;
      _months.text = b.monthsLeft?.toString() ?? '';
      _saveTo = b.saveTo ?? 'n26space';
      _space.text = b.space ?? '';
      _note.text = b.note ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _amt, _owed, _orig, _months, _space, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setType(String t) {
    setState(() {
      _type = t;
      if (widget.bill == null && t == 'sub') _acc = 'n26';
      if (t == 'ins') {
        _rep = 'quarterly';
        _saveTo = 'n26space';
        if (_space.text.isEmpty) _space.text = 'Insurance';
      }
      if ((t == 'emi' || t == 'chit') && _rep == 'none') _rep = 'monthly';
    });
  }

  void _save() {
    final name = _name.text.trim();
    final amt = parseNum(_amt.text);
    if (name.isEmpty) return showError(context, 'Enter a name');
    if (amt == null || amt <= 0) return showError(context, 'Enter an amount above 0');
    final old = widget.bill;
    final b = Bill(
      id: old?.id ?? '${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: _type,
      amt: r2(amt),
      date: _date,
      rep: _rep,
      acc: _acc,
      saved: old?.saved ?? 0,
      saveLog: old == null ? null : List.of(old.saveLog),
      saveNext: old?.saveNext,
      example: old?.example ?? false,
    );
    final note = _note.text.trim();
    if (note.isNotEmpty) b.note = note;
    if (_isEmi) {
      final owed = parseNum(_owed.text);
      if (owed == null && _end == null) return showError(context, 'Enter the amount still owed or the end date');
      if (_end != null && _end!.compareTo(_date) < 0) return showError(context, 'End date is before the next due date');
      b.owed = owed != null ? r2(owed) : r2(amt * countUntil(_date, _rep, _end!));
      b.endDate = _end;
      final o = parseNum(_orig.text);
      if (o != null && o > 0) b.orig = r2(o);
    }
    if (_isChit) {
      final m = int.tryParse(_months.text.trim());
      if (m == null || m < 0 || (old == null && m < 1)) return showError(context, 'Enter how many months are left');
      b.monthsLeft = m;
    }
    if (_canSave) {
      b.saveTo = _saveTo;
      final sp = _space.text.trim();
      if (_saveTo == 'n26space' && sp.isNotEmpty) b.space = sp;
    }
    Navigator.pop(context, b);
  }

  @override
  Widget build(BuildContext context) {
    final reps = (_isEmi || _isChit) ? (Map.of(repLabel)..remove('none')) : repLabel;
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bill == null ? 'Add payment' : 'Edit payment'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          textField(_name, 'Name', hint: 'e.g. Laptop, Netflix, Home Rent'),
          gap,
          dropField('Type', _type, const {'sub': 'Subscription', 'emi': 'EMI / Loan', 'chit': 'Chitti', 'ins': 'Insurance', 'bill': 'Bill / Rent'}, _setType),
          gap,
          textField(_amt, _isEmi ? 'Monthly payment (€)' : 'Amount (€)', number: true),
          gap,
          dateField(context, 'Next due date', _date, (v) => setState(() => _date = v ?? _date)),
          gap,
          dropField('Pays from', _acc, accName, (v) => setState(() => _acc = v)),
          gap,
          dropField('Repeats', _rep, reps, (v) => setState(() => _rep = v)),
          if (_isEmi) ...[
            gap,
            textField(_owed, 'Amount still owed (€)', number: true, hint: 'e.g. 340'),
            gap,
            dateField(context, 'End date (optional)', _end, (v) => setState(() => _end = v), clearable: true),
            gap,
            textField(_orig, 'Original loan (€, optional)', number: true),
          ],
          if (_isChit) ...[
            gap,
            textField(_months, 'Months left', number: true, hint: 'e.g. 11'),
          ],
          if (_canSave) ...[
            gap,
            dropField('Set aside in', _saveTo,
                const {'n26space': 'N26 Space', 'cb': 'Commerzbank', 'n26': 'N26 main', 'cash': 'Cash', '': "Don't set aside"},
                (v) => setState(() => _saveTo = v)),
            if (_saveTo == 'n26space') ...[gap, textField(_space, 'Space name', hint: 'e.g. Insurance_DAD')],
          ],
          gap,
          textField(_note, 'Description (optional)'),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: Text(widget.bill == null ? 'Add payment' : 'Save changes')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit a debt
// ---------------------------------------------------------------------------
class DebtForm extends StatefulWidget {
  const DebtForm({super.key, this.debt});
  final Debt? debt;

  @override
  State<DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends State<DebtForm> {
  final _name = TextEditingController();
  final _amt = TextEditingController();
  final _note = TextEditingController();
  String _dir = 'owe';
  String? _due;

  @override
  void initState() {
    super.initState();
    final d = widget.debt;
    if (d != null) {
      _name.text = d.name;
      _amt.text = numText(d.amt);
      _note.text = d.note ?? '';
      _dir = d.dir;
      _due = d.due;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amt.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final amt = parseNum(_amt.text);
    if (name.isEmpty) return showError(context, 'Enter a person or reason');
    if (amt == null || amt < 0 || (widget.debt == null && amt == 0)) return showError(context, 'Enter the amount');
    final old = widget.debt;
    final d = Debt(
      id: old?.id ?? '${DateTime.now().microsecondsSinceEpoch}d',
      name: name,
      dir: _dir,
      amt: r2(amt),
      due: _due,
      example: old?.example ?? false,
    );
    final note = _note.text.trim();
    if (note.isNotEmpty) d.note = note;
    Navigator.pop(context, d);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.debt == null ? 'Add debt' : 'Edit debt'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          textField(_name, 'Person / what for', hint: 'e.g. Mrunal'),
          gap,
          dropField('Direction', _dir, const {'owe': 'I owe them', 'owed': 'They owe me'}, (v) => setState(() => _dir = v)),
          gap,
          textField(_amt, widget.debt == null ? 'Amount (€)' : 'Amount left (€)', number: true),
          gap,
          dateField(context, 'Pay back by (optional)', _due, (v) => setState(() => _due = v), clearable: true),
          gap,
          textField(_note, 'Description (optional)'),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: Text(widget.debt == null ? 'Add debt' : 'Save changes')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------
Future<double?> askAmount(BuildContext context, String title, String label) {
  final c = TextEditingController();
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(c.text)), child: const Text('Save')),
      ],
    ),
  );
}

Future<(double, String, int)?> askSalary(BuildContext context, double salary, String acc, int day) {
  final c = TextEditingController(text: salary > 0 ? numText(salary) : '');
  final dc = TextEditingController(text: '$day');
  var a = acc;
  return showDialog<(double, String, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Salary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monthly net salary (€)'),
            ),
            const SizedBox(height: 12),
            dropField('Salary goes to', a, const {'cb': 'Commerzbank', 'n26': 'N26'}, (v) => setD(() => a = v)),
            const SizedBox(height: 12),
            TextField(
              controller: dc,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'My month starts on day',
                helperText: 'Rent / salary day, e.g. 30 → month runs 30th to 29th',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = parseNum(c.text);
              final d = int.tryParse(dc.text.trim());
              if (v == null || v < 0 || d == null || d < 1 || d > 31) return;
              Navigator.pop(ctx, (v, a, d));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> askConfirm(BuildContext context, String text, String action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

// ---------------------------------------------------------------------------
// Add / edit spending
// ---------------------------------------------------------------------------
class SpendForm extends StatefulWidget {
  const SpendForm({super.key, this.spend});
  final Spend? spend;

  @override
  State<SpendForm> createState() => _SpendFormState();
}

class _SpendFormState extends State<SpendForm> {
  final _amt = TextEditingController();
  final _note = TextEditingController();
  String _cat = 'food';
  String _acc = 'cb';
  String _date = todayS();

  @override
  void initState() {
    super.initState();
    final x = widget.spend;
    if (x != null) {
      _amt.text = numText(x.amt);
      _note.text = x.note ?? '';
      _cat = x.cat;
      _acc = x.acc;
      _date = x.date;
    }
  }

  @override
  void dispose() {
    _amt.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final amt = parseNum(_amt.text);
    if (amt == null || amt <= 0) return showError(context, 'Enter an amount above 0');
    final x = Spend(
      id: widget.spend?.id ?? '${DateTime.now().microsecondsSinceEpoch}s',
      date: _date,
      amt: r2(amt),
      cat: _cat,
      acc: _acc,
    );
    final note = _note.text.trim();
    if (note.isNotEmpty) x.note = note;
    Navigator.pop(context, x);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.spend == null ? 'Add spending' : 'Edit spending'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amt,
            autofocus: widget.spend == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: const InputDecoration(labelText: 'Amount (€)', border: OutlineInputBorder()),
          ),
          gap,
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in spendCats.entries)
              ChoiceChip(label: Text(c.value), selected: _cat == c.key, onSelected: (_) => setState(() => _cat = c.key)),
          ]),
          gap,
          dateField(context, 'Date', _date, (v) => setState(() => _date = v ?? _date)),
          gap,
          dropField('Paid from', _acc, accName, (v) => setState(() => _acc = v)),
          gap,
          textField(_note, 'Note (optional)', hint: 'e.g. Lidl, dinner with friends'),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: Text(widget.spend == null ? 'Add spending' : 'Save changes')),
        ],
      ),
    );
  }
}
