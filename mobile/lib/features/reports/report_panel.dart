import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/status_banners.dart';
import '../../core/widgets/ui_kit.dart';
import 'moderation_view_model.dart';
import 'report_dto.dart';

Future<void> showReportPanel(BuildContext context, ReportDto report) =>
    showReportById(context, report.id, initial: report);

Future<void> showReportById(
  BuildContext context,
  String id, {
  ReportDto? initial,
}) async {
  final model = context.read<ModerationViewModel>();
  model.openId(id, initial: initial);
  final owner = model.panelOwner;
  try {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => ReportPanel(id: id),
    );
  } finally {
    if (owner != null && identical(model.panelOwner, owner)) {
      model.closePanel();
    }
  }
}

IconData reportCategoryIcon(String key) => switch (key) {
  'earthquake' => Icons.waves,
  'flood' => Icons.water,
  'eruption' => Icons.terrain,
  'extreme_weather' => Icons.thunderstorm,
  _ => Icons.cloud,
};

IconData reportStatusIcon(String key) => switch (key) {
  'verified' => Icons.verified,
  'rejected' => Icons.cancel_outlined,
  'in_review' => Icons.rate_review,
  _ => Icons.schedule,
};

class ReportStatusPill extends StatelessWidget {
  const ReportStatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'verified' => AppColors.success,
      'rejected' => AppColors.error,
      'in_review' => AppColors.information,
      _ => AppColors.warning,
    };
    return StatusPill(
      icon: reportStatusIcon(status),
      label: reportStatusLabels[status] ?? status,
      foreground: color,
      background: color.withValues(alpha: 0.10),
    );
  }
}

class ReportLabels extends StatelessWidget {
  const ReportLabels(this.report, {super.key});
  final ReportDto report;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      IconLabel(
        icon: Icons.campaign_outlined,
        text: report.status == 'verified'
            ? 'Warga — ditinjau admin aplikasi'
            : 'Warga',
        color: AppColors.primary,
      ),
      IconLabel(
        icon: reportCategoryIcon(report.category),
        text: reportCategories[report.category] ?? report.category,
        color: AppColors.primary,
      ),
      ReportStatusPill(report.status),
      if (report.isSimulated) const SimulationBadge(),
    ],
  );
}

Widget _time(String title, DateTime date) => Tooltip(
  message: formatFullTooltipDateTime(date),
  child: Text('$title: ${formatLocalDateTime(date)}'),
);

Widget reportNotice(String text) => Semantics(liveRegion: true, child: Text(text));

class _SignedPhoto extends StatefulWidget {
  const _SignedPhoto({super.key, required this.url, required this.onFailure});
  final String url;
  final VoidCallback onFailure;

  @override
  State<_SignedPhoto> createState() => _SignedPhotoState();
}

class _SignedPhotoState extends State<_SignedPhoto> {
  @override
  void dispose() {
    NetworkImage(widget.url).evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image.network(
    widget.url,
    semanticLabel: 'Foto laporan warga',
    errorBuilder: (_, _, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFailure();
      });
      return const Text('Foto tidak dapat dimuat.');
    },
  );
}

class ReportPanel extends StatelessWidget {
  const ReportPanel({super.key, required this.id});
  final String id;

