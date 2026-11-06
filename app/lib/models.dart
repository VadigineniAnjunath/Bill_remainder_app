// Data model for Bill Radar.
// Field names match the web version's backup JSON exactly, so a backup
// imports without any conversion.

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
double? _dn(dynamic v) => v == null ? null : (v as num).toDouble();
int? _in(dynamic v) => v == null ? null : (v as num).toInt();
String? _sn(dynamic v) => v?.toString();

Map<String, dynamic> _clean(Map<String, dynamic> m) =>
    m..removeWhere((k, v) => v == null);

/// One entry in a saving history (monthly saving, or paying from the Space).
class SaveLogEntry {
  String k; // 'save' or 'paid'
  String d; // date it belongs to (yyyy-mm-dd)
  double a; // amount
  double? from; // for 'paid': how much was saved at that time
  String? on; // day the button was tapped

  SaveLogEntry({required this.k, required this.d, required this.a, this.from, this.on});

  factory SaveLogEntry.fromJson(Map<String, dynamic> j) => SaveLogEntry(
        k: j['k'].toString(),
        d: j['d'].toString(),
        a: _d(j['a']),
        from: _dn(j['from']),
        on: _sn(j['on']),
      );

  Map<String, dynamic> toJson() => _clean({'k': k, 'd': d, 'a': a, 'from': from, 'on': on});
}

/// A recurring or one-off payment: subscription, EMI, chitti, insurance or bill.
class Bill {
  String id;
  String name;
  String type; // sub | emi | chit | ins | bill
  double amt; // regular payment amount
  String date; // next due date, yyyy-mm-dd
  String rep; // none | weekly | monthly | quarterly | yearly
  String acc; // cb | n26 | cash
  double? owed; // EMI: amount still owed
  double? orig; // EMI: original loan (optional)
  String? endDate; // EMI: end date from the bank (optional)
  int? monthsLeft; // chitti
  String? note;
  String? saveTo; // quarterly/yearly: n26space | cb | n26 | cash | '' (don't set aside)
  String? space; // N26 Space name
  String? saveNext; // next monthly saving date
  double saved; // saved so far for the next payment
  List<SaveLogEntry> saveLog;
  bool example;

  Bill({
    required this.id,
    required this.name,
    required this.type,
    required this.amt,
    required this.date,
    this.rep = 'monthly',
    this.acc = 'cb',
    this.owed,
    this.orig,
    this.endDate,
    this.monthsLeft,
    this.note,
    this.saveTo,
    this.space,
    this.saveNext,
    this.saved = 0,
    List<SaveLogEntry>? saveLog,
    this.example = false,
  }) : saveLog = saveLog ?? [];

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        id: (j['id'] ?? DateTime.now().microsecondsSinceEpoch).toString(),
        name: (j['name'] ?? '').toString(),
        type: (j['type'] ?? 'bill').toString(),
        amt: _d(j['amt']),
        date: j['date'].toString(),
        rep: (j['rep'] ?? 'monthly').toString(),
        acc: (j['acc'] ?? 'cb').toString(),
        owed: _dn(j['owed']),
        orig: _dn(j['orig']),
        endDate: _sn(j['endDate']),
        monthsLeft: _in(j['monthsLeft']),
        note: _sn(j['note']),
        saveTo: _sn(j['saveTo']),
        space: _sn(j['space']),
        saveNext: _sn(j['saveNext']),
        saved: _d(j['saved']),
        saveLog: ((j['saveLog'] as List?) ?? [])
            .map((e) => SaveLogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        example: j['example'] == true,
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'name': name,
        'type': type,
        'amt': amt,
        'date': date,
        'rep': rep,
        'acc': acc,
        'owed': owed,
        'orig': orig,
        'endDate': endDate,
        'monthsLeft': monthsLeft,
        'note': note,
        'saveTo': saveTo,
        'space': space,
        'saveNext': saveNext,
        'saved': saved == 0 ? null : saved,
        'saveLog': saveLog.isEmpty ? null : saveLog.map((e) => e.toJson()).toList(),
        'example': example ? true : null,
      });
}

/// Money borrowed or lent.
class Debt {
  String id;
  String name;
  String dir; // owe | owed
  double amt;
  String? due;
  String? note;
  bool example;

  Debt({required this.id, required this.name, required this.dir, required this.amt, this.due, this.note, this.example = false});

  factory Debt.fromJson(Map<String, dynamic> j) => Debt(
        id: (j['id'] ?? DateTime.now().microsecondsSinceEpoch).toString(),
        name: (j['name'] ?? '').toString(),
        dir: (j['dir'] ?? 'owe').toString(),
        amt: _d(j['amt']),
        due: _sn(j['due']),
        note: _sn(j['note']),
        example: j['example'] == true,
      );

