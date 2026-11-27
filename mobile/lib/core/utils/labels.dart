const priorityLevelLabels = {
  'ordinary': 'Biasa',
  'attention': 'Perhatian',
  'high': 'Tinggi',
  'information': 'Informasi',
  'unavailable': 'Belum tersedia',
};

const lifecycleLabels = {
  'active': 'Aktif',
  'scheduled': 'Terjadwal',
  'expired': 'Kedaluwarsa',
  'cancelled': 'Dibatalkan',
  'superseded': 'Digantikan',
  'incomplete': 'Data belum lengkap',
  'current': 'Terkini',
  'historical': 'Historis',
  'invalid_time': 'Waktu tidak valid',
};

String? capSeverityLabel(String? value) => switch (value) {
  null => null,
  'Minor' => 'Ringan',
  'Moderate' => 'Sedang',
  'Severe' => 'Parah',
  'Extreme' => 'Ekstrem',
  'Unknown' => 'Tidak diketahui',
  _ => value,
};

String? capUrgencyLabel(String? value) => switch (value) {
  null => null,
  'Immediate' => 'Segera',
  'Expected' => 'Diperkirakan',
  'Future' => 'Mendatang',
  'Past' => 'Lampau',
  'Unknown' => 'Tidak diketahui',
  _ => value,
};

String? capCertaintyLabel(String? value) => switch (value) {
  null => null,
  'Observed' => 'Teramati',
  'Likely' => 'Kemungkinan besar',
  'Possible' => 'Mungkin',
  'Unlikely' => 'Kecil kemungkinan',
  'Unknown' => 'Tidak diketahui',
  _ => value,
};

String sourceStateLabel(String state) => switch (state) {
  'healthy' => 'Aktif',
  'degraded' => 'Terganggu',
  'stale' => 'Belum diperbarui',
  _ => 'Tidak tersedia',
};
