import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/staff.dart';
import '../models/scan_record.dart';
import '../db/database_helper.dart';

class SessionService {
  SessionService._internal();
  static final SessionService instance = SessionService._internal();

  Staff? currentStaff;

  // Counts scans made since this login session began, broken down by
  // purpose - shown on the dashboard.
  final Map<Purpose, int> sessionScanCounts = {};

  void recordScan(Purpose purpose) {
    sessionScanCounts[purpose] = (sessionScanCounts[purpose] ?? 0) + 1;
  }

  String get operatorName => currentStaff?.name ?? 'Unknown';

  String? _deviceId;

  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? stored = prefs.getString('device_id');
    if (stored == null) {
      stored = const Uuid().v4();
      await prefs.setString('device_id', stored);
    }
    _deviceId = stored;
    return stored;
  }

  Future<void> login(Staff staff, bool keepLoggedIn) async {
    currentStaff = staff;
    sessionScanCounts.clear();
    final prefs = await SharedPreferences.getInstance();
    if (keepLoggedIn) {
      await prefs.setString('saved_username', staff.username);
    } else {
      await prefs.remove('saved_username');
    }
  }

  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUsername = prefs.getString('saved_username');
    if (savedUsername == null) return false;
    final staff = await DatabaseHelper.instance.findStaffByUsername(savedUsername);
    if (staff == null) return false;
    currentStaff = staff;
    sessionScanCounts.clear();
    return true;
  }

  Future<void> logout() async {
    currentStaff = null;
    sessionScanCounts.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
  }
}