  Future<void> _decision(BuildContext context, String outcome) async {
    final model = context.read<ModerationViewModel>();
    model.decisionDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => Consumer<ModerationViewModel>(
        builder: (_, vm, _) {
          if (!vm.decisionDialogOpen) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (dialog.mounted && ModalRoute.of(dialog)?.isCurrent == true) {
                Navigator.pop(dialog);
              }
            });
          }
          return PopScope(
            canPop: !vm.actionBusy,
            child: AlertDialog(
              scrollable: true,
              title: Text(
                outcome == 'verified' ? 'Setujui laporan' : 'Tolak laporan',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: vm.draftReason,
                    enabled: !vm.actionBusy,
                    minLines: 2,
                    maxLines: 5,
                    onChanged: vm.setReason,
                    decoration: InputDecoration(
                      labelText: 'Alasan keputusan',
                      counterText: '${vm.reasonLength}/500',
                      errorText: vm.validReason
                          ? null
                          : 'Masukkan 10–500 karakter.',
                    ),
                  ),
                  if (vm.actionError != null) reportNotice(vm.actionError!),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: vm.actionBusy ? null : () => Navigator.pop(dialog),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: !vm.validReason || vm.actionBusy
                      ? null
                      : () => vm.submitDecision(outcome),
                  child: const Text('Simpan keputusan'),
                ),
              ],
            ),
          );
        },
      ),
    );
    model.decisionDialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ModerationViewModel>();
    final report = vm.panelReport;
    final revision = vm.photoRevision;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            'Detail laporan warga',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (vm.conflictMessage != null) reportNotice(vm.conflictMessage!),
          if (vm.actionError != null) reportNotice(vm.actionError!),
          if (vm.panelLoading) const LinearProgressIndicator(),
          if (vm.panelError != null) ...[
            reportNotice(vm.panelError!),
            TextButton(
              onPressed: () => vm.openId(id, forceRefresh: true),
              child: const Text('Coba lagi'),
            ),
          ],
          if (report != null) ...[
            ReportLabels(report),
            Text(report.description),
            _time('Dibuat', report.createdAt),
            if (report.verifiedAt != null) _time('Ditinjau', report.verifiedAt!),
            if (vm.canAudit && report.claimedAt != null)
              _time('Diambil untuk ditinjau', report.claimedAt!),
            if (vm.canAudit && report.decidedAt != null)
              _time('Diputuskan', report.decidedAt!),
            if (vm.canAudit && report.latestReason != null)
              Text('Alasan terakhir: ${report.latestReason}'),
            Text(
              'Koordinat: ${report.latitude}, ${report.longitude}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (report.matchDistanceKm != null)
              Text(formatDistanceKm(report.matchDistanceKm!)),
            if (report.eventId != null) Text('Terkait event: ${report.eventId}'),
            if (report.hasPhoto && !vm.panelLoading) ...[
              if (vm.photoError != null)
                Text(vm.photoError!)
              else if (vm.photoUrl != null)
                Stack(
                  children: [
                    _SignedPhoto(
                      key: ValueKey(revision),
                      url: vm.photoUrl!,
                      onFailure: () =>
                          vm.refreshPhotoUrlOnce(revision: revision),
                    ),
                    if (report.isSimulated || vm.photoIsSimulated)
                      const SimulationBadge(),
                  ],
                )
              else
                const Text('Memuat foto…'),
            ],
            if (vm.canAudit)
              ExpansionTile(
                title: const Text('Jejak peninjauan'),
                children: [
                  if (vm.verificationsLoading)
                    const LinearProgressIndicator()
                  else if (vm.verificationsError != null)
                    Text(vm.verificationsError!)
                  else if (vm.verifications.isEmpty)
                    const Text('Belum ada jejak peninjauan.')
                  else
                    for (final entry in vm.verifications)
                      ListTile(
                        title: Text(
                          '${reportStatusLabels[entry.fromStatus]} → ${reportStatusLabels[entry.toStatus]}',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entry.reason != null) Text(entry.reason!),
                            Text('Versi ${entry.resultingVersion}'),
                            _time('Waktu', entry.createdAt),
                          ],
                        ),
                      ),
                ],
              ),
            if (vm.admin && report.isPrivate && !vm.panelLoading) ...[
              if (report.status == 'pending')
                if (report.reporterId == vm.session.user?.id)
                  const FilledButton(
                    onPressed: null,
                    child: IconLabel(
                      icon: Icons.block,
                      text: 'Tidak dapat meninjau laporan sendiri',
                    ),
                  )
                else
                  FilledButton(
                    onPressed: vm.canClaim && !vm.actionBusy
                        ? vm.claimActiveReport
                        : null,
                    child: const Text('Ambil untuk ditinjau'),
                  ),
              if (report.status == 'in_review') ...[
                Text(
                  'Peninjau: ${(report.reviewerId ?? '—').split('-').first} · versi ${report.version}',
                ),
                if (vm.canDecide)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final outcome in ['verified', 'rejected'])
                        FilledButton(
                          onPressed: vm.actionBusy
                              ? null
                              : () => _decision(context, outcome),
                          child: Text(
                            outcome == 'verified' ? 'Setujui' : 'Tolak',
                          ),
                        ),
                    ],
                  )
                else
                  Text(
                    'Sedang ditinjau oleh admin lain (${(report.reviewerId ?? "—").split("-").first})',
                  ),
              ],
            ],
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}
