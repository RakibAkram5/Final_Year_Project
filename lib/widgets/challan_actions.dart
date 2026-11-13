import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/theme_extensions.dart';
import '../data/models/fee_challan_model.dart';
import '../data/remote/challan_pdf_service.dart';
import '../logic/auth_provider.dart';

/// Download / print / share for a fee challan, shared by the admin, student
/// and parent screens so every entry point offers the same three options.
class ChallanActions {
  ChallanActions._();

  static Future<void> download(BuildContext context, FeeChallanModel c) => _run(
      context,
      'Download',
      () => ChallanPdfService.download(c,
          academy: context.read<AuthProvider>().currentUser));

  static Future<void> print(BuildContext context, FeeChallanModel c) => _run(
      context,
      'Print',
      () => ChallanPdfService.print(c,
          academy: context.read<AuthProvider>().currentUser));

  static Future<void> share(BuildContext context, FeeChallanModel c) => _run(
      context,
      'Share',
      () => ChallanPdfService.share(c,
          academy: context.read<AuthProvider>().currentUser));

  static Future<void> _run(
      BuildContext context, String action, Future<void> Function() job) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await job();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
          content: Text('$action failed: $e'),
          backgroundColor: AppColors.danger));
    }
  }

  /// Bottom sheet listing the three options (used from compact rows).
  static Future<void> showSheet(BuildContext context, FeeChallanModel c) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(children: [
                Expanded(
                  child: Text('Challan ${c.challanNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: ctx.appColors.textPrimary)),
                ),
                Text('Rs. ${c.totalAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ctx.appColors.accentText)),
              ]),
            ),
            _tile(
                ctx,
                Icons.download_rounded,
                kIsWeb ? 'Download PDF' : 'Save PDF',
                kIsWeb
                    ? 'Saves the challan to your downloads'
                    : 'Save to files or Drive', () {
              Navigator.pop(ctx);
              download(context, c);
            }),
            _tile(ctx, Icons.print_rounded, 'Print', 'Open the print dialog',
                () {
              Navigator.pop(ctx);
              print(context, c);
            }),
            _tile(ctx, Icons.share_rounded, 'Share',
                'Send via WhatsApp, email and more', () {
              Navigator.pop(ctx);
              share(context, c);
            }),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  static Widget _tile(BuildContext ctx, IconData icon, String title,
          String subtitle, VoidCallback onTap) =>
      ListTile(
        dense: true,
        leading: Icon(icon, color: ctx.appColors.accentText),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        onTap: onTap,
      );
}

/// Three compact outlined buttons (Download · Print · Share) for detail views.
class ChallanActionBar extends StatelessWidget {
  final FeeChallanModel challan;
  const ChallanActionBar({super.key, required this.challan});

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: context.appColors.accentText,
      side: BorderSide(
          color: context.appColors.accentText.withValues(alpha: 0.6)),
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    Widget button(IconData icon, String label, VoidCallback onPressed) =>
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
    return Row(children: [
      button(Icons.download_rounded, kIsWeb ? 'Download' : 'Save',
          () => ChallanActions.download(context, challan)),
      const SizedBox(width: 8),
      button(Icons.print_rounded, 'Print',
          () => ChallanActions.print(context, challan)),
      const SizedBox(width: 8),
      button(Icons.share_rounded, 'Share',
          () => ChallanActions.share(context, challan)),
    ]);
  }
}
