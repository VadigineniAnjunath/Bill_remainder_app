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

/// Everything the app stores.
class AppState {
  double salary;
  String salaryAcc;
  bool salaryExample;
  List<Bill> bills;
  List<Debt> debts;
  List<Freed> freed;

  AppState({this.salary = 0, this.salaryAcc = 'cb', this.salaryExample = false, List<Bill>? bills, List<Debt>? debts, List<Freed>? freed})
      : bills = bills ?? [],
        debts = debts ?? [],
        freed = freed ?? [];

  factory AppState.empty() => AppState();

  static List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      ((v as List?) ?? []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();

  factory AppState.fromJson(Map<String, dynamic> j) => AppState(
        salary: _d(j['salary']),
        salaryAcc: (j['salaryAcc'] ?? 'cb').toString(),
        salaryExample: j['salaryExample'] == true,
        bills: _list(j['bills'], Bill.fromJson),
        debts: _list(j['debts'], Debt.fromJson),
        freed: _list(j['freed'], Freed.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'salary': salary,
        'salaryAcc': salaryAcc,
        'salaryExample': salaryExample,
        'bills': bills.map((b) => b.toJson()).toList(),
        'debts': debts.map((d) => d.toJson()).toList(),
        'freed': freed.map((f) => f.toJson()).toList(),
      };
}
