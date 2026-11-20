import 'package:flutter/material.dart';

import '../../features/events/event_dto.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';

class SimulationBanner extends StatelessWidget {
  const SimulationBanner({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: double.infinity,
    child: _SimulationLabel('SIMULASI — data demo'),
  );
}

class SimulationBadge extends StatelessWidget {
  const SimulationBadge({super.key});
  @override
  Widget build(BuildContext context) => const _SimulationLabel('SIMULASI');
}

class _SimulationLabel extends StatelessWidget {
  const _SimulationLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.simulation,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Icon(Icons.science_outlined, color: Colors.white),
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ]),
    ),
  );
}

class FreshnessBanner extends StatelessWidget {
  const FreshnessBanner({super.key, required this.sources, this.compact = false});
  final List<SourceFreshnessDto> sources;
  final bool compact;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12, runSpacing: 8,
    children: [
      for (final source in sources) _source(context, source),
    ],
  );

  Widget _source(BuildContext context, SourceFreshnessDto source) {
    final name = source.source == 'BMKG_TEWS' ? 'BMKG Gempa' : 'BMKG Cuaca';
    final (icon, color) = switch (source.state) {
      'healthy' => (Icons.check_circle_outline, AppColors.success),
      'degraded' => (Icons.warning_amber, AppColors.warning),
      'stale' => (Icons.schedule, AppColors.warning),
      _ => (Icons.cloud_off_outlined, AppColors.error),
    };
    final last = source.lastSuccessAt;
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: EdgeInsets.all(compact ? 6 : 10),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Icon(icon, color: color), Text('$name — ${source.state}'),
          ]),
          if (source.state != 'healthy')
            Text('Data $name belum berhasil diperbarui. '
                '${last == null ? 'Belum pernah berhasil diperbarui.' : 'Terakhir berhasil ${formatLocalDateTime(last)}.'}'),
        ]),
      ),
    );
  }
}
