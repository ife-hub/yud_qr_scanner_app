import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../db/database_helper.dart';
import '../models/app_user.dart';
import '../models/scan_record.dart';
import '../services/session_service.dart';
import '../services/sync_service.dart';
import '../config/event_schedule.dart';
import '../widgets/photo_avatar.dart';

enum _Mode { scanning, quantityEntry, success, failure }

const Color _accentRed = Color(0xFFE53935);

// EDIT THIS with your real basket color options.
const List<String> kBasketColors = ['Red', 'Blue', 'Green', 'Yellow', 'Black'];

class ScanScreen extends StatefulWidget {
  final Purpose purpose;

  const ScanScreen({super.key, required this.purpose});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  _Mode _mode = _Mode.scanning;
  bool _processing = false;

  String? _lastScannedId;
  DateTime? _lastScannedAt;
  static const _sameCodeCooldown = Duration(seconds: 3);

  // Result state
  AppUser? _resultUser;
  String? _failureMessage;
  int? _savedPrimaryQty;
  int? _savedSecondaryQty;
  String? _savedBasketColor;
  String? _savedAction;
  DateTime? _savedAt;

  // Quantity entry state. Labels are set dynamically based on
  // widget.purpose: Radios/Earpieces for Purpose.radio, Bowls/Baskets
  // for Purpose.basket.
  String _primaryLabel = 'Radios';
  String _secondaryLabel = 'Earpieces';
  int _primaryQty = 0;
  int _secondaryQty = 0;
  String _activeField = 'primary'; // 'primary' | 'secondary'

  // Collecting vs Returning - applies to all resource scans (radio/basket).
  String _action = 'Collecting';

  // Only relevant when purpose == Purpose.basket and the Baskets (secondary)
  // quantity is > 0.
  String? _basketColor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _headerText => 'SCANNING FOR ${widget.purpose.label.toUpperCase()}';

