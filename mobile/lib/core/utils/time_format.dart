const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
const _fullMonths = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

String _two(int n) => n.toString().padLeft(2, '0');

String _zone(Duration offset) {
  final minutes = offset.inMinutes;
  return switch (minutes) {
    420 => 'WIB',
    480 => 'WITA',
    540 => 'WIT',
    _ => 'UTC${minutes < 0 ? '-' : '+'}${_two(minutes.abs() ~/ 60)}:${_two(minutes.abs() % 60)}',
  };
}

String _format(DateTime utc, {required bool full}) {
  final local = utc.toLocal();
  final month = (full ? _fullMonths : _months)[local.month - 1];
  final prefix = full ? '${_days[local.weekday - 1]}, ' : '';
  return '$prefix${_two(local.day)} $month ${local.year}, '
      '${_two(local.hour)}:${_two(local.minute)} ${_zone(local.timeZoneOffset)}';
}

String formatLocalDateTime(DateTime utc) => _format(utc, full: false);
String formatFullTooltipDateTime(DateTime utc) => _format(utc, full: true);

String formatDistanceKm(double km) {
  if (km == 0) return 'Di titik pantau';
  if (km < 0.05) return '0 km';
  return '${km.toStringAsFixed(1)} km';
}
