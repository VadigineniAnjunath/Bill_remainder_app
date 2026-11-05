// Saves the whole app state on the phone, and imports a backup file.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class Store {
  static const _key = 'billradar.state.v1';

  /// The saved state, or null on the very first start.
  static Future<AppState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return AppState.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  static Future<void> save(AppState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(s.toJson()));
  }

  /// Reads a Bill Radar backup: {"app":"bill-radar","data":{...}} or the bare data.
  static AppState parseBackup(String text) {
    final j = Map<String, dynamic>.from(jsonDecode(text) as Map);
    final data = j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : j;
    if (data['bills'] is! List) throw const FormatException('Not a Bill Radar backup');
    return AppState.fromJson(data);
  }

  /// The backup bundled with the app at assets/import/backup.json, if present.
  /// Used once, on the first start, so you don't have to type anything again.
  static Future<AppState?> bundledBackup() async {
    try {
      return parseBackup(await rootBundle.loadString('assets/import/backup.json'));
    } catch (_) {
      return null;
    }
  }
}
