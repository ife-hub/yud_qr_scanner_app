import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/app_user.dart';
import '../models/staff.dart';
import '../models/scan_record.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'qr_scanner_app.db');

    final db = await openDatabase(
      path,
      version: 8, // Incremented for basket_color + action columns
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Schema has changed - drop + recreate for simplicity.
        // Uninstall/reinstall the app on your test device if you hit issues.
        await db.execute('DROP TABLE IF EXISTS members');
        await db.execute('DROP TABLE IF EXISTS admins');
        await db.execute('DROP TABLE IF EXISTS scan_records');
        await _createTables(db);
      },
    );

    await _seedIfEmpty(db);
    return db;
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        "group" TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE admins (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        "group" TEXT NOT NULL,
        specialRole TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE scan_records (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        scanned_id TEXT NOT NULL,
        purpose TEXT NOT NULL,
        radio_qty INTEGER,
        earpiece_qty INTEGER,
        bowl_qty INTEGER,
        basket_qty INTEGER,
        basket_color TEXT,
        action TEXT,
        timestamp TEXT NOT NULL,
        day INTEGER NOT NULL,
        session TEXT NOT NULL,
        device_id TEXT NOT NULL,
        operator TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _seedIfEmpty(Database db) async {
    final memberCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM members'),
        ) ??
        0;

    if (memberCount == 0) {
      final json = await rootBundle.loadString('assets/members.json');
      final List<dynamic> members = jsonDecode(json);
      final batch = db.batch();
      for (final m in members) {
        batch.insert('members', {
          'id': m['id'],
          'name': m['name'],
          'role': m['role'],
          'group': m['group'],
        });
      }
      await batch.commit(noResult: true);
    }

    final adminCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM admins'),
        ) ??
        0;

    if (adminCount == 0) {
      final json = await rootBundle.loadString('assets/admins.json');
      final List<dynamic> admins = jsonDecode(json);
      final batch = db.batch();
      for (final a in admins) {
        batch.insert('admins', {
          'id': a['id'],
          'username': a['username'],
          'password': a['password'],
          'name': a['name'],
          'role': a['role'],
          'group': a['group'],
          'specialRole': a['specialRole'] ?? '',
        });
      }
      await batch.commit(noResult: true);
    }
  }

  // ---------- Admin / login ----------

  Future<Staff?> findStaffByCredentials(String username, String password) async {
    final db = await database;
    final rows = await db.query(
      'admins',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );
    if (rows.isEmpty) return null;
    return Staff.fromMap(rows.first);
  }

  Future<Staff?> findStaffByUsername(String username) async {
    final db = await database;
    final rows = await db.query('admins', where: 'username = ?', whereArgs: [username]);
    if (rows.isEmpty) return null;
    return Staff.fromMap(rows.first);
  }

  // ---------- Member lookup ----------

  Future<AppUser?> findMemberById(String id) async {
    final db = await database;
    final rows = await db.query('members', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  // ---------- Scan records ----------

  Future<int> insertScanRecord(ScanRecord record) async {
    final db = await database;
    return db.insert('scan_records', {
      'scanned_id': record.scannedId,
      'purpose': record.purpose.value,
      'radio_qty': record.radioQty,
      'earpiece_qty': record.earpieceQty,
      'bowl_qty': record.bowlQty,
      'basket_qty': record.basketQty,
      'basket_color': record.basketColor,
      'action': record.action,
      'timestamp': record.timestamp,
      'day': record.day,
      'session': record.session,
      'device_id': record.deviceId,
      'operator': record.operator,
      'synced': record.synced,
    });
  }

  Future<List<ScanRecord>> getUnsyncedRecords() async {
    final db = await database;
    final rows = await db.query('scan_records', where: 'synced = 0');
    return rows.map((r) => ScanRecord.fromMap(r)).toList();
  }

  Future<void> markRecordsSynced(List<int> localIds) async {
    if (localIds.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(localIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE scan_records SET synced = 1 WHERE local_id IN ($placeholders)',
      localIds,
    );
  }

  Future<int> unsyncedCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM scan_records WHERE synced = 0'),
        ) ??
        0;
  }
}