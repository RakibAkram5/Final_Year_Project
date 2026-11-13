import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../logic/connection_status.dart';

/// Slim banner above the whole app while the device/backend is unreachable.
/// Mounted once through `MaterialApp.builder` so every screen shows it
/// without per-screen wiring. Disappears automatically when a request
/// succeeds again.
class ConnectionBanner extends StatelessWidget {
  final Widget child;
  const ConnectionBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConnectionStatus.instance,
      builder: (context, _) {
        final status = ConnectionStatus.instance;
        if (!status.isOffline) return child;
        final cached = status.lastServedFromCache != null;
        return Column(
          children: [
            Material(
              color: cached ? AppColors.warning : AppColors.danger,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_rounded,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cached
                              ? 'You are offline — showing the last saved data. Changes cannot be submitted until you reconnect.'
                              : 'You are offline — TaleemPlus cannot reach the server.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
                child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            )),
          ],
        );
      },
    );
  }
}
