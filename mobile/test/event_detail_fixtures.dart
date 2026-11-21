typedef DetailJson = Map<String, dynamic>;

const quakeKey = '30000000-0000-4000-8000-000000000001';
const weatherKey = '30000000-0000-4000-8000-000000000002';
const _seen = '2026-11-16T03:00:00Z';
const potential = 'Tidak berpotensi tsunami';
const officialUrl = 'https://www.bmkg.go.id/';
const distanceReason = '10 km dari titik pantau, radius 50 km';

DetailJson quakeDetail({String id = quakeKey, int version = 1}) => <String, dynamic>{
  'meta': <String, dynamic>{
    'server_time': _seen,
    'zone_version': version,
    'mode': 'simulation',
    'is_simulated': true,
    'sources': <Object>[
      for (final source in ['BMKG_TEWS', 'BMKG_NOWCAST'])
        <String, dynamic>{
          'source': source,
          'state': 'healthy',
          'last_success_at': _seen,
          'last_attempt_at': _seen,
        },
    ],
  },
  'data': <String, dynamic>{
    'id': id,
    'source': 'BMKG_TEWS',
    'category': 'earthquake',
    'title': 'Gempa uji radar',
    'occurred_at': '2026-11-16T01:00:00Z',
    'latitude': 0,
    'longitude': -179.9,
    'is_simulated': true,
    'content_version': 1,
    'lifecycle_status': 'current',
    'source_url': officialUrl,
    'first_seen_at': _seen,
    'last_seen_at': _seen,
    'priority': <String, dynamic>{
      'priority_algo': 'eq-priority-v1',
      'priority_score': 74.25,
      'priority_display': '74.3',
      'priority_label': 'high',
      'evaluated_at': _seen,
      'zone_version': version,
      'match_method': 'point_distance',
      'match_distance_km': 10,
      'within_radius': true,
      'components': <String, dynamic>{
        'p': 0.8,
        'm': 0.5,
        't': 0.9166666666666666,
        'age_hours': 2,
        'radius_km': 50,
        'magnitude': 5,
      },
      'priority_reasons': <Object>[
        <String, dynamic>{
          'code': 'distance_radius',
          'text': distanceReason,
          'values': <String, dynamic>{'distance_km': 10, 'radius_km': 50},
        },
        <String, dynamic>{
          'code': 'magnitude',
          'text': 'Magnitudo 5',
          'values': <String, dynamic>{'magnitude': 5},
        },
        <String, dynamic>{
          'code': 'age',
          'text': 'Umur informasi 2 jam',
          'values': <String, dynamic>{'age_hours': 2},
        },
        <String, dynamic>{
          'code': 'application_priority',
          'text': 'Prioritas tinggi',
          'values': <String, dynamic>{'priority_label': 'high'},
        },
      ],
    },
    'cap': null,
    'weather': null,
    'areas': <Object>[],
    'references': <Object>[],
    'earthquake': <String, dynamic>{
      'magnitude': 5,
      'depth_km': 10,
      'region': 'Pasifik',
      'latitude_text': '0°',
      'longitude_text': '179.9° BB',
      'potential': potential,
      'felt': 'II',
      'shakemap_url': 'https://data.bmkg.go.id/example.jpg',
    },
  },
};

