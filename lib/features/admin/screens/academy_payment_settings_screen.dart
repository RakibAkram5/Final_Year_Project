import 'dart:convert';
import '../../../core/theme/theme_extensions.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/remote/payment_service.dart';

class AcademyPaymentSettingsScreen extends StatefulWidget {
  const AcademyPaymentSettingsScreen({super.key});

  @override
  State<AcademyPaymentSettingsScreen> createState() =>
      _AcademyPaymentSettingsScreenState();
}

class _AcademyPaymentSettingsScreenState
    extends State<AcademyPaymentSettingsScreen> {
  final _service = PaymentService();
  final _provider = TextEditingController();
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _bankName = TextEditingController();
  final _accountNumber = TextEditingController();
  final _iban = TextEditingController();
  final _instructions = TextEditingController();
  final _picker = ImagePicker();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  String? _existingImage;
  XFile? _newImage;
  bool _removeImage = false;
  String? _error;
  List<Map<String, dynamic>> _pendingProofs = [];

  Uint8List? get _previewBytes {
    if (_removeImage) return null;
    if (_newImage != null) return null;
    if (_existingImage == null) return null;
    try {
      return base64Decode(_existingImage!);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _provider.dispose();
    _title.dispose();
    _details.dispose();
    _bankName.dispose();
    _accountNumber.dispose();
    _iban.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _service.getSettings();
      _provider.text = (settings['provider'] ?? '').toString();
      _title.text = (settings['accountTitle'] ?? '').toString();
      _details.text = (settings['accountDetails'] ?? '').toString();
      _bankName.text = (settings['bankName'] ?? '').toString();
      _accountNumber.text = (settings['bankAccountNumber'] ?? '').toString();
      _iban.text = (settings['bankIban'] ?? '').toString();
      _instructions.text = (settings['paymentInstructions'] ?? '').toString();
      _enabled = settings['enabled'] == true;
      _existingImage = settings['qrImageBase64'] as String?;
    } catch (error) {
      _error = error.toString();
    }
    try {
      _pendingProofs = await _service.pendingProofs();
    } catch (_) {
      // Settings remain usable if no proof review access is available.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reviewProof(Map<String, dynamic> proof, bool verified) async {
    final action = verified
        ? 'verify this receipt and mark the challan paid'
        : 'reject this receipt';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(verified ? 'Confirm payment' : 'Reject payment proof'),
        content: Text('Are you sure you want to $action?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(verified ? 'Verify payment' : 'Reject proof')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.reviewProof(proof['id'].toString(), verified: verified);
      _pendingProofs = await _service.pendingProofs();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _pickQr() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1400,
      maxHeight: 1400,
    );
    if (image == null) return;
    final name = image.name.toLowerCase();
    if (!(name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg'))) {
      setState(() => _error = 'Choose a PNG or JPEG image.');
      return;
    }
    if (await image.length() > 512 * 1024) {
      setState(() => _error = 'QR images must be under 512 KB.');
      return;
    }
    setState(() {
      _newImage = image;
      _removeImage = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_enabled && _details.text.trim().isEmpty) {
      setState(() => _error =
          'Add verified payment account details before enabling payment instructions.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'provider': _provider.text.trim(),
        'accountTitle': _title.text.trim(),
        'accountDetails': _details.text.trim(),
        'bankName': _bankName.text.trim(),
        'bankAccountNumber': _accountNumber.text.trim(),
        'bankIban': _iban.text.trim(),
        'paymentInstructions': _instructions.text.trim(),
        'enabled': _enabled,
      };
      if (_removeImage) {
        body['qrImageBase64'] = null;
      } else if (_newImage != null) {
        final bytes = await _newImage!.readAsBytes();
        final name = _newImage!.name.toLowerCase();
        body['qrMimeType'] = name.endsWith('.png') ? 'image/png' : 'image/jpeg';
        body['qrImageBase64'] = base64Encode(bytes);
      }
      await _service.saveSettings(body);
      if (_newImage != null) {
        _existingImage = base64Encode(await _newImage!.readAsBytes());
      } else if (_removeImage) {
        _existingImage = null;
      }
      _newImage = null;
      _removeImage = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment settings saved.')),
        );
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Academy Payment Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                    'Payment QR and account details are private to this academy. Verify them before enabling payment instructions.',
                    style: TextStyle(color: context.appColors.textSecondary)),
                const SizedBox(height: 20),
                TextField(
                    controller: _provider,
                    decoration:
                        const InputDecoration(labelText: 'Payment provider')),
                const SizedBox(height: 12),
                TextField(
                    controller: _title,
                    decoration:
                        const InputDecoration(labelText: 'Account title')),
                const SizedBox(height: 12),
                TextField(
                    controller: _details,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Account / wallet details')),
                const SizedBox(height: 20),
                Text('BANK ACCOUNT',
                    style: TextStyle(
                        color: context.appColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1)),
                const SizedBox(height: 8),
                TextField(
                    controller: _bankName,
                    decoration: const InputDecoration(labelText: 'Bank name')),
                const SizedBox(height: 12),
                TextField(
                    controller: _accountNumber,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Account number')),
                const SizedBox(height: 12),
                TextField(
                    controller: _iban,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'IBAN',
                        helperText:
                            'Checked with the IBAN checksum (PK IBANs have 24 characters).')),
                const SizedBox(height: 12),
                TextField(
                    controller: _instructions,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Payment instructions for parents',
                        hintText:
                            'e.g. Write the challan number as the reference.')),
                const SizedBox(height: 20),
                if (_newImage != null)
                  FutureBuilder<Uint8List>(
                    future: _newImage!.readAsBytes(),
                    builder: (_, snapshot) => snapshot.hasData
                        ? Image.memory(snapshot.data!,
                            height: 190, fit: BoxFit.contain)
                        : const SizedBox(
                            height: 100,
                            child: Center(child: CircularProgressIndicator())),
                  )
                else if (_previewBytes != null)
                  Image.memory(_previewBytes!, height: 190, fit: BoxFit.contain)
                else
                  Container(
                    height: 130,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        border: Border.all(color: context.appColors.border),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Text('No QR image uploaded'),
                  ),
                Wrap(spacing: 12, children: [
                  OutlinedButton.icon(
                      onPressed: _pickQr,
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('Upload / replace QR')),
                  if (_existingImage != null || _newImage != null)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _newImage = null;
                        _removeImage = true;
                      }),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove QR'),
                    ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable payment instructions'),
                  subtitle: const Text(
                      'Students can view this academy’s QR and account details.'),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
                const SizedBox(height: 28),
                Text(
                    'Payment proofs awaiting review (${_pendingProofs.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_pendingProofs.isEmpty)
                  const Text('No pending payment proofs.'),
                ..._pendingProofs.map((proof) {
                  final data = proof['imageBase64']?.toString() ?? '';
                  Uint8List? image;
                  try {
                    image = base64Decode(data);
                  } catch (_) {}
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${proof['studentName'] ?? 'Student'} · ${proof['challanNumber'] ?? ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text('Amount: Rs. ${proof['amount'] ?? ''}'),
                            if (image != null)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Image.memory(image,
                                      height: 180, fit: BoxFit.contain)),
                            Wrap(spacing: 8, children: [
                              FilledButton.icon(
                                  onPressed: () => _reviewProof(proof, true),
                                  icon: const Icon(Icons.verified_rounded),
                                  label: const Text('Verify payment')),
                              OutlinedButton.icon(
                                  onPressed: () => _reviewProof(proof, false),
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('Reject')),
                            ]),
                          ]),
                    ),
                  );
                }),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.danger)),
                  ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded),
                  label: const Text('Save payment settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
