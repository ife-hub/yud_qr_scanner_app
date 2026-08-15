/// -----------------------------------------------------------------------
/// EDIT THIS: set kEventStartDate to the actual Tuesday your event begins.
/// Everything else (Day 1-5, session windows per weekday) is computed
/// automatically from that one date, following these rules:
///   - Tuesday (Day 1): Night session only
///   - Wednesday, Thursday, Friday (Days 2-4): Morning, Afternoon, Night
///   - Saturday (Day 5): Morning session only
/// -----------------------------------------------------------------------
final DateTime kEventStartDate = DateTime(2026, 8, 18); // <-- SET YOUR REAL TUESDAY DATE HERE

// Fails fast if kEventStartDate isn't actually a Tuesday, instead of
// silently producing a scrambled schedule.
final _kEventStartDateCheck = () {
  assert(
    kEventStartDate.weekday == DateTime.tuesday,
    'kEventStartDate must fall on a Tuesday — got ${_weekdayNames[kEventStartDate.weekday - 1]}',
  );
  return true;
  
}();

// TESTING ONLY: when true, currentActiveSession() always returns a fake
// active session instead of checking the real date/time — regardless of
// build mode (debug, profile, or release/APK).
//
// *** MUST be set back to false before shipping the real build, or the
// app will always report a fake active session in production. ***
const bool kForceActiveSessionForTesting = true;

// Time windows for each named session - edit if your actual hours differ.
const Map<String, List<String>> kSessionTimes = {
  'Morning': ['06:00', '12:00'],
  'Afternoon': ['13:00', '17:00'],
  'Night': ['18:00', '23:59'],
};

const Map<String, String> kSessionDisplayLabels = {
  'Morning': 'Hour Of Visitation',
  'Afternoon': 'Specialized Classes',
  'Night': 'Encounter Night',
};

class SessionWindow {
  final String name;
  final String start;
  final String end;

  const SessionWindow({required this.name, required this.start, required this.end});

  DateTime _timeOn(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    return DateTime(date.year, date.month, date.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  bool contains(DateTime dateTime) {
    final startDt = _timeOn(dateTime, start);
    final endDt = _timeOn(dateTime, end);
    return !dateTime.isBefore(startDt) && dateTime.isBefore(endDt);
  }
}

class EventDay {
  final int dayNumber;
  final DateTime date;
  final List<SessionWindow> sessions;

  const EventDay({required this.dayNumber, required this.date, required this.sessions});

  bool isSameDate(DateTime other) =>
      date.year == other.year && date.month == other.month && date.day == other.day;
}

List<SessionWindow> _sessionsFor(String weekday) {
  List<String> names;
  switch (weekday) {
    case 'Tuesday':
      names = ['Night'];
      break;
    case 'Saturday':
      names = ['Morning'];
      break;
    default: // Wednesday, Thursday, Friday
      names = ['Morning', 'Afternoon', 'Night'];
  }
  return names
      .map((n) => SessionWindow(name: n, start: kSessionTimes[n]![0], end: kSessionTimes[n]![1]))
      .toList();
}

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];

/// Generates Day 1 (Tuesday) through Day 5 (Saturday) from kEventStartDate.
final List<EventDay> eventSchedule = List.generate(5, (i) {
  final date = kEventStartDate.add(Duration(days: i));
  final weekdayName = _weekdayNames[date.weekday - 1];
  return EventDay(dayNumber: i + 1, date: date, sessions: _sessionsFor(weekdayName));
});

class ActiveSession {
  final int dayNumber;
  final DateTime date;
  final String sessionName;

  ActiveSession({required this.dayNumber, required this.date, required this.sessionName});

  String get label => 'Day $dayNumber';
  String get sessionDisplayLabel => kSessionDisplayLabels[sessionName] ?? sessionName;
}

ActiveSession? currentActiveSession([DateTime? now]) {
  if (kForceActiveSessionForTesting) {
    return ActiveSession(dayNumber: 1, date: DateTime.now(), sessionName: 'Morning');
  }

  final n = now ?? DateTime.now();
  for (final day in eventSchedule) {
    if (!day.isSameDate(n)) continue;
    for (final session in day.sessions) {
      if (session.contains(n)) {
        return ActiveSession(dayNumber: day.dayNumber, date: day.date, sessionName: session.name);
      }
    }
  }
  return null;
}