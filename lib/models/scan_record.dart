enum Purpose { generalAttendance, leadersAttendance, radio, basket }

extension PurposeLabel on Purpose {
  String get label {
    switch (this) {
      case Purpose.generalAttendance:
        return 'General Attendance';
      case Purpose.leadersAttendance:
        return "Leaders' Attendance";
      case Purpose.radio:
        return 'Radios & Earpieces';
      case Purpose.basket:
        return 'Bowls & Baskets';
    }
  }

  String get buttonLabel {
    switch (this) {
      case Purpose.generalAttendance:
        return 'Scan For General Attendance';
      case Purpose.leadersAttendance:
        return "Scan For Leaders' Attendance";
      case Purpose.radio:
        return 'Scan For Radios & Earpieces';
      case Purpose.basket:
        return 'Scan For Bowls & Baskets';
    }
  }

  String get value {
    switch (this) {
      case Purpose.generalAttendance:
        return 'general_attendance';
      case Purpose.leadersAttendance:
        return 'leaders_attendance';
      case Purpose.radio:
        return 'radio';
      case Purpose.basket:
        return 'basket';
    }
  }

  bool get needsQuantity => this == Purpose.radio || this == Purpose.basket;

  static Purpose fromValue(String value) {
    return Purpose.values.firstWhere((p) => p.value == value);
  }
}

class ScanRecord {
  final int? localId;
  final String scannedId; // AppUser.id, or Staff.username if scansStaff
  final Purpose purpose;
  final int? radioQty; // for radio purpose
  final int? earpieceQty; // for radio purpose
  final int? bowlQty; // for basket purpose
  final int? basketQty; // for basket purpose
  final String? basketColor; // only set when basketQty > 0
  final String? action; // 'Collecting' or 'Returning' - only for radio/basket purposes
  final String timestamp; // ISO 8601
  final int day;
  final String session;
  final String deviceId;
  final String operator;
  final int synced;

  ScanRecord({
    this.localId,
    required this.scannedId,
    required this.purpose,
    this.radioQty,
    this.earpieceQty,
    this.bowlQty,
    this.basketQty,
    this.basketColor,
    this.action,
    required this.timestamp,
    required this.day,
    required this.session,
    required this.deviceId,
    required this.operator,
    this.synced = 0,
  });

  factory ScanRecord.fromMap(Map<String, dynamic> map) {
    return ScanRecord(
      localId: map['local_id'] as int?,
      scannedId: map['scanned_id'] as String,
      purpose: PurposeLabel.fromValue(map['purpose'] as String),
      radioQty: map['radio_qty'] as int?,
      earpieceQty: map['earpiece_qty'] as int?,
      bowlQty: map['bowl_qty'] as int?,
      basketQty: map['basket_qty'] as int?,
      basketColor: map['basket_color'] as String?,
      action: map['action'] as String?,
      timestamp: map['timestamp'] as String,
      day: map['day'] as int,
      session: map['session'] as String,
      deviceId: map['device_id'] as String,
      operator: map['operator'] as String,
      synced: map['synced'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'local_id': localId,
      'scanned_id': scannedId,
      'purpose': purpose.value,
      'radio_qty': radioQty,
      'earpiece_qty': earpieceQty,
      'bowl_qty': bowlQty,
      'basket_qty': basketQty,
      'basket_color': basketColor,
      'action': action,
      'timestamp': timestamp,
      'day': day,
      'session': session,
      'device_id': deviceId,
      'operator': operator,
      'synced': synced,
    };
  }
}