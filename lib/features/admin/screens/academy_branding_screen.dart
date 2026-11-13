import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/web/web_breakpoints.dart';
import '../../../data/remote/branding_service.dart';
import '../../../logic/auth_provider.dart';
import '../../../widgets/academy_logo.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/gradient_background.dart';
import '../../../widgets/web/web_nav_items.dart';
import '../../../widgets/web/web_shell.dart';
import '../../shared/academy_location.dart';

/// Admin: the academy's own identity — logo, name and contact details —
/// shown on every portal, the login screen and all generated documents.
class AcademyBrandingScreen extends StatefulWidget {
  const AcademyBrandingScreen({super.key});

  @override
  State<AcademyBrandingScreen> createState() => _AcademyBrandingScreenState();
}

class _AcademyBrandingScreenState extends State<AcademyBrandingScreen> {
  final _service = BrandingService();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  AcademyBranding? _saved;

  /// Pending logo change: new bytes, or `removeLogo` when clearing.
  Uint8List? _newLogo;
  String? _newLogoMime;
  bool _removeLogo = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final branding = await _service.getBranding();
      _saved = branding;
      _name.text = branding.name;
      _address.text = branding.address ?? '';
      _phone.text = branding.phone ?? '';
      _email.text = branding.email ?? '';
      _error = null;
    } catch (e) {
      // Fall back to the session's academy fields so the form stays usable.
      final user = context.read<AuthProvider>().currentUser;
      _name.text = user?.academyName ?? '';
      _address.text = user?.academyAddress ?? '';
      _phone.text = user?.academyPhone ?? '';
      _email.text = user?.academyEmail ?? '';
      _error = 'Could not load saved branding: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// What the logo will look like after saving (live preview).
  String? get _previewLogo {
    if (_removeLogo) return null;
    if (_newLogo != null) {
      return 'data:${_newLogoMime ?? 'image/png'};base64,'
          '${base64Encode(_newLogo!)}';
    }
    return _saved?.logo ??
        context.read<AuthProvider>().currentUser?.academyLogo;
  }

  bool get _hasLogo => _previewLogo != null && _previewLogo!.isNotEmpty;
  bool get _dirty => _newLogo != null || _removeLogo;

  Future<void> _pickLogo() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final mime = BrandingService.detectMimeType(bytes);
      if (mime == null) {
        setState(() => _error = 'Choose a PNG, JPEG or WebP image.');
        return;
      }
      if (bytes.length > BrandingService.maxLogoBytes) {
        setState(() => _error =
            'The logo must be under ${BrandingService.maxLogoBytes ~/ 1024} KB after resizing. Try a smaller image.');
        return;
      }
      setState(() {
        _newLogo = bytes;
        _newLogoMime = mime;
        _removeLogo = false;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not read that image: $e');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final branding = await _service.saveBranding(
        name: _name.text.trim(),
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        logoBytes: _newLogo,
        logoMimeType: _newLogoMime,
        removeLogo: _removeLogo,
      );
      _saved = branding;
      _newLogo = null;
      _newLogoMime = null;
      _removeLogo = false;
      if (!mounted) return;
      await context.read<AuthProvider>().applyBranding(branding);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Academy branding saved. It now appears on every portal and document.')));
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !WebBreakpoints.isCompact(context)) {
      return WebAppShell(
        title: 'Academy Branding',
        titleIcon: Icons.palette_rounded,
        navSections: buildAdminNavSections(context,
            onDashboard: () =>
                Navigator.of(context).popUntil((r) => r.isFirst)),
        activeNavId: 'branding',
        user: context.watch<AuthProvider>().currentUser,
        onLogout: () => performWebLogout(context),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760), child: _body()),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Academy Branding')),
      body: GradientBackground(child: SafeArea(child: _body())),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    final colors = context.appColors;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            'Your academy\'s own name and logo appear on every portal, the login screen, '
            'fee challans, reports and other documents. TaleemPlus stays a small attribution only.',
            style: TextStyle(
                color: colors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          _sectionLabel('LOGO'),
          _logoCard(),
          const SizedBox(height: 18),
          _sectionLabel('IDENTITY & CONTACT'),
          LabeledField(
            label: 'Academy name',
            hint: 'e.g. Al-Noor Science Academy',
            controller: _name,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Academy name is required'
                : null,
          ),
          LabeledField(
              label: 'Address',
              hint: 'Street, area, city',
              controller: _address),
          LabeledField(
              label: 'Phone',
              hint: '+92 300 1234567',
              controller: _phone,
              keyboardType: TextInputType.phone),
          LabeledField(
            label: 'Email',
            hint: 'office@youracademy.pk',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return null;
              return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(value)
                  ? null
                  : 'Enter a valid email address';
            },
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AcademyLocationEditorScreen())),
            icon: const Icon(Icons.add_location_alt_rounded, size: 18),
            label: const Text('Set location on map'),
          ),
          const SizedBox(height: 18),
          _sectionLabel('PREVIEW'),
          _preview(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_saving ? 'Saving…' : 'Save branding'),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1)),
      );

  Widget _logoCard() {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          AcademyLogo(
              logo: _previewLogo,
              academyName: _name.text,
              size: 72,
              radius: 14,
              showShadow: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasLogo
                      ? (_dirty
                          ? 'New logo selected (not saved yet)'
                          : 'Custom logo in use')
                      : 'No logo — the academy initials are shown instead',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                    'PNG, JPEG or WebP · square works best · resized to 512 px',
                    style: TextStyle(color: colors.textMuted, fontSize: 11.5)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  OutlinedButton.icon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(_hasLogo ? 'Change logo' : 'Upload logo'),
                  ),
                  if (_hasLogo)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _newLogo = null;
                        _newLogoMime = null;
                        _removeLogo = true;
                      }),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Remove'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.danger),
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How the identity will look in the portal header and on documents.
  Widget _preview() {
    final colors = context.appColors;
    final name = _name.text.trim().isEmpty ? 'Academy name' : _name.text.trim();
    final contact = [
      if (_address.text.trim().isNotEmpty) _address.text.trim(),
      if (_phone.text.trim().isNotEmpty) _phone.text.trim(),
      if (_email.text.trim().isNotEmpty) _email.text.trim(),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          AcademyLogo(
              logo: _previewLogo, academyName: name, size: 44, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                Text(contact.isEmpty ? 'Contact details appear here' : contact,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const PoweredByTaleemPlus(centered: false),
        ],
      ),
    );
  }
}
