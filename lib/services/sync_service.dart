import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../db/database_helper.dart';
import '../models/scan_record.dart';

/// -----------------------------------------------------------------------
/// Paste your 3 deployed Google Apps Script Web App URLs below - one per
/// Google Sheet (Members log, Leaders log, Resources log). These 3 sheets
/// cover the whole event; day/session are just columns in each row, not
/// separate sheets.
/// -----------------------------------------------------------------------
const String kMembersSheetUrl = 'https://script.google.com/macros/s/AKfycbxwR_KdtbduliTWZlkWVDAI7QVwfCFB-B-M19m0UTyheCevP9V--0z9nfITcjlYRFBT/exec';
const String kLeadersSheetUrl = 'https://script.google.com/macros/s/AKfycbzvEausTo8uEZgcTnyNwLh3PcCtTupmDB_iu-mFK-oAAtCoJWD4T_g-J4IaBz-DKbK8cw/exec';
const String kResourcesSheetUrl = 'https://script.google.com/macros/s/AKfycbwWZf3RbhYKgvmAkh5uDSUQ9fpjuiFZzUkk4RJWbQt23PTJ1dipexXFqKzL6bPVpOHO/exec';

class SyncResult {
  final bool success;
  final int syncedCount;
  final String? error;

  SyncResult({required this.success, required this.syncedCount, this.error});
}

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  Future<SyncResult>? _inFlight;

  Future<bool> hasConnection() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<SyncResult> syncPendingRecords() {
    if (_inFlight != null) {
      return _inFlight!;
    }
    final future = _doSync();
    _inFlight = future;
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  Future<SyncResult> _doSync() async {
    final online = await hasConnection();
    if (!online) {
      return SyncResult(success: false, syncedCount: 0, error: 'Offline');
    }

    try {
      final db = DatabaseHelper.instance;
      final pending = await db.getUnsyncedRecords();
      if (pending.isEmpty) {
        return SyncResult(success: true, syncedCount: 0);
      }

      final membersRows = <List<dynamic>>[];
      final leadersRows = <List<dynamic>>[];
      final resourcesRows = <List<dynamic>>[];
      final membersLocalIds = <int>[];
      final leadersLocalIds = <int>[];
      final resourcesLocalIds = <int>[];

      for (final r in pending) {
        final member = await db.findMemberById(r.scannedId);
        final name = member?.name ?? 'UNKNOWN';
        final role = member?.role ?? '';
        final group = member?.group ?? '';

        switch (r.purpose) {
          case Purpose.generalAttendance:
            membersRows.add([r.scannedId, name, role, group, r.day, r.session, r.operator, r.deviceId, r.timestamp]);
            membersLocalIds.add(r.localId!);
            break;
          case Purpose.leadersAttendance:
            leadersRows.add([r.scannedId, name, role, group, r.day, r.session, r.operator, r.deviceId, r.timestamp]);
            leadersLocalIds.add(r.localId!);
            break;
          case Purpose.radio:
          case Purpose.basket:
            // id, name, role, group, radioQty, earpieceQty, bowlQty, basketQty, basketColor, action, day, session, operator, deviceId, timestamp
            resourcesRows.add([
              r.scannedId,
              name,
              role,
              group,
              r.radioQty ?? '',
              r.earpieceQty ?? '',
              r.bowlQty ?? '',
              r.basketQty ?? '',
              r.basketColor ?? '',
              r.action ?? '',
              r.day,
              r.session,
              r.operator,
              r.deviceId,
              r.timestamp,
            ]);
            resourcesLocalIds.add(r.localId!);
            break;
        }
      }

      var syncedCount = 0;
      final errors = <String>[];

      if (membersRows.isNotEmpty) {
        final ok = await _postRows(kMembersSheetUrl, membersRows);
        if (ok) {
          await db.markRecordsSynced(membersLocalIds);
          syncedCount += membersRows.length;
        } else {
          errors.add('Failed to sync Members sheet');
        }
      }
      if (leadersRows.isNotEmpty) {
        final ok = await _postRows(kLeadersSheetUrl, leadersRows);
        if (ok) {
          await db.markRecordsSynced(leadersLocalIds);
          syncedCount += leadersRows.length;
        } else {
          errors.add('Failed to sync Leaders sheet');
        }
      }
      if (resourcesRows.isNotEmpty) {
        final ok = await _postRows(kResourcesSheetUrl, resourcesRows);
        if (ok) {
          await db.markRecordsSynced(resourcesLocalIds);
          syncedCount += resourcesRows.length;
        } else {
          errors.add('Failed to sync Resources sheet');
        }
      }

      if (errors.isNotEmpty && syncedCount == 0) {
        return SyncResult(success: false, syncedCount: 0, error: errors.first);
      }
      return SyncResult(success: true, syncedCount: syncedCount);
    } catch (e) {
      return SyncResult(success: false, syncedCount: 0, error: e.toString());
    }
  }

  Future<bool> _postRows(String url, List<List<dynamic>> rows) async {
    if (url.startsWith('PASTE_YOUR')) return false;
    try {
      var response = await http
          .post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'rows': rows}))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 302) {
        final location = response.headers['location'];
        if (location != null) {
          response = await http.get(Uri.parse(location)).timeout(const Duration(seconds: 20));
        }
      }
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}