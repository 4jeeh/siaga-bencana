import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_coordinator.dart';
import '../../core/widgets/status_banners.dart';
import '../auth/auth_view_model.dart';
import 'moderation_view_model.dart';
import 'report_dto.dart';
import 'report_form.dart';
import 'report_panel.dart';
import 'reports_view_model.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.eventId});
  final String? eventId;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}
class _ReportsScreenState extends State<ReportsScreen> {
  int tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { _prefill(); context.read<ReportsViewModel>().loadNearby(); } });
  }
  void _prefill() { final id = widget.eventId; if (id != null && id.isNotEmpty) context.read<ReportsViewModel>().applyInitialEventId(id); }
  @override
  void didUpdateWidget(ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.eventId != oldWidget.eventId) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _prefill(); });
  }
  Future<void> _compose() async {
    final session = context.read<SessionCoordinator>();
    final generation = session.generation;
    while (mounted && session.generation == generation) {
      final manual = await showModalBottomSheet<bool>(context: context, useSafeArea: true, isScrollControlled: true,
        builder: (sheet) => sheet.watch<SessionCoordinator>().generation == generation
            ? const ReportForm() : const SizedBox.shrink());
      if (manual != true || !mounted || session.generation != generation) return;
      await context.push<void>('/map?mode=pick_report');
      if (!mounted) return;
    }
  }
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportsViewModel>();
    final mod = context.watch<ModerationViewModel>();
    final admin = context.watch<SessionCoordinator>().user?.role == 'admin';
    final index = tab == 2 && !admin ? 0 : tab;
    final state = [vm.nearby, vm.mine, mod.review][index];
    final load = [vm.loadNearby, vm.loadMine, mod.loadReview][index];
    final simulated = context.watch<AuthViewModel>().healthMeta?.isSimulated == true || state.meta?.isSimulated == true;
    final filters = <String?, String>{null: index == 2 ? 'Keduanya' : 'Semua', ...switch (index) {
      0 => reportCategories, 1 => reportStatusLabels, _ => const {'pending': 'Menunggu', 'in_review': 'Sedang ditinjau'},
    }};
    final selected = [vm.nearbyCategory, vm.mineStatus, mod.reviewStatusFilter][index];
    final filter = [vm.filterNearby, vm.filterMine, mod.filterReview][index];
    final scaled = MediaQuery.textScalerOf(context).scale(22) > 32;
    return DefaultTabController(length: admin ? 3 : 2, child: Scaffold(
      appBar: AppBar(toolbarHeight: scaled ? 120 : kToolbarHeight,
        title: const Text('Lapor Warga', maxLines: 2, softWrap: true), actions: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: scaled ? 168 : 200),
            child: TextButton(
              onPressed: _compose,
              child: const Text('Tulis Laporan', textAlign: TextAlign.center, softWrap: true, maxLines: 2),
            ),
          ),
        ],
        bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, onTap: (value) {
          setState(() => tab = value); [vm.loadNearby, vm.loadMine, mod.loadReview][value]();
        }, tabs: [const Tab(text: 'Sekitar', height: 52), const Tab(text: 'Saya', height: 52), if (admin) const Tab(text: 'Tinjau', height: 52)])),
      body: RefreshIndicator(onRefresh: () => load(), child: ListView.builder(key: PageStorageKey('reports-$index'), physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16), itemCount: state.items.length + 2, itemBuilder: (context, position) {
          if (position == 0) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              if (simulated) const SimulationBanner(), if (vm.draftEventId != null) Text('Terkait event: ${vm.draftEventId}'),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final entry in filters.entries) FilterChip(materialTapTargetSize: MaterialTapTargetSize.padded,
                avatar: entry.key == null ? null : Icon(index == 0 ? reportCategoryIcon(entry.key!) : reportStatusIcon(entry.key!)),
                label: Text(entry.value), selected: selected == entry.key, onSelected: (_) => filter(entry.key))]),
              if (state.initialLoading || state.refreshing) const LinearProgressIndicator(),
              if (state.error != null) ...[reportNotice(state.error!), TextButton(onPressed: () => load(), child: const Text('Coba lagi'))],
              if (state.zoneRequired) OutlinedButton(onPressed: () => context.go('/account?edit=zone'), child: const Text('Ubah Zona')),
              if (state.empty) Text(['Belum ada laporan ditinjau dalam radius', 'Belum ada laporan Anda', 'Antrean sesuai filter kosong'][index]),
            ]);
          }
          if (position > state.items.length) {
            return Column(children: [if (state.loadMoreError != null) reportNotice(state.loadMoreError!),
              if (state.page?.hasMore == true) OutlinedButton(onPressed: state.loadingMore ? null : () => load(more: true), child: Text(state.loadingMore ? 'Memuat…' : 'Muat lebih banyak'))]);
          }
          final report = state.items[position - 1];
          return Padding(padding: const EdgeInsets.only(top: 12), child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [ReportLabels(report), Text(report.description),
              if (index != 0 && report.version != null) Text('Versi ${report.version}'), if (index != 0 && report.latestReason != null) Text(report.latestReason!),
              OutlinedButton(onPressed: () => showReportPanel(context, report), child: Text(index == 2 ? 'Lihat / Tinjau' : 'Lihat'))]))));
        })),
    ));
  }
}
