import 'package:flutter/material.dart';

import '../../features/events/event_dto.dart';
import '../theme/app_theme.dart';
import '../utils/labels.dart';
import '../utils/time_format.dart';
import 'ui_kit.dart';

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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.simulation,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExcludeSemantics(
            child: Icon(Icons.science_outlined, color: Colors.white, size: 18),
          ),
          const SizedBox(width: AppSpace.s),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class FreshnessBanner extends StatelessWidget {
  const FreshnessBanner({super.key, required this.sources, this.compact = false});
  final List<SourceFreshnessDto> sources;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final allHealthy =
        sources.isNotEmpty && sources.every((s) => s.state == 'healthy');
    if (allHealthy) {
      final summary = sources.length >= 2
          ? 'Sumber resmi BMKG · Gempa & Cuaca aktif'
          : 'Sumber resmi BMKG · ${sources.single.source == 'BMKG_TEWS' ? 'Gempa' : 'Cuaca'} aktif';
      return Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
        child: IconLabel(
          icon: Icons.verified_outlined,
          text: summary,
          color: AppColors.success,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.success,
            fontWeight: FontWeight.w600,
          ),
          iconSize: 16,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpace.s : AppSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: compact ? AppSpace.xs : AppSpace.s,
          children: [
            for (final source in sources) _source(context, source),
          ],
        ),
      ),
    );
  }

  Widget _source(BuildContext context, SourceFreshnessDto source) {
    final name = source.source == 'BMKG_TEWS' ? 'BMKG Gempa' : 'BMKG Cuaca';
    final (icon, color) = switch (source.state) {
      'healthy' => (Icons.check_circle_outline, AppColors.success),
      'degraded' => (Icons.warning_amber, AppColors.warning),
      'stale' => (Icons.schedule, AppColors.warning),
      _ => (Icons.cloud_off_outlined, AppColors.error),
    };
    final last = source.lastSuccessAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconLabel(
          icon: icon,
          text: '$name — ${sourceStateLabel(source.state)}',
          color: color,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: color == AppColors.warning ? AppColors.textPrimary : color,
          ),
        ),
        if (source.state != 'healthy')
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Data $name belum berhasil diperbarui. '
              '${last == null ? 'Belum pernah berhasil diperbarui.' : 'Terakhir berhasil ${formatLocalDateTime(last)}.'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