  bool get _needsBasketColor => widget.purpose == Purpose.basket && _secondaryQty > 0;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _mode != _Mode.scanning) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final rawId = barcodes.first.rawValue;
    if (rawId == null || rawId.isEmpty) return;
    final scannedId = rawId.trim();

    final now = DateTime.now();
    if (_lastScannedId == scannedId &&
        _lastScannedAt != null &&
        now.difference(_lastScannedAt!) < _sameCodeCooldown) {
      return;
    }

    setState(() => _processing = true);
    await _controller.stop();

    _lastScannedId = scannedId;
    _lastScannedAt = now;

    final active = currentActiveSession(now);
    if (active == null) {
      _showFailure(null, 'No active session right now.');
      return;
    }

    final staff = SessionService.instance.currentStaff;
    if (staff == null) {
      _showFailure(null, 'Session error. Please log in again.');
      return;
    }

    final db = DatabaseHelper.instance;
    final member = await db.findMemberById(scannedId);

    if (member == null) {
      _showFailure(null, 'QR code not recognized.\n\n($scannedId)');
      return;
    }

    switch (widget.purpose) {
      case Purpose.generalAttendance:
        if (member.role != 'Member') {
          _showFailure(member, '${member.name} is a ${member.role}, not a Member.\nUse Leaders\' Attendance instead.');
          return;
        }
        if (!staff.canCheckInMember(member.group)) {
          _showFailure(member, '${member.name} is in ${member.group}.\nYou can only scan ${staff.group}.');
          return;
        }
        await _saveRecord(member, active, now, null, null, null, null, null, null);
        return;

      case Purpose.leadersAttendance:
        if (!staff.canScanLeaders) {
          _showFailure(member, 'You are not authorized to scan Leaders\' Attendance.');
          return;
        }
        if (member.role == 'Member') {
          _showFailure(member, '${member.name} is a Member, not eligible for Leaders\' Attendance.');
          return;
        }
        await _saveRecord(member, active, now, null, null, null, null, null, null);
        return;

      case Purpose.radio:
      case Purpose.basket:
        if (!staff.canHandleResources) {
          _showFailure(member, 'You are not authorized to hand out ${widget.purpose.label}.');
          return;
        }
        if (!member.canCollectResources) {
          _showFailure(member, '${member.name} is a Member, not eligible to collect ${widget.purpose.label}.');
          return;
        }
        setState(() {
          _primaryLabel = widget.purpose == Purpose.radio ? 'Radios' : 'Bowls';
          _secondaryLabel = widget.purpose == Purpose.radio ? 'Earpieces' : 'Baskets';
          _resultUser = member;
          _primaryQty = 0;
          _secondaryQty = 0;
          _activeField = 'primary';
          _action = 'Collecting';
          _basketColor = null;
          _mode = _Mode.quantityEntry;
        });
        return;
    }
  }

  void _showFailure(AppUser? member, String message) {
    setState(() {
      _resultUser = member;
      _failureMessage = message;
      _mode = _Mode.failure;
    });
  }

  Future<void> _saveRecord(
    AppUser member,
    ActiveSession active,
    DateTime now,
    int? radioQty,
    int? earpieceQty,
    int? bowlQty,
    int? basketQty,
    String? basketColor,
    String? action,
  ) async {
    final db = DatabaseHelper.instance;
    final deviceId = await SessionService.instance.getDeviceId();
    final operator = SessionService.instance.operatorName;

    await db.insertScanRecord(ScanRecord(
      scannedId: member.id,
      purpose: widget.purpose,
      radioQty: radioQty,
      earpieceQty: earpieceQty,
      bowlQty: bowlQty,
      basketQty: basketQty,
      basketColor: basketColor,
      action: action,
      timestamp: now.toIso8601String(),
      day: active.dayNumber,
      session: active.sessionName,
      deviceId: deviceId,
      operator: operator,
    ));

    SessionService.instance.recordScan(widget.purpose);
    SyncService.instance.syncPendingRecords();

    if (!mounted) return;
    setState(() {
      _resultUser = member;
      _savedPrimaryQty = radioQty ?? bowlQty;
      _savedSecondaryQty = earpieceQty ?? basketQty;
      _savedBasketColor = basketColor;
      _savedAction = action;
      _savedAt = now;
      _mode = _Mode.success;
    });
  }

  Future<void> _confirmQuantity() async {
    final active = currentActiveSession();
    if (active == null || _resultUser == null) {
      _showFailure(_resultUser, 'No active session right now.');
      return;
    }

    // Require a basket color if any baskets are being collected/returned.
    if (_needsBasketColor && _basketColor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a basket color.')),
      );
      return;
    }

    int? radioQty, earpieceQty, bowlQty, basketQty;

    if (widget.purpose == Purpose.radio) {
      radioQty = _primaryQty;
      earpieceQty = _secondaryQty;
    } else if (widget.purpose == Purpose.basket) {
      bowlQty = _primaryQty;
      basketQty = _secondaryQty;
    }

    await _saveRecord(
      _resultUser!,
      active,
      DateTime.now(),
      radioQty,
      earpieceQty,
      bowlQty,
      basketQty,
      _needsBasketColor ? _basketColor : null,
      _action,
    );
  }

  Future<void> _scanNext() async {
    setState(() {
      _mode = _Mode.scanning;
      _resultUser = null;
      _failureMessage = null;
    });
    await _controller.start();
    setState(() => _processing = false);
  }

  void _keypadTap(String digit) {
    setState(() {
      final current = _activeField == 'primary' ? _primaryQty : _secondaryQty;
      final next = int.parse('${current == 0 ? '' : current}$digit');
      final capped = next > 999 ? current : next; // sane upper bound
      if (_activeField == 'primary') {
        _primaryQty = capped;
      } else {
        _secondaryQty = capped;
        // Basket color selection only makes sense once there's a count -
        // clear any prior selection if the count drops back to 0.
        if (_secondaryQty == 0) _basketColor = null;
      }
    });
  }

  void _keypadBackspace() {
    setState(() {
      if (_activeField == 'primary') {
        _primaryQty = _primaryQty ~/ 10;
      } else {
        _secondaryQty = _secondaryQty ~/ 10;
        if (_secondaryQty == 0) _basketColor = null;
      }
    });
  }

  // Advances from the primary to the secondary field; if already on the
  // secondary field, treats it as a shortcut for Confirm.
  void _advanceField() {
    if (_activeField == 'primary') {
      setState(() => _activeField = 'secondary');
    } else {
      _confirmQuantity();
    }
  }

  String _userSubtitle(AppUser user) => '${user.role}, ${user.group}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_headerText, style: const TextStyle(fontSize: 12, letterSpacing: 0.5)),
      ),
      body: switch (_mode) {
        _Mode.scanning => _buildScanningView(),
        _Mode.quantityEntry => _buildQuantityEntryView(),
        _Mode.success => _buildSuccessView(),
        _Mode.failure => _buildFailureView(),
      },
    );
  }

  Widget _buildScanningView() {
    final squareSize = MediaQuery.of(context).size.width * 0.82;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: SizedBox(
                  width: squareSize,
                  height: squareSize,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(controller: _controller, onDetect: _onDetect, fit: BoxFit.cover),
                      if (_processing) Container(color: Colors.black26),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Point Camera at QR Code', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, child) {
                  final isOn = state.torchState == TorchState.on;
                  return GestureDetector(
                    onTap: () => _controller.toggleTorch(),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isOn ? _accentRed : Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flashlight_on, color: Colors.white),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityEntryView() {
    final user = _resultUser!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              user.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _userSubtitle(user),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            _ActionToggle(
              value: _action,
              onChanged: (v) => setState(() => _action = v),
            ),
            const SizedBox(height: 16),
            _QuantityRow(
              label: _primaryLabel,
              value: _primaryQty,
              selected: _activeField == 'primary',
              onTap: () => setState(() => _activeField = 'primary'),
            ),
            const SizedBox(height: 10),
            _QuantityRow(
              label: _secondaryLabel,
              value: _secondaryQty,
              selected: _activeField == 'secondary',
              onTap: () => setState(() => _activeField = 'secondary'),
            ),
            if (_needsBasketColor) ...[
              const SizedBox(height: 16),
              const Text('Basket Color', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in kBasketColors)
                    ChoiceChip(
                      label: Text(color),
                      selected: _basketColor == color,
                      onSelected: (_) => setState(() => _basketColor = color),
                      selectedColor: _accentRed,
                      labelStyle: TextStyle(
                        color: _basketColor == color ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: Colors.grey.shade100,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            _NumberPad(onDigit: _keypadTap, onBackspace: _keypadBackspace, onNext: _advanceField),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accentRed,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: _confirmQuantity,
                  child: const Text('Confirm', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    final user = _resultUser!;
    final timeStr = DateFormat('HH:mm:ss').format(_savedAt!);
    String message;
    if (widget.purpose == Purpose.radio || widget.purpose == Purpose.basket) {
      final parts = <String>[];
      if (_savedPrimaryQty != null) parts.add('$_savedPrimaryQty $_primaryLabel');
      if (_savedSecondaryQty != null) parts.add('$_savedSecondaryQty $_secondaryLabel');
      var msg = '${parts.join(' & ')} ${_savedAction ?? "Collected"} at $timeStr';
      if (_savedBasketColor != null) msg = '$msg\n($_savedBasketColor baskets)';
      message = msg;
    } else {
      message = '${widget.purpose.label} Recorded at $timeStr';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PhotoAvatar(id: user.id, radius: 55),
            const SizedBox(height: 16),
            Text(user.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(_userSubtitle(user), style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _accentRed,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                ),
                onPressed: _scanNext,
                child: const Text('Scan Next', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailureView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, color: Colors.red.shade700, size: 64),
            const SizedBox(height: 16),
            const Text('Scan Failed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(_failureMessage ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                ),
                onPressed: _scanNext,
                child: const Text('Scan Again', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Collecting / Returning segmented toggle.
class _ActionToggle extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;

  const _ActionToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(child: _segment('Collecting')),
          Expanded(child: _segment('Returning')),
        ],
      ),
    );
  }

  Widget _segment(String label) {
    final selected = value == label;
    return GestureDetector(
      onTap: () => onChanged(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// A row with a fixed light-grey background. The label sits in its own
// pill (black when this field is active, white when inactive), and the
// value is plain text to the right — the pill only ever wraps the label,
// never the whole row. The pill has a fixed width so the Bowls/Baskets
// (or Radios/Earpieces) pair line up with each other regardless of how
// long each label text is.
class _QuantityRow extends StatelessWidget {
  final String label;
  final int value;
  final bool selected;
  final VoidCallback onTap;

  // Shared width for the label pill across both rows. "Earpieces" is the
  // longest label currently used, so this comfortably fits every label
  // with room to spare.
  static const double _pillWidth = 130;

  const _QuantityRow({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: _pillWidth,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: selected ? Colors.white : Colors.black,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '$value',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Circular numpad: digits/backspace are black, the trailing "next field /
// confirm" key is red with a white arrow.
class _NumberPad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onNext;

  const _NumberPad({required this.onDigit, required this.onBackspace, required this.onNext});

  Widget _key({required Widget child, required Color color, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.all(3.0),
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const digitStyle = TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w600);
    final keys = <Widget>[
      for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
        _key(child: Text(d, style: digitStyle), color: Colors.black, onTap: () => onDigit(d)),
      _key(child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 20), color: Colors.black, onTap: onBackspace),
      _key(child: Text('0', style: digitStyle), color: Colors.black, onTap: () => onDigit('0')),
      _key(child: const Icon(Icons.arrow_forward, color: Colors.white, size: 22), color: _accentRed, onTap: onNext),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.25,
      children: keys,
    );
  }
}