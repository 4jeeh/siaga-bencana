import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PermissionOnboardingDialog extends StatelessWidget {
  const PermissionOnboardingDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    icon: const CircleAvatar(
      radius: 28,
      backgroundColor: AppColors.primaryContainer,
      child: Icon(
        Icons.notifications_active_outlined,
        color: AppColors.primary,
        size: 28,
      ),
    ),
    title: const Text('Tetap waspada tanpa repot'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BenefitRow(
          icon: Icons.sensors,
          title: 'Peringatan di area Anda',
          description:
              'Notifikasi muncul saat BMKG merilis info gempa atau cuaca ekstrem di sekitar titik pantau.',
        ),
        const SizedBox(height: AppSpace.m),
        const _BenefitRow(
          icon: Icons.my_location,
          title: 'Atur titik lebih cepat',
          description:
              'Lokasi hanya dipakai sekali untuk memilih titik pantau, tidak dilacak terus-menerus.',
        ),
        const SizedBox(height: AppSpace.l),
        Text(
          'Keduanya opsional dan bisa diubah kapan saja di Profil.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Nanti saja'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Izinkan'),
      ),
    ],
  );
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
      ),
      const SizedBox(width: AppSpace.m),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ],
  );
}