  Map<String, dynamic> toJson() => _clean({
        'id': id,
        'name': name,
        'dir': dir,
        'amt': amt,
        'due': due,
        'note': note,
        'example': example ? true : null,
      });
}

/// An EMI or chitti that finished: its monthly amount is now free.
class Freed {
  String id;
  String name;
  double amt;
  String type;
  String from; // first month the money is free

  Freed({required this.id, required this.name, required this.amt, required this.type, required this.from});

  factory Freed.fromJson(Map<String, dynamic> j) => Freed(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        amt: _d(j['amt']),
        type: (j['type'] ?? 'emi').toString(),
        from: j['from'].toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'amt': amt, 'type': type, 'from': from};
}

/// One "Paid" tap: what was paid, when, and the payment as it was before
/// (so the tap can be undone exactly).
class PaidEntry {
  String id;
  String billId;
  String name;
  String type;
  String acc;
  double amt;
  String due; // the due date that was paid
  String on; // the day "Paid" was tapped
  Map<String, dynamic> before; // the payment before it was marked paid

  PaidEntry({
    required this.id,
    required this.billId,
    required this.name,
    required this.type,
    required this.acc,
    required this.amt,
    required this.due,
    required this.on,
    required this.before,
  });

  factory PaidEntry.fromJson(Map<String, dynamic> j) => PaidEntry(
        id: (j['id'] ?? '').toString(),
        billId: (j['billId'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        type: (j['type'] ?? 'bill').toString(),
        acc: (j['acc'] ?? 'cb').toString(),
        amt: _d(j['amt']),
        due: j['due'].toString(),
        on: j['on'].toString(),
        before: Map<String, dynamic>.from((j['before'] as Map?) ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'billId': billId,
        'name': name,
        'type': type,
        'acc': acc,
        'amt': amt,
        'due': due,
        'on': on,
        'before': before,
      };
}

/// Day-to-day spending (groceries, eating out, shopping …).
class Spend {
  String id;
  String date;
  double amt;
  String cat;
  String acc;
  String? note;

  Spend({required this.id, required this.date, required this.amt, required this.cat, this.acc = 'cb', this.note});

  factory Spend.fromJson(Map<String, dynamic> j) => Spend(
        id: (j['id'] ?? '').toString(),
        date: j['date'].toString(),
        amt: _d(j['amt']),
        cat: (j['cat'] ?? 'other').toString(),
        acc: (j['acc'] ?? 'cb').toString(),
        note: _sn(j['note']),
      );

  Map<String, dynamic> toJson() => _clean({'id': id, 'date': date, 'amt': amt, 'cat': cat, 'acc': acc, 'note': note});
}

/// Everything the app stores.
class AppState {
  double salary;
  String salaryAcc;
  bool salaryExample;
  int cycleDay; // the day your month starts (rent + salary), e.g. 30
  List<Bill> bills;
  List<Debt> debts;
  List<Freed> freed;
  List<PaidEntry> paid;
  List<Spend> spends;

  AppState({
    this.salary = 0,
    this.salaryAcc = 'cb',
    this.salaryExample = false,
    this.cycleDay = 30,
    List<Bill>? bills,
    List<Debt>? debts,
    List<Freed>? freed,
    List<PaidEntry>? paid,
    List<Spend>? spends,
  })  : bills = bills ?? [],
        debts = debts ?? [],
        freed = freed ?? [],
        paid = paid ?? [],
        spends = spends ?? [];

  factory AppState.empty() => AppState();

  static List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      ((v as List?) ?? []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();

  factory AppState.fromJson(Map<String, dynamic> j) => AppState(
        salary: _d(j['salary']),
        salaryAcc: (j['salaryAcc'] ?? 'cb').toString(),
        salaryExample: j['salaryExample'] == true,
        cycleDay: _in(j['cycleDay']) ?? 30,
        bills: _list(j['bills'], Bill.fromJson),
        debts: _list(j['debts'], Debt.fromJson),
        freed: _list(j['freed'], Freed.fromJson),
        paid: _list(j['paid'], PaidEntry.fromJson),
        spends: _list(j['spends'], Spend.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'salary': salary,
        'salaryAcc': salaryAcc,
        'salaryExample': salaryExample,
        'cycleDay': cycleDay,
        'bills': bills.map((b) => b.toJson()).toList(),
        'debts': debts.map((d) => d.toJson()).toList(),
        'freed': freed.map((f) => f.toJson()).toList(),
        'paid': paid.map((p) => p.toJson()).toList(),
        'spends': spends.map((x) => x.toJson()).toList(),
      };
}
