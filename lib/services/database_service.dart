import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../models/telemetry.dart';

class DatabaseService {
  DatabaseService._();
  static final instance = DatabaseService._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('telemetry.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE telemetry_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        batteryVoltage REAL NOT NULL,
        loadPercentage REAL NOT NULL,
        pvPower REAL NOT NULL,
        pvEnergy REAL NOT NULL
      )
    ''');
  }

  Future<void> insertTelemetry(Telemetry data) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.insert(
      'telemetry_history',
      {
        'timestamp': now,
        'batteryVoltage': data.batteryVoltage,
        'loadPercentage': data.loadPercentage,
        'pvPower': data.pvPower,
        'pvEnergy': data.pvEnergy,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Auto-cleanup: delete records older than 30 days
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    await db.delete(
      'telemetry_history',
      where: 'timestamp < ?',
      whereArgs: [thirtyDaysAgo],
    );
  }

  /// Retrieves today's snapshot (Peak Load, Peak Solar, Min Battery, Total Energy)
  Future<Map<String, dynamic>> getTodayStats() async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    
    final result = await db.rawQuery('''
      SELECT 
        MAX(loadPercentage) as maxLoad,
        MAX(pvPower) as maxSolar,
        MIN(NULLIF(batteryVoltage, 0)) as minBattery,
        MAX(pvEnergy) - MIN(NULLIF(pvEnergy, 0)) as totalEnergy
      FROM telemetry_history
      WHERE timestamp >= ?
    ''', [startOfDay]);

    if (result.isNotEmpty && result.first['maxLoad'] != null) {
      return result.first;
    }
    return {'maxLoad': 0.0, 'maxSolar': 0.0, 'minBattery': 0.0, 'totalEnergy': 0.0};
  }
  
  /// Retrieves 30-day All-Time Highs
  Future<Map<String, dynamic>> getMonthStats() async {
    final db = await database;
    
    // We get absolute maxes
    final maxes = await db.rawQuery('''
      SELECT 
        MAX(loadPercentage) as monthMaxLoad,
        MAX(pvPower) as monthMaxSolar
      FROM telemetry_history
    ''');

    // To find the best solar day (highest daily energy), we group by day
    // SQLite doesn't have a built-in time zone aware date truncator easily,
    // so we approximate by grouping by (timestamp / 86400000)
    // which is days since epoch (UTC), close enough for a general statistic.
    final bestDay = await db.rawQuery('''
      SELECT 
        MAX(pvEnergy) - MIN(NULLIF(pvEnergy, 0)) as dailyEnergy
      FROM telemetry_history
      GROUP BY (timestamp / 86400000)
      ORDER BY dailyEnergy DESC
      LIMIT 1
    ''');

    final result = <String, dynamic>{
      'monthMaxLoad': maxes.isNotEmpty ? (maxes.first['monthMaxLoad'] ?? 0.0) : 0.0,
      'monthMaxSolar': maxes.isNotEmpty ? (maxes.first['monthMaxSolar'] ?? 0.0) : 0.0,
      'bestDailyEnergy': bestDay.isNotEmpty ? (bestDay.first['dailyEnergy'] ?? 0.0) : 0.0,
    };
    
    return result;
  }

  /// Retrieves today's telemetry history for charts
  Future<List<Map<String, dynamic>>> getTelemetryHistoryForToday() async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    
    final result = await db.rawQuery('''
      SELECT 
        timestamp,
        batteryVoltage,
        loadPercentage,
        pvPower,
        pvEnergy
      FROM telemetry_history
      WHERE timestamp >= ?
      ORDER BY timestamp ASC
    ''', [startOfDay]);

    return result;
  }
}
