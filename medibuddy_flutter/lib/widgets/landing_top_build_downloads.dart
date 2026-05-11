import 'package:flutter/material.dart';

import '../theme/medisathi_colors.dart';
import 'android_release_download_panel.dart';
import 'app_release_download_launcher.dart';

/// Hero-adjacent app download chips: Android APK + placeholder iOS.
class LandingTopBuildDownloads extends StatelessWidget {
  const LandingTopBuildDownloads({
    super.key,
    required this.snapshotFuture,
    this.wrapAlignment = WrapAlignment.start,
  });

  static bool get visibleHere => AndroidReleaseDownloadPanel.offerApkHere;

  final Future<AndroidLatestSnapshot> snapshotFuture;
  final WrapAlignment wrapAlignment;

  @override
  Widget build(BuildContext context) {
    if (!visibleHere) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final loadingAlign = wrapAlignment == WrapAlignment.center ? Alignment.center : Alignment.centerLeft;

    return FutureBuilder<AndroidLatestSnapshot>(
      future: snapshotFuture,
      builder: (context, snap) {
        final release = snap.data?.release;

        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Wrap(
            alignment: wrapAlignment,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
                if (snap.connectionState != ConnectionState.done)
                  SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: Align(
                      alignment: loadingAlign,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: MediSathiColors.brandBlue),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Loading build info…',
                            style: theme.textTheme.labelMedium?.copyWith(color: MediSathiColors.mutedText, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (snap.connectionState == ConnectionState.done) ...[
                  if (release != null && release.platform.toLowerCase() == 'android')
                    FilledButton.tonalIcon(
                      onPressed: () => AppReleaseDownloadLauncher.launchAndroid(context, release),
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        'Download APK v${release.versionLabel}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xFF047857),
                        backgroundColor: const Color(0xFF052E16).withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('APK publishing soon'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MediSathiColors.mutedText,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  Tooltip(
                    message: 'iPhone & iPad build — coming soon.',
                    triggerMode: TooltipTriggerMode.longPress,
                    waitDuration: const Duration(milliseconds: 320),
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.phone_iphone_outlined, size: 18),
                      label: const Text('Download iOS (coming soon)', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MediSathiColors.mutedText,
                        side: BorderSide(color: MediSathiColors.brandBlue.withValues(alpha: 0.22)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        );
      },
    );
  }
}
