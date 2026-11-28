import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class IconLabel extends StatelessWidget {
  const IconLabel({
    super.key,
    required this.icon,
    required this.text,
    this.color,
    this.style,
    this.iconSize = 18,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final TextStyle? style;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? style?.color;
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(
              child: Icon(icon, size: iconSize, color: effectiveColor),
            ),
          ),
          const SizedBox(width: AppSpace.s),
          Flexible(
            child: Text(
              text,
              style: style ?? (color != null ? TextStyle(color: color) : null),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    this.border,
    this.textColor,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final Color? border;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.m,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(icon, size: 16, color: foreground),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor ?? foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.dark = false,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final bool dark;

  @override
  Widget build(BuildContext context) => _MetricTileCard(
    label: label,
    value: value,
    icon: icon,
    dark: dark,
    horizontal: false,
  );
}

class _MetricTileCard extends StatelessWidget {
  const _MetricTileCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.dark,
    required this.horizontal,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final bool dark;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final missing = value == null || value!.trim().isEmpty;
    final display = missing ? '—' : value!;
    final bg = dark
        ? Colors.white.withValues(alpha: 0.14)
        : AppColors.surfaceVariant;
    final border = dark
        ? Colors.white.withValues(alpha: 0.24)
        : AppColors.outline;
    final labelColor = dark
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textMuted;
    final valueColor = dark ? Colors.white : AppColors.textPrimary;
    final theme = Theme.of(context).textTheme;
    final labelStyle = theme.labelMedium?.copyWith(
      color: labelColor,
      fontSize: horizontal ? null : 11.5,
    );
    final valueStyle = (horizontal ? theme.titleLarge : theme.titleMedium)
        ?.copyWith(
          color: valueColor,
          fontWeight: FontWeight.w700,
          fontSize: horizontal ? null : 17,
          fontFeatures: tabularFigures,
        );

    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          ExcludeSemantics(child: Icon(icon, size: 14, color: labelColor)),
          const SizedBox(width: 4),
        ],
        Flexible(child: Text(label, style: labelStyle)),
      ],
    );
    final valueWidget = Text(display, style: valueStyle);

    return Semantics(
      label: missing ? '$label: tidak tersedia' : '$label: $display',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontal ? AppSpace.m : 10,
            vertical: horizontal ? AppSpace.m : 10,
          ),
          child: horizontal
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: labelWidget),
                    const SizedBox(width: AppSpace.s),
                    Flexible(child: valueWidget),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelWidget,
                    const SizedBox(height: AppSpace.xs),
                    valueWidget,
                  ],
                ),
        ),
      ),
    );
  }
}

class MetricStrip extends StatelessWidget {
  const MetricStrip({super.key, required this.tiles});

  final List<MetricTile> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final minColumnWidth = MediaQuery.textScalerOf(context).scale(96);
        final fitsRow = constraints.maxWidth / tiles.length >= minColumnWidth;
        if (fitsRow) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.s),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpace.s),
              _MetricTileCard(
                label: tiles[i].label,
                value: tiles[i].value,
                icon: tiles[i].icon,
                dark: tiles[i].dark,
                horizontal: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

class AccentCard extends StatelessWidget {
  const AccentCard({super.key, required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.l),
        child: child,
      ),
    ),
  );
}

class TsunamiPotentialBox extends StatelessWidget {
  const TsunamiPotentialBox({super.key, required this.potential});

  final String? potential;

  @override
  Widget build(BuildContext context) {
    final raw = potential?.trim();
    final lower = raw?.toLowerCase() ?? '';
    final Color tone;
    final IconData icon;
    final double borderWidth;
    final FontWeight valueWeight;

    if (raw == null || raw.isEmpty) {
      tone = AppColors.information;
      icon = Icons.info_outline;
      borderWidth = 1.5;
      valueWeight = FontWeight.w500;
    } else if (lower.contains('tidak berpotensi')) {
      tone = AppColors.success;
      icon = Icons.check_circle_outline;
      borderWidth = 1.5;
      valueWeight = FontWeight.w600;
    } else if (lower.contains('berpotensi') || lower.contains('tsunami')) {
      tone = AppColors.error;
      icon = Icons.tsunami;
      borderWidth = 2;
      valueWeight = FontWeight.w700;
    } else {
      tone = AppColors.information;
      icon = Icons.info_outline;
      borderWidth = 1.5;
      valueWeight = FontWeight.w600;
    }

    final text = (raw == null || raw.isEmpty) ? 'Tidak tersedia dari sumber' : raw;
    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tone, width: borderWidth),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ExcludeSemantics(
                  child: Icon(icon, color: tone, size: 22),
                ),
              ),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Potensi',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: valueWeight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}
