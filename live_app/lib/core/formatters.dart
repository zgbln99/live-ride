/// Formatting helpers shared by every Live Ride screen so a value never renders
/// with two different precisions in two places.
abstract final class Fmt {
  static String distance(double meters, {bool metric = true}) {
    if (!meters.isFinite || meters <= 0) return metric ? '0.00' : '0.00';
    if (metric) {
      final km = meters / 1000;
      if (km < 10) return km.toStringAsFixed(2);
      if (km < 100) return km.toStringAsFixed(1);
      return km.toStringAsFixed(0);
    }
    final miles = meters / 1609.344;
    if (miles < 10) return miles.toStringAsFixed(2);
    if (miles < 100) return miles.toStringAsFixed(1);
    return miles.toStringAsFixed(0);
  }

  static String distanceUnit({bool metric = true}) => metric ? 'km' : 'mi';

  /// Short distance for maneuver callouts: metres below 1 km, then km.
  static String turnDistance(double meters, {bool metric = true}) {
    if (!meters.isFinite || meters < 0) meters = 0;
    if (metric) {
      if (meters < 1000) {
        // Close to the junction the rider wants finer steps than 10 m.
        if (meters < 50) return '${(meters / 5).round() * 5}';
        return '${(meters / 10).round() * 10}';
      }
      final km = meters / 1000;
      return km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0);
    }
    final feet = meters * 3.28084;
    if (feet < 1000) return '${(feet / 10).round() * 10}';
    final miles = meters / 1609.344;
    return miles < 10 ? miles.toStringAsFixed(1) : miles.toStringAsFixed(0);
  }

  static String turnDistanceUnit(double meters, {bool metric = true}) {
    if (metric) return meters < 1000 ? 'm' : 'km';
    return meters * 3.28084 < 1000 ? 'ft' : 'mi';
  }

  static String speed(double kmh, {bool metric = true}) {
    if (!kmh.isFinite || kmh < 0) kmh = 0;
    final value = metric ? kmh : kmh / 1.609344;
    return value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }

  static String speedUnit({bool metric = true}) => metric ? 'km/h' : 'mph';

  static String elevation(double meters, {bool metric = true}) {
    if (!meters.isFinite) return '0';
    final value = metric ? meters : meters * 3.28084;
    return value.round().toString();
  }

  static String elevationUnit({bool metric = true}) => metric ? 'm' : 'ft';

  static String duration(Duration d) {
    final seconds = d.inSeconds.abs();
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h:${_two(m)}:${_two(s)}';
    return '${_two(m)}:${_two(s)}';
  }

  static String durationCompact(Duration d) {
    final seconds = d.inSeconds.abs();
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${_two(m)}m';
    return '${m}m';
  }

  static String clock(DateTime time) =>
      '${_two(time.hour)}:${_two(time.minute)}';

  static String date(DateTime time) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${time.day} ${months[time.month - 1]} ${time.year}';
  }

  /// Nazwa miesiąca z rokiem, po polsku w dopełniaczu — „maj 2026".
  static String monthYear(DateTime time) {
    const months = [
      'styczeń',
      'luty',
      'marzec',
      'kwiecień',
      'maj',
      'czerwiec',
      'lipiec',
      'sierpień',
      'wrzesień',
      'październik',
      'listopad',
      'grudzień',
    ];
    final index = (time.month - 1).clamp(0, 11);
    return '${months[index]} ${time.year}';
  }

  static String dateTime(DateTime time) => '${date(time)} · ${clock(time)}';

  /// Rozmiar pliku po ludzku: 42 MB, 1,3 GB.
  ///
  /// Podstawa 1024, bo tak liczy system telefonu i tak wygląda liczba w
  /// ustawieniach pamięci — inna podstawa dawałaby dwie różne prawdy.
  static String bytes(int value) {
    if (value < 1024) return '$value B';
    const units = ['kB', 'MB', 'GB', 'TB'];
    var size = value / 1024;
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final digits = size >= 100 ? 0 : (size >= 10 ? 1 : 2);
    final number = size.toStringAsFixed(digits).replaceAll('.', ',');
    return '$number ${units[unit]}';
  }

  static String temperature(double celsius, {bool metric = true}) {
    if (!celsius.isFinite) return '--';
    final value = metric ? celsius : celsius * 9 / 5 + 32;
    return '${value.round()}°';
  }

  static String compass(double degrees) {
    if (!degrees.isFinite) return '--';
    const labels = [
      'N',
      'NNE',
      'NE',
      'ENE',
      'E',
      'ESE',
      'SE',
      'SSE',
      'S',
      'SSW',
      'SW',
      'WSW',
      'W',
      'WNW',
      'NW',
      'NNW',
    ];
    final index = (((degrees % 360) + 360) % 360 / 22.5).round() % 16;
    return labels[index];
  }

  static String gradient(double percent) {
    if (!percent.isFinite) return '0.0';
    return percent.toStringAsFixed(1);
  }

  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'[\s_.-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'LR';
    if (parts.length == 1) {
      final single = parts.first;
      return single.length == 1
          ? single.toUpperCase()
          : single.substring(0, 2).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
