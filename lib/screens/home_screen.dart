import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/scan_record.dart';
import '../services/session_service.dart';
import '../services/sync_service.dart';
import '../config/event_schedule.dart';
import '../config/app_config.dart';
import '../widgets/photo_avatar.dart';
import 'scan_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _pendingCount = 0;
  bool _syncing = false;
  String? _syncMessage;
  bool _isOnline = false;

  static const Color _accentColor = Color(0xFFE53935);

  // Only staff with one of these specialRoles get the resource-handout
  // buttons (Radios & Earpieces / Bowls & Baskets). Keep this in sync
  // with the same set in scan_screen.dart.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPendingCount();
    _checkOnline();
    _attemptSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkOnline();
      _attemptSync();
      setState(() {});
    }
  }

  Future<void> _checkOnline() async {
    final online = await SyncService.instance.hasConnection();
    if (mounted) setState(() => _isOnline = online);
  }

  Future<void> _refreshPendingCount() async {
    final count = await DatabaseHelper.instance.unsyncedCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  Future<void> _attemptSync() async {
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });
    final result = await SyncService.instance.syncPendingRecords();
    await _refreshPendingCount();
    await _checkOnline();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      if (result.success) {
        _syncMessage = result.syncedCount > 0 ? 'Synced ${result.syncedCount} record(s)' : null;
      } else if (result.error == 'Offline') {
        _syncMessage = 'Offline - will sync when connected';
      } else if (result.error == 'Already syncing') {
        // no-op
      } else {
        _syncMessage = result.error;
      }
    });
  }

  // Updated signature: ScanScreen now takes a single Purpose that already
  // encodes attendance-vs-resource and which specific category it is.
  void _openScanner(Purpose purpose) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanScreen(purpose: purpose)),
    );
    setState(() {});
    _checkOnline();
    _attemptSync();
  }

  Future<void> _logout() async {
    await SessionService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = SessionService.instance.currentStaff;
    final operator = staff?.name ?? 'Unknown';
    final subtitle = staff != null ? '${staff.role}, ${staff.group}' : '';
    final active = currentActiveSession();

    // General Attendance is open to every admin (gated at scan-time by
    // group-match / member eligibility). Leaders' Attendance is gated by
    // canScanLeaders, and Radios/Baskets are gated by specialRole -
    // only super_admin / operations should see those buttons at all.
    final canHandleResources = staff?.canHandleResources ?? false;
    
    final buttons = <Purpose>[];
    if (active != null) {
      buttons.add(Purpose.generalAttendance);
      if (staff?.canScanLeaders ?? false) {
        buttons.add(Purpose.leadersAttendance);
      }
      if (canHandleResources) {
        buttons.add(Purpose.radio);
        buttons.add(Purpose.basket);
      }
    }

    // Highlight the first action in red only when there are 1-2 of them
    // (a focused role). Broader access (3+ actions) stays neutral black.
    final highlightFirst = buttons.length <= 2;

    final counts = SessionService.instance.sessionScanCounts;
    final totalScanned = counts.values.fold(0, (a, b) => a + b);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Branding header bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(kOrgName, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                  Text(kEventName, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 18),
              // Welcome row with operator's own avatar
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome,\n$operator.', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.2)),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ],
                    ),
                  ),
                  PhotoAvatar(id: staff?.id ?? '', radius: 28),
                ],
              ),
              const SizedBox(height: 20),
              // Hero day/session card - red while online, black while offline.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _isOnline ? _accentColor : Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active != null ? 'Day ${active.dayNumber}' : 'No active session right now',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      active != null
                          ? DateFormat('EEEE, d MMMM yyyy').format(active.date)
                          : 'Check back during a scheduled window.',
                      style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          active != null ? active.sessionDisplayLabel : '',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                            Text(_isOnline ? 'Online' : 'Offline', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Sync status card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$totalScanned IDs scanned this session\n'
                        '${_pendingCount == 0 ? "All records uploaded" : "$_pendingCount records pending upload"}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _syncing ? null : _attemptSync,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: _syncing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sync now'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: buttons.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            active == null
                                ? "Scanning is unavailable outside scheduled sessions."
                                : "You don't have any scanning permissions assigned.\nContact your event admin.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (var i = 0; i < buttons.length; i++) ...[
                            _PurposeButton(
                              label: buttons[i].buttonLabel,
                              primary: highlightFirst && i == 0,
                              onTap: () => _openScanner(buttons[i]),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
              ),
              Center(
                child: TextButton(
                  onPressed: _logout,
                  child: const Text('Log Out', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurposeButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _PurposeButton({required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: primary ? const Color(0xFFE53935) : Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }
}