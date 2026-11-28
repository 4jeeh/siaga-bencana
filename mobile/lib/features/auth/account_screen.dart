import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/status_banners.dart';
import '../../core/widgets/ui_kit.dart';
import '../zone/zone_form.dart';
import '../zone/zone_view_model.dart';
import 'auth_view_model.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.editZone = false});
  final bool editZone;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _register = false;
  bool _rememberMe = true;
  bool _obscure = true;
  SessionCoordinator? _session;

  @override
  void initState() {
    super.initState();
    _passwordFocus.addListener(_onPasswordFocusChanged);
  }

  void _onPasswordFocusChanged() {
    if (mounted) setState(() {});
  }

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
    _passwordFocus.removeListener(_onPasswordFocusChanged);
    _passwordFocus.dispose();
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
      rememberMe: _rememberMe,
      displayName: _register ? _name.text : null,
    );
    if (mounted) _password.clear();
  }

  Future<void> _showForgotPasswordDialog() => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      scrollable: true,
      title: const Text('Lupa kata sandi?'),
      content: const Text(
        'Atur ulang kata sandi lewat email belum tersedia di versi ini. '
        'Hubungi admin aplikasi Siaga Bencana agar akun Anda dibantu diatur ulang, '
        'atau daftar dengan email lain.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Mengerti'),
        ),
      ],
    ),
  );

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
    if (session.restoring) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: AppSpace.m),
              Text('Memulihkan sesi...'),
            ],
          ),
        ),
      );
    }
    final isDuplicateEmail = vm.error?.code == 'EMAIL_ALREADY_REGISTERED';
    final editingZone = widget.editZone && session.isValid && session.verified;
    return Scaffold(
      appBar: AppBar(
        title: Text(editingZone ? 'Ubah Zona Pantau' : 'Siaga Bencana'),
        leading: editingZone
            ? IconButton(
                tooltip: 'Kembali',
                onPressed: () {
                  context.read<ZoneViewModel>().resetDraft();
                  context.go('/profile');
                },
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(editingZone ? AppSpace.l : AppSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: vm.healthError != null
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.l),
                            child: Card(
                              color: AppColors.error.withValues(alpha: 0.06),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpace.l),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    IconLabel(
                                      icon: Icons.cloud_off_outlined,
                                      text: vm.healthError!,
                                      color: AppColors.error,
                                    ),
                                    const SizedBox(height: AppSpace.s),
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
                          )
                        : vm.healthMeta?.isSimulated == true
                        ? const Padding(
                            padding: EdgeInsets.only(bottom: AppSpace.l),
                            child: SimulationBanner(),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (!editingZone) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: const SizedBox(
                          width: 64,
                          height: 64,
                          child: Icon(
                            Icons.shield_outlined,
                            size: 36,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpace.l),
                    Semantics(
                      header: true,
                      child: Text(
                        session.isValid
                            ? 'Zona pantau Anda'
                            : 'Siap, peduli, terhubung.',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: AppSpace.s),
                    Text(
                      'Informasi bencana dan laporan warga dalam satu aplikasi.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                  ],
                  if (session.message != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        session.message!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                    const SizedBox(height: AppSpace.l),
                  ],
                  if (session.isValid && session.verified) ...[
                    if (!editingZone) ...[
                      Text(
                        'Selamat datang, ${session.user!.displayName}.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpace.l),
                    ],
                    ZoneForm(editZone: widget.editZone),
                  ] else ...[
                    SegmentedButton<bool>(
                      style: SegmentedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('Masuk')),
                        ButtonSegment(value: true, label: Text('Daftar')),
                      ],
                      selected: {_register},
                      onSelectionChanged: vm.busy
                          ? null
                          : (values) {
                              vm.clearError();
                              setState(() {
                                _register = values.single;
                                _password.clear();
                              });
                            },
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
                            const SizedBox(height: AppSpace.l),
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
                          const SizedBox(height: AppSpace.l),
                          TextFormField(
                            key: const Key('password'),
                            controller: _password,
                            focusNode: _passwordFocus,
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
                              helperText: _register && _passwordFocus.hasFocus
                                  ? '10–128 karakter. Spasi ikut dihitung.'
                                  : null,
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
                          if (!_register)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: const Key('forgot-password'),
                                onPressed: vm.busy
                                    ? null
                                    : _showForgotPasswordDialog,
                                child: const Text('Lupa kata sandi?'),
                              ),
                            ),
                          const SizedBox(height: AppSpace.l),
                          if (isDuplicateEmail) ...[
                            Semantics(
                              liveRegion: true,
                              child: Card(
                                color: AppColors.primaryContainer,
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpace.l),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const IconLabel(
                                        icon: Icons.mark_email_read_outlined,
                                        text:
                                            'Email ini sudah terdaftar. Satu email hanya untuk satu akun — silakan masuk.',
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(height: AppSpace.m),
                                      FilledButton.tonal(
                                        key: const Key('switch-to-login'),
                                        onPressed: vm.busy
                                            ? null
                                            : () {
                                                vm.clearError();
                                                setState(() {
                                                  _register = false;
                                                  _password.clear();
                                                });
                                              },
                                        child: const Text('Pindah ke Masuk'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpace.m),
                          ] else if (vm.error != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                vm.error!.message,
                                style: const TextStyle(color: AppColors.error),
                              ),
                            ),
                            const SizedBox(height: AppSpace.m),
                          ],
                          if (vm.retrySeconds > 0) ...[
                            Text('Coba lagi dalam ${vm.retrySeconds} detik.'),
                            const SizedBox(height: AppSpace.m),
                          ],
                          if (!_register)
                            CheckboxListTile(
                              key: const Key('remember-me'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Tetap masuk'),
                              value: _rememberMe,
                              onChanged: vm.busy
                                  ? null
                                  : (value) => setState(
                                      () => _rememberMe = value ?? false,
                                    ),
                            ),
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
                          const SizedBox(height: AppSpace.l),
                          Text(
                            'Jika Tetap masuk aktif, sesi terenkripsi disimpan di perangkat hingga keluar atau masa berlaku habis.',
                            style: Theme.of(context).textTheme.bodySmall,
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
