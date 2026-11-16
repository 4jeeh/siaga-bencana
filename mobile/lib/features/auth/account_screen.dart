import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import 'auth_view_model.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _obscure = true;
  SessionCoordinator? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session ??= context.read<SessionCoordinator>()
      ..addListener(_sessionChanged);
  }

  void _sessionChanged() {
    _password.clear();
    if (!_session!.isValid) {
      _email.clear();
      _name.clear();
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_sessionChanged);
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthViewModel vm) async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await vm.submit(
      email: _email.text,
      password: _password.text,
      displayName: _register ? _name.text : null,
    );
    if (mounted) _password.clear();
  }

  String? _serverFieldError(AuthViewModel vm, String name) {
    final fields = vm.error?.details?['fields'];
    if (fields is List &&
        fields.any((Object? value) => value is Map && value['field'] == name)) {
      return 'Periksa kembali isian ini.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final session = context.watch<SessionCoordinator>();
    return Scaffold(
      appBar: AppBar(title: const Text('Siaga Bencana')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 48,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    session.isValid
                        ? 'Zona pantau Anda'
                        : 'Siap, peduli, terhubung.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Informasi bencana dan laporan warga dalam satu aplikasi.',
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    liveRegion: true,
                    child: Card(
                      color: AppColors.surfaceVariant,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vm.checkingHealth
                                  ? 'Memeriksa konektivitas API…'
                                  : vm.healthError ??
                                        (vm.healthMeta == null
                                            ? 'Status API belum diperiksa.'
                                            : vm.healthMeta!.isSimulated
                                            ? 'SIMULASI — data demo'
                                            : 'API terhubung • ${vm.healthMeta!.mode == 'local_live' ? 'Lokal' : 'Produksi'}'),
                              style: TextStyle(
                                color: vm.healthMeta?.isSimulated == true
                                    ? AppColors.simulation
                                    : AppColors.textPrimary,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: vm.checkingHealth
                                  ? null
                                  : vm.checkHealth,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Periksa koneksi'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (session.message != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        session.message!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (session.isValid && session.verified) ...[
                    Text('Selamat datang, ${session.user!.displayName}.'),
                    const SizedBox(height: 16),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              color: AppColors.primary,
                            ),
                            SizedBox(height: 12),
                            Text('UI-01c • Atur Zona Pantau'),
                            SizedBox(height: 8),
                            Text('Dalam pengembangan Slice berikutnya'),
                            SizedBox(height: 8),
                            Text(
                              'Pemilihan titik pantau dan radius tersedia pada Slice 2. '
                              'Akun Anda sudah berhasil masuk.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () {
                        vm.clearError();
                        session.clear();
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Keluar'),
                    ),
                  ] else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Masuk'),
                          selected: !_register,
                          onSelected: vm.busy
                              ? null
                              : (_) {
                                  vm.clearError();
                                  setState(() {
                                    _register = false;
                                    _password.clear();
                                  });
                                },
                        ),
                        ChoiceChip(
                          label: const Text('Daftar'),
                          selected: _register,
                          onSelected: vm.busy
                              ? null
                              : (_) {
                                  vm.clearError();
                                  setState(() {
                                    _register = true;
                                    _password.clear();
                                  });
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_register) ...[
                            TextFormField(
                              key: const Key('name'),
                              controller: _name,
                              enabled: !vm.busy,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Nama tampilan',
                                errorText: _serverFieldError(
                                  vm,
                                  'display_name',
                                ),
                              ),
                              validator: (value) =>
                                  (value ?? '').trim().isEmpty ||
                                      (value ?? '').trim().length > 80
                                  ? 'Nama harus 1–80 karakter.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            key: const Key('email'),
                            controller: _email,
                            enabled: !vm.busy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              errorText: _serverFieldError(vm, 'email'),
                            ),
                            validator: (value) =>
                                (value ?? '').trim().length > 254 ||
                                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                        .hasMatch((value ?? '').trim())
                                ? 'Masukkan alamat email yang valid.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('password'),
                            controller: _password,
                            enabled: !vm.busy,
                            obscureText: _obscure,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (!vm.busy && vm.retrySeconds == 0) _submit(vm);
                            },
                            decoration: InputDecoration(
                              labelText: 'Kata sandi',
                              helperText:
                                  '10–128 karakter. Spasi ikut dihitung.',
                              helperMaxLines: 3,
                              errorText: _serverFieldError(vm, 'password'),
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? 'Tampilkan kata sandi'
                                    : 'Sembunyikan kata sandi',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                (value ?? '').length < 10 ||
                                    (value ?? '').length > 128
                                ? 'Kata sandi harus 10–128 karakter.'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          if (vm.error != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                vm.error!.message,
                                style: const TextStyle(color: AppColors.error),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (vm.retrySeconds > 0) ...[
                            Text('Coba lagi dalam ${vm.retrySeconds} detik.'),
                            const SizedBox(height: 12),
                          ],
                          FilledButton(
                            key: const Key('submit'),
                            onPressed: vm.busy || vm.retrySeconds > 0
                                ? null
                                : () => _submit(vm),
                            child: Text(
                              vm.busy
                                  ? 'Memproses…'
                                  : _register
                                  ? 'Buat akun'
                                  : 'Masuk',
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Sesi disimpan hanya selama aplikasi berjalan.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