DetailJson weatherDetail({
  String method = 'inside_polygon',
  double? distance = 0,
  bool? within = true,
  String severity = 'Severe',
  String label = 'high',
  String status = 'active',
}) {
  final envelope = quakeDetail();
  final data = envelope['data'] as DetailJson;
  final geometry = method != 'no_geometry';
  const coordinates = [(0, 179), (0, -179), (1, -179), (1, 179), (0, 179)];
  final invalid = <String, dynamic>{
    'id': '31000000-0000-4000-8000-000000000001',
    'position': 1,
    'geometry_valid': false,
    'centroid_latitude': null,
    'centroid_longitude': null,
    'south': null,
    'north': null,
    'west': null,
    'east': null,
    'crosses_antimeridian': null,
    'vertices': <Object>[],
  };
  data.addAll(<String, dynamic>{
    'id': weatherKey,
    'source': 'BMKG_NOWCAST',
    'category': 'extreme_weather',
    'title': 'Peringatan Pasifik',
    'lifecycle_status': status,
    'latitude': geometry ? 0.5 : null,
    'longitude': geometry ? -180 : null,
    'earthquake': null,
    'weather': <String, dynamic>{
      'sender': 'BMKG',
      'sent': _seen,
      'status': 'Actual',
      'msg_type': 'Update',
      'language': 'id',
      'cap_event': 'Hujan lebat',
      'event_code': null,
      'headline': null,
      'description': 'Peringatan cuaca',
      'web_url': null,
      'lifecycle_complete': status != 'incomplete',
    },
    'cap': <String, dynamic>{
      'severity': severity,
      'urgency': 'Immediate',
      'certainty': 'Likely',
      'effective': _seen,
      'expires': '2026-11-16T04:00:00Z',
      'area_descriptions': <Object>['Pasifik barat', 'Pasifik timur'],
    },
    'areas': <Object>[
      <String, dynamic>{
        'id': '32000000-0000-4000-8000-000000000002',
        'position': 2,
        'area_description': 'Pasifik timur',
        'polygons': <Object>[invalid],
      },
      <String, dynamic>{
        'id': '32000000-0000-4000-8000-000000000001',
        'position': 1,
        'area_description': 'Pasifik barat',
        'polygons': <Object>[
          if (geometry)
            <String, dynamic>{
              ...invalid,
              'id': '31000000-0000-4000-8000-000000000002',
              'geometry_valid': true,
              'centroid_latitude': 0.5,
              'centroid_longitude': -180,
              'south': 0,
              'north': 1,
              'west': 179,
              'east': -179,
              'crosses_antimeridian': true,
              'vertices': <Object>[
                for (var i = coordinates.length - 1; i >= 0; i--)
                  <String, dynamic>{
                    'sequence': i + 1,
                    'latitude': coordinates[i].$1,
                    'longitude': coordinates[i].$2,
                  },
              ],
            },
        ],
      },
    ],
    'priority': <String, dynamic>{
      'priority_algo': 'cap-priority-v1',
      'priority_score': null,
      'priority_display': null,
      'components': null,
      'priority_label': label,
      'match_method': method,
      'match_distance_km': distance,
      'within_radius': within,
      'evaluated_at': _seen,
      'zone_version': 1,
      'priority_reasons': <Object>[
        <String, dynamic>{
          'code': 'area',
          'text': 'Pasifik barat dan timur',
          'values': <String, dynamic>{
            'area_descriptions': <Object>['Pasifik barat', 'Pasifik timur'],
          },
        },
        <String, dynamic>{
          'code': 'location_match',
          'text': 'Metode lokasi: $method',
          'values': <String, dynamic>{
            'match_method': method,
            'match_distance_km': distance,
            'within_radius': within,
          },
        },
        <String, dynamic>{
          'code': 'severity',
          'text': severity,
          'values': <String, dynamic>{'severity': severity},
        },
        <String, dynamic>{
          'code': 'urgency_certainty',
          'text': 'Immediate / Likely',
          'values': <String, dynamic>{'urgency': 'Immediate', 'certainty': 'Likely'},
        },
        <String, dynamic>{
          'code': 'validity',
          'text': status,
          'values': <String, dynamic>{
            'effective': _seen,
            'expires': '2026-11-16T04:00:00Z',
            'lifecycle_status': status,
          },
        },
      ],
    },
    'references': <Object>[
      <String, dynamic>{
        'relation_type': 'update',
        'referenced_source_key': 'BMKG-1',
        'referenced_event_id': quakeKey,
      },
      <String, dynamic>{
        'relation_type': 'update',
        'referenced_source_key': 'BMKG-2',
        'referenced_event_id': null,
      },
    ],
  });
  return envelope;
}
