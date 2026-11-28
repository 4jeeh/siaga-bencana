import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/status_banners.dart';
import '../../core/widgets/ui_kit.dart';
import '../auth/auth_view_model.dart';
import '../notifications/local_notification_service.dart';
import '../notifications/notification_coordinator.dart';
import '../notifications/notification_dto.dart';
import '../notifications/notification_view_model.dart';
import '../zone/zone_view_model.dart';
import 'profile_view_model.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _initials(String? name) {
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts[1].substring(0, 1)}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionCoordinator>().user;
    final profile = context.watch<ProfileViewModel>();
    final zoneVm = context.watch<ZoneViewModel>();
    final zone = zoneVm.savedZone;
    final channel = context.watch<NotificationCoordinator>();
    final history = context.watch<NotificationViewModel>();
    final simulated =
        context.watch<AuthViewModel>().healthMeta?.isSimulated == true ||
        channel.isSimulated ||
        history.meta?.isSimulated == true;
    final permission = profile.permissionState;
    final channelLabel = switch (channel.status) {
      NotificationChannelStatus.sseActive => 'Notifikasi Real-Time Aktif',
      NotificationChannelStatus.polling => 'Pembaruan berkala aktif',
      NotificationChannelStatus.connecting => 'Menghubungkan…',
      NotificationChannelStatus.offline => 'Offline — menunggu koneksi',
      _ => channel.statusLabel,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              onRefresh: profile.refreshProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpace.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpace.m,
                  children: [
                    if (simulated) const SimulationBanner(),
                    _section(context, 'Akun', [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColors.primaryContainer,
                            child: ExcludeSemantics(
                              child: Text(
                                _initials(user?.displayName),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpace.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName ?? '',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  user?.email ?? '',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill(
                          icon: user?.role == 'admin'
                              ? Icons.admin_panel_settings_outlined
                              : Icons.person_outline,
                          label: user?.role == 'admin' ? 'Admin' : 'Warga',
                          foreground: AppColors.primary,
                          background: AppColors.primaryContainer,
                        ),
                      ),
                      if (profile.currentAccountError != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(profile.currentAccountError!),
                        ),
                    ]),
                    _section(context, 'Zona Pantau', [
                      if (zoneVm.loading) const LinearProgressIndicator(),
                      if (zone != null) ...[
                        Text(
                          'Lintang: ${zone.latitude} · Bujur: ${zone.longitude}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        IconLabel(
                          icon: Icons.adjust,
                          text: 'Radius: ${zone.radiusKm} km',
                        ),
                        IconLabel(
                          icon: Icons.waves,
                          text:
                              'Gempa & Potensi Tsunami: ${zone.notifyEarthquake ? "Aktif" : "Nonaktif"}',
                        ),
                        IconLabel(
                          icon: Icons.thunderstorm_outlined,
                          text:
                              'Cuaca Ekstrem: ${zone.notifyWeather ? "Aktif" : "Nonaktif"}',
                        ),
                      ] else if (!zoneVm.loading)
                        const Text('Zona belum tersedia.'),
                      if (zoneVm.error != null) ...[
                        Semantics(liveRegion: true, child: Text(zoneVm.error!)),
                        TextButton(
                          onPressed: zoneVm.load,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                      FilledButton(
                        onPressed: zoneVm.busy
                            ? null
                            : () {
                                zoneVm.resetDraft();
                                context.go('/account?edit=zone');
                              },
                        child: const Text('Ubah Zona Pantau'),
                      ),
                    ]),
                    _section(context, 'Kanal dan izin notifikasi', [
                      _status(
                        'Status kanal',
                        switch (channel.status) {
                          NotificationChannelStatus.sseActive => Icons.sensors,
                          NotificationChannelStatus.polling => Icons.sync,
                          NotificationChannelStatus.connecting =>
                            Icons.wifi_find,
                          NotificationChannelStatus.offline => Icons.cloud_off,
                          _ => Icons.pause_circle_outline,
                        },
                        channelLabel,
                      ),
                      if (channel.lastReceivedAt != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Terakhir diterima',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            _time(channel.lastReceivedAt!),
                          ],
                        ),
                      if (channel.notice != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(channel.notice!),
                        ),
                      _status(
                        'Izin notifikasi',
                        permission == NotificationPermissionState.granted
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                        switch (permission) {
                          NotificationPermissionState.granted => 'Diizinkan',
                          NotificationPermissionState.denied => 'Ditolak',
                          NotificationPermissionState.unknown =>
                            'Belum diminta',
                        },
                      ),
                      if (permission != NotificationPermissionState.granted)
                        FilledButton(
                          onPressed: profile.requestOsPermission,
                          child: const Text('Aktifkan notifikasi'),
                        ),
                      if (permission == NotificationPermissionState.denied)
                        OutlinedButton(
                          onPressed: profile.openOsNotificationSettings,
                          child: const Text('Buka pengaturan OS'),
                        ),
                      if (profile.permissionNotice != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(profile.permissionNotice!),
                        ),
                      Text(
                        'Pembaruan otomatis saat aplikasi aktif. Tidak dijamin saat aplikasi ditutup.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ]),
                    _section(context, 'Riwayat Notifikasi', [
                      Wrap(
                        spacing: AppSpace.s,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (history.unreadCount > 0)
                            Badge.count(count: history.unreadCount)
                          else
                            const StatusPill(
                              icon: Icons.mark_email_read_outlined,
                              label: '0',
                              foreground: AppColors.textMuted,
                              background: AppColors.surfaceVariant,
                            ),
                          const Text('Belum dibaca'),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Hanya belum dibaca'),
                        value: history.unreadOnly,
                        onChanged: history.setUnreadOnly,
                      ),
                      if (history.initialLoading ||
                          history.refreshing ||
                          history.loadingMore)
                        const LinearProgressIndicator(),
                      if (history.error != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(history.error!),
                        ),
                        if (history.lastLoadedAt != null) ...[
                          const Text('Riwayat terakhir diperbarui'),
                          _time(history.lastLoadedAt!),
                        ],
                        TextButton(
                          onPressed: history.refresh,
                          child: const Text('Coba Lagi'),
                        ),
                      ] else if (!history.initialLoading &&
                          history.items.isEmpty)
                        Text(
                          history.unreadOnly
                              ? 'Semua notifikasi sudah dibaca'
                              : 'Belum ada notifikasi untuk akun ini',
                        ),
                      if (history.notice != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(history.notice!),
                        ),
                      for (final item in history.items)
                        _historyTile(context, item),
                      if (history.loadMoreError != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(history.loadMoreError!),
                        ),
                      if (history.page?.nextOffset != null)
                        OutlinedButton(
                          onPressed: history.loadingMore
                              ? null
                              : history.loadMore,
                          child: Text(
                            history.loadMoreError == null
                                ? 'Muat lebih banyak'
                                : 'Coba muat lagi',
                          ),
                        ),
                    ]),
                    OutlinedButton.icon(
                      onPressed: profile.logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Keluar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.s,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...children,
            ],
          ),
        ),
      );

  Widget _status(String name, IconData icon, String label) => Semantics(
    label: '$name: $label',
    excludeSemantics: true,
    child: IconLabel(icon: icon, text: label),
  );

  Widget _time(DateTime time) => Tooltip(
    message: formatFullTooltipDateTime(time),
    child: Text(formatLocalDateTime(time)),
  );

  Widget _historyTile(BuildContext context, NotificationDto item) {
    final quake = item.eventCategory == 'earthquake';
    final unread = item.readAt == null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            quake ? Icons.waves : Icons.thunderstorm_outlined,
            color: AppColors.primary,
          ),
        ),
      ),
      title: Text(item.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            quake ? 'Gempa' : 'Cuaca Ekstrem',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          _time(item.createdAt),
          IconLabel(
            icon: unread ? Icons.fiber_manual_record : Icons.done_all,
            text: unread ? 'Belum dibaca' : 'Dibaca',
            color: unread ? AppColors.primary : AppColors.textMuted,
            iconSize: 14,
          ),
          if (item.isSimulated) const SimulationBadge(),
          if (!item.presentAsActiveAlert)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: StatusPill(
                  icon: Icons.history,
                  label: switch (item.currentLifecycleStatus) {
                    'expired' => 'Kedaluwarsa',
                    'cancelled' => 'Dibatalkan',
                    'superseded' => 'Digantikan',
                    'incomplete' || 'invalid_time' => 'Data belum lengkap',
                    _ => 'Histori',
                  },
                  foreground: AppColors.textMuted,
                  background: AppColors.surfaceVariant,
                ),
              ),
            ),
        ],
      ),
      onTap: () async {
        final session = context.read<SessionCoordinator>();
        final generation = session.generation;
        await context.read<NotificationViewModel>().markRead(item);
        if (context.mounted &&
            session.canNavigate &&
            session.generation == generation) {
          context.push('/events/${Uri.encodeComponent(item.eventId)}');
        }
      },
    );
  }
}
