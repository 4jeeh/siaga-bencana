import 'package:flutter/material.dart';

class PermissionOnboardingDialog extends StatelessWidget {
  const PermissionOnboardingDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Izin lokasi dan notifikasi'),
    content: const Text('Lokasi membantu Anda memilih titik pantau. Notifikasi memberi tahu '
        'Anda saat ada peringatan dini BMKG di zona pantau. Kedua izin ini opsional.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nanti saja')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Izinkan')),
    ],
  );
}
