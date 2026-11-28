import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/status_banners.dart';
import '../../core/widgets/ui_kit.dart';
import '../auth/auth_view_model.dart';
import 'report_dto.dart';
import 'report_panel.dart';
import 'report_photo_service.dart';
import 'reports_view_model.dart';

class ReportForm extends StatefulWidget {
  const ReportForm({super.key});
  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  bool selectingEvent = false;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportsViewModel>();
    final health = context.watch<AuthViewModel>();
    final photo = vm.draftPhoto;
    final simulated =
        health.healthMeta?.isSimulated == true ||
        vm.nearby.meta?.isSimulated == true;
    final count = vm.descriptionLength;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Tulis laporan warga',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SectionHeader('Kategori'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in reportCategoryOrder)
                  ChoiceChip(
                    avatar: Icon(reportCategoryIcon(key), size: 18),
                    label: Text(reportCategories[key]!),
                    selected: vm.draftCategory == key,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: vm.submitting
                        ? null
                        : (_) => vm.setCategory(key),
                  ),
              ],
            ),
            if (vm.draftCategory == null)
              Text(
                'Pilih kategori.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.error),
              ),
            const SectionHeader('Ceritakan kondisinya'),
            TextFormField(
              initialValue: vm.draftDescription,
              enabled: !vm.submitting,
              minLines: 3,
              maxLines: 6,
              onChanged: vm.setDescription,
              decoration: InputDecoration(
                labelText: 'Deskripsi',
                counterText: '$count/1000',
                errorText: count < 20 || count > 1000
                    ? 'Masukkan 20–1000 karakter.'
                    : null,
              ),
            ),
            IconLabel(
              icon: Icons.privacy_tip_outlined,
              text:
                  'Privasi foto dan lokasi: Hindari wajah/identitas dan titik rumah yang tak relevan.',
              color: AppColors.textMuted,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SectionHeader('Lokasi'),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Lokasi laporan',
                errorText:
                    vm.locationError ??
                    (vm.draftLatitude == null
                        ? 'Pilih lokasi laporan.'
                        : null),
              ),
              child: Text(
                vm.draftLatitude == null
                    ? 'Belum dipilih'
                    : '${vm.draftLatitude}, ${vm.draftLongitude}',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: vm.locating || vm.submitting ? null : vm.gps,
                  icon: const Icon(Icons.my_location),
                  label: Text(vm.locating ? 'Mencari lokasi…' : 'GPS sekali'),
                ),
                OutlinedButton.icon(
                  onPressed: vm.locating || vm.submitting
                      ? null
                      : () => Navigator.pop(context, true),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Pilih titik manual'),
                ),
                if (vm.canOpenSettings)
                  TextButton(
                    onPressed: vm.openSettings,
                    child: const Text('Buka Pengaturan'),
                  ),
              ],
            ),
            const SectionHeader('Kejadian terkait (opsional)'),
            Text(
              vm.draftEventId == null
                  ? 'Event terkait (opsional)'
                  : 'Terkait event: ${vm.draftEventId}',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: vm.submitting
                      ? null
                      : () {
                          setState(() => selectingEvent = !selectingEvent);
                          if (selectingEvent) vm.loadEvents();
                        },
                  child: Text(selectingEvent ? 'Tutup pilihan' : 'Pilih event'),
                ),
                if (vm.draftEventId != null)
                  TextButton(
                    onPressed: vm.submitting ? null : () => vm.setEvent(null),
                    child: const Text('Lepas'),
                  ),
              ],
            ),
            if (selectingEvent) ...[
              if (vm.eventsLoading) const LinearProgressIndicator(),
              if (vm.eventsError != null) ...[
                reportNotice(vm.eventsError!),
                TextButton(
                  onPressed: vm.loadEvents,
                  child: const Text('Coba lagi'),
                ),
              ],
              if (vm.events != null) ...[
                FreshnessBanner(sources: vm.eventsMeta!.sources),
                if (vm.events!.items.isEmpty) const Text('Belum ada event.'),
                for (final event in vm.events!.items)
                  OutlinedButton(
                    onPressed: vm.submitting
                        ? null
                        : () {
                            vm.setEvent(event.id);
                            setState(() => selectingEvent = false);
                          },
                    child: Text(event.title),
                  ),
              ],
            ],
            const SectionHeader('Foto (opsional)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final source in ReportPhotoSource.values)
                  OutlinedButton.icon(
                    onPressed: vm.submitting || vm.picking
                        ? null
                        : () => vm.pickPhoto(source),
                    icon: Icon(
                      source == ReportPhotoSource.camera
                          ? Icons.photo_camera_outlined
                          : Icons.photo_library_outlined,
                    ),
                    label: Text(
                      source == ReportPhotoSource.camera
                          ? 'Ambil foto'
                          : 'Pilih galeri',
                    ),
                  ),
              ],
            ),
            if (vm.picking) const LinearProgressIndicator(),
            if (photo != null) ...[
              Image.memory(
                photo.bytes,
                semanticLabel: 'Pratinjau foto laporan warga',
                height: 180,
                fit: BoxFit.contain,
              ),
              Text(
                '${(photo.byteLength / 1024).ceil()} KB · ${photo.width} × ${photo.height} px',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (simulated) const SimulationBadge(),
            ],
            if (vm.photoError != null) ...[
              reportNotice(vm.photoError!),
              OutlinedButton(
                onPressed: vm.picking
                    ? null
                    : () => vm.pickPhoto(vm.lastPhotoSource),
                child: const Text('Pilih Ulang'),
              ),
            ],
            if (photo != null || vm.photoError != null)
              TextButton(
                onPressed: vm.submitting || vm.picking ? null : vm.removePhoto,
                child: const Text('Hapus foto'),
              ),
            if (health.healthError != null) ...[
              reportNotice(health.healthError!),
              TextButton(
                onPressed: health.checkHealth,
                child: const Text('Periksa koneksi'),
              ),
            ],
            if (vm.contentChangedNotice != null)
              reportNotice(vm.contentChangedNotice!),
            if (vm.submitError != null) reportNotice(vm.submitError!),
            if (!vm.canSubmit && !vm.submitting && vm.submitError == null)
              Text(
                'Lengkapi kategori, deskripsi, lokasi, dan periksa foto sebelum mengirim.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            FilledButton(
              onPressed: vm.canSubmit && health.healthError == null
                  ? () async {
                      if (await vm.submit() &&
                          context.mounted &&
                          ModalRoute.of(context)?.isCurrent == true) {
                        Navigator.pop(context);
                      }
                    }
                  : null,
              child: Text(
                vm.submitting
                    ? 'Mengirim…'
                    : vm.lockedKey == null
                    ? 'Kirim'
                    : 'Coba kirim lagi',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }
}
