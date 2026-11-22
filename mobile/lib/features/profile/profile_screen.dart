import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_coordinator.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/status_banners.dart';
import '../auth/auth_view_model.dart';
import '../notifications/local_notification_service.dart';
import '../notifications/notification_coordinator.dart';
import '../notifications/notification_dto.dart';
import '../notifications/notification_view_model.dart';
import '../zone/zone_view_model.dart';
import 'profile_view_model.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionCoordinator>().user;
    final profile = context.watch<ProfileViewModel>();
    final zoneVm = context.watch<ZoneViewModel>();
    final zone = zoneVm.savedZone;
    final channel = context.watch<NotificationCoordinator>();
    final history = context.watch<NotificationViewModel>();
    final simulated = context.watch<AuthViewModel>().healthMeta?.isSimulated == true ||
        channel.isSimulated || history.meta?.isSimulated == true;
    final permission = profile.permissionState;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: RefreshIndicator(onRefresh: profile.refreshProfile,
          child: SingleChildScrollView(physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
              if (simulated) const SimulationBanner(),
              _section(context, 'Akun', [
                Text(user?.displayName ?? ''), Text(user?.email ?? ''),
                Text(user?.role == 'admin' ? 'Admin' : 'Citizen'),
                if (profile.currentAccountError != null) Text(profile.currentAccountError!),
              ]),
              _section(context, 'Zona Pantau', [
                if (zoneVm.loading) const LinearProgressIndicator(),
                if (zone != null) ...[
                  Text('Lintang: ${zone.latitude}\nBujur: ${zone.longitude}'),
                  Text('Radius: ${zone.radiusKm} km'),
                  Text('Gempa & Potensi Tsunami: ${zone.notifyEarthquake ? "Aktif" : "Nonaktif"}'),
                  Text('Cuaca Ekstrem: ${zone.notifyWeather ? "Aktif" : "Nonaktif"}'),
                ] else if (!zoneVm.loading) const Text('Zona belum tersedia.'),
                if (zoneVm.error != null) ...[
                  Text(zoneVm.error!),
                  TextButton(onPressed: zoneVm.load, child: const Text('Coba Lagi')),
                ],
                FilledButton(onPressed: zoneVm.busy ? null : () {
                  zoneVm.resetDraft();
                  context.go('/account?edit=zone');
                }, child: const Text('Ubah Zona Pantau')),
              ]),
              _section(context, 'Kanal dan izin notifikasi', [
                _status('Status kanal', switch (channel.status) {
                  NotificationChannelStatus.sseActive => Icons.sensors,
                  NotificationChannelStatus.polling => Icons.sync,
                  NotificationChannelStatus.connecting => Icons.wifi_find,
                  NotificationChannelStatus.offline => Icons.cloud_off,
                  _ => Icons.pause_circle_outline,
                }, channel.statusLabel),
                if (channel.lastReceivedAt != null) ...[
                  const Text('Terakhir diterima'), _time(channel.lastReceivedAt!),
                ],
                if (channel.notice != null) Text(channel.notice!),
                _status('Izin notifikasi', permission == NotificationPermissionState.granted
                    ? Icons.notifications_active : Icons.notifications_none, switch (permission) {
                  NotificationPermissionState.granted => 'Diizinkan',
                  NotificationPermissionState.denied => 'Ditolak',
                  NotificationPermissionState.unknown => 'Belum diminta',
                }),
                if (permission != NotificationPermissionState.granted)
                  FilledButton(onPressed: profile.requestOsPermission, child: const Text('Aktifkan notifikasi')),
                if (permission == NotificationPermissionState.denied)
                  OutlinedButton(onPressed: profile.openOsNotificationSettings, child: const Text('Buka pengaturan OS')),
                if (profile.permissionNotice != null) Text(profile.permissionNotice!),
                const Text('Pembaruan otomatis saat aplikasi aktif. Tidak dijamin saat aplikasi ditutup.'),
              ]),
              _section(context, 'Riwayat Notifikasi', [
                Wrap(spacing: 8, children: [
                  Badge.count(count: history.unreadCount), const Text('Belum dibaca'),
                ]),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Hanya belum dibaca'),
                    value: history.unreadOnly, onChanged: history.setUnreadOnly),
                if (history.initialLoading || history.refreshing || history.loadingMore)
                  const LinearProgressIndicator(),
                if (history.error != null) ...[
                  Text(history.error!),
                  if (history.lastLoadedAt != null) ...[
                    const Text('Riwayat terakhir diperbarui'), _time(history.lastLoadedAt!),
                  ],
                  TextButton(onPressed: history.refresh, child: const Text('Coba Lagi')),
                ] else if (!history.initialLoading && history.items.isEmpty)
                  Text(history.unreadOnly ? 'Semua notifikasi sudah dibaca' : 'Belum ada notifikasi untuk akun ini'),
                if (history.notice != null) Text(history.notice!),
                for (final item in history.items) _historyTile(context, item),
                if (history.loadMoreError != null) Text(history.loadMoreError!),
                if (history.page?.nextOffset != null)
                  OutlinedButton(onPressed: history.loadingMore ? null : history.loadMore,
                      child: Text(history.loadMoreError == null ? 'Muat lebih banyak' : 'Coba muat lagi')),
              ]),
              OutlinedButton(onPressed: profile.logout, child: const Text('Keluar')),
            ]),
          ),
        ),
      ))),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          ...children,
        ],
      )));

  Widget _status(String name, IconData icon, String label) =>
      Semantics(label: '$name: $label', excludeSemantics: true,
        child: Wrap(spacing: 8, children: [Icon(icon), Text(label)]));

  Widget _time(DateTime time) => Tooltip(message: formatFullTooltipDateTime(time),
      child: Text(formatLocalDateTime(time)));

  Widget _historyTile(BuildContext context, NotificationDto item) {
    final quake = item.eventCategory == 'earthquake';
    return ListTile(contentPadding: EdgeInsets.zero, title: Text(item.title),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, children: [Icon(quake ? Icons.waves : Icons.thunderstorm_outlined),
          Text(quake ? 'Gempa' : 'Cuaca Ekstrem')]),
        _time(item.createdAt), Text(item.readAt == null ? 'Belum dibaca' : 'Dibaca'),
        if (item.isSimulated) const SimulationBadge(),
        if (!item.presentAsActiveAlert) Chip(label: Text(switch (item.currentLifecycleStatus) {
          'expired' => 'Kedaluwarsa', 'cancelled' => 'Dibatalkan', 'superseded' => 'Digantikan',
          'incomplete' || 'invalid_time' => 'Data belum lengkap', _ => 'Histori',
        })),
      ]),
      onTap: () async {
        final session = context.read<SessionCoordinator>();
        final generation = session.generation;
        await context.read<NotificationViewModel>().markRead(item);
        if (context.mounted && session.canNavigate && session.generation == generation) {
          context.push('/events/${Uri.encodeComponent(item.eventId)}');
        }
      },
    );
  }
}
