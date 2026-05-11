import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_release.dart';
import '../services/app_release_api.dart';
import 'android_release_download_panel.dart';
import 'app_release_download_launcher.dart';

/// Update nudge when the published Android [AppRelease.versionCode] > installed [PackageInfo.buildNumber].
/// Backend [AppRelease.createdAt] is publish time; [AppRelease.updateMandatory] blocks "Later".
abstract final class AppUpdatePrompt {
  static bool _scheduled = false;
  static const _prefDismissedVc = 'update_prompt_dismissed_version_code';

  /// Queue after first frame once [navigatorKey]'s navigator is mounted.
  static void scheduleAfterSplash(GlobalKey<NavigatorState> navigatorKey) {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(maybeOffer(navigatorKey));
    });
  }

  static Future<void> maybeOffer(GlobalKey<NavigatorState> navigatorKey) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!AndroidReleaseDownloadPanel.offerApkHere) return;

    int localVc = 0;
    try {
      final info = await PackageInfo.fromPlatform();
      localVc = int.tryParse(info.buildNumber.trim()) ?? 0;
    } catch (_) {
      return;
    }

    AppRelease? latest;
    try {
      latest = await AppReleaseApi().fetchLatest(platform: 'android');
    } catch (_) {
      return;
    }
    if (latest == null) return;

    final release = latest;
    if (release.platform.toLowerCase() != 'android') return;
    if (release.versionCode <= localVc) return;

    final prefs = await SharedPreferences.getInstance();
    final dismissedVc = prefs.getInt(_prefDismissedVc);
    if (!release.updateMandatory && dismissedVc != null && dismissedVc >= release.versionCode) return;

    final nav = navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    final dlgCtx = nav.overlay?.context ?? navigatorKey.currentContext;
    if (dlgCtx == null || !dlgCtx.mounted) return;
    await showDialog<void>(
      context: dlgCtx,
      barrierDismissible: !release.updateMandatory,
      useRootNavigator: true,
      builder: (dialogContext) {
        final pub = DateFormat.yMMMd().format(release.createdAt.toLocal());
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update_alt_rounded, color: Theme.of(dialogContext).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(release.updateMandatory ? 'Required MediSathi update' : 'New MediSathi build'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  release.updateMandatory ?
                      'This version must be installed to continue using the app safely.'
                      : 'Version ${release.versionLabel} is available.',
                  style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'You are on build $localVc. Latest published build is ${release.versionCode} (released $pub).',
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(height: 1.42),
                ),
                if (release.releaseNotes.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'What’s new',
                    style: Theme.of(dialogContext).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    release.releaseNotes.trim(),
                    style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(height: 1.42),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!release.updateMandatory)
              TextButton(
                onPressed: () async {
                  await prefs.setInt(_prefDismissedVc, release.versionCode);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
                child: const Text('Later'),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (navigatorKey.currentContext?.mounted ?? false) {
                  await AppReleaseDownloadLauncher.launchAndroid(navigatorKey.currentContext!, release);
                }
              },
              child: const Text('Download update'),
            ),
          ],
        );
      },
    );
  }
}
