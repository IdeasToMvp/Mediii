import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/app_release.dart';
import '../services/app_release_api.dart';
import 'android_release_download_panel.dart';
import 'app_release_download_launcher.dart';

/// Fetches `GET /api/app-releases/latest` on first [HomeShell] frame and compares
/// `release.version_code` to [PackageInfo.buildNumber] (Android `versionCode`). Uses
/// `release.update_mandatory` for blocking vs optional UX (web is skipped).
abstract final class AppUpdatePrompt {
  static bool _scheduled = false;
  static const _prefDismissedVc = 'update_prompt_dismissed_version_code';

  /// Call from [HomeShell] after splash/onboarding — not from [MaterialApp] before the shell exists.
  static void scheduleWhenShellReady(BuildContext navigatorContext) {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigatorContext.mounted) return;
      unawaited(checkAndMaybePrompt(navigatorContext));
    });
  }

  static Future<void> checkAndMaybePrompt(BuildContext navigatorContext) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!AndroidReleaseDownloadPanel.offerApkHere) return;

    late final PackageInfo pkg;
    int localVc = 0;
    try {
      pkg = await PackageInfo.fromPlatform();
      localVc = int.tryParse(pkg.buildNumber.trim()) ?? 0;
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

    if (kDebugMode) {
      debugPrint(
        'AppUpdatePrompt: installed Android versionCode=$localVc < API latest=${release.versionCode}. '
        'Bump pubspec "version:" +build (after +) or use flutter build apk --build-number=${release.versionCode} '
        'so installed versionCode reaches the API.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final dismissedVc = prefs.getInt(_prefDismissedVc);
    if (!release.updateMandatory &&
        dismissedVc != null &&
        dismissedVc >= release.versionCode) {
      return;
    }

    if (!navigatorContext.mounted) return;

    final result = await showDialog<String>(
      context: navigatorContext,
      // Scrim / Android back close with result `null` → same prefs as "Later" for optional updates.
      barrierDismissible: !release.updateMandatory,
      useRootNavigator: true,
      builder: (dialogContext) {
        final pub = DateFormat.yMMMd().format(release.createdAt.toLocal());
        final detailStyle = Theme.of(dialogContext).textTheme.bodySmall
            ?.copyWith(
              height: 1.38,
              fontFamily: 'monospace',
              fontSize:
                  (Theme.of(dialogContext).textTheme.bodySmall?.fontSize ??
                      12) -
                  0.5,
            );
        final detailBuf = StringBuffer()
          ..writeln('INSTALLED (PackageInfo)')
          ..writeln('  app: ${pkg.appName}')
          ..writeln('  package: ${pkg.packageName}')
          ..writeln('  versionName: ${pkg.version}')
          ..writeln('  versionCode string: "${pkg.buildNumber}"')
          ..writeln('  versionCode parsed: $localVc')
          ..writeln('')
          ..writeln('API /api/app-releases/latest')
          ..writeln('  release id: ${release.id}')
          ..writeln('  version_label: ${release.versionLabel}')
          ..writeln('  version_code: ${release.versionCode}')
          ..writeln('  update_mandatory: ${release.updateMandatory}')
          ..writeln('  channel: ${release.channel}')
          ..writeln(
            '  created_at (UTC): ${release.createdAt.toUtc().toIso8601String()}',
          )
          ..writeln('  created_at (shown): $pub')
          ..writeln('')
          ..writeln('Client config')
          ..writeln('  AppConfig.apiBaseUrl: ${AppConfig.apiBaseUrl}');

        final alert = AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                color: Theme.of(dialogContext).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  release.updateMandatory
                      ? 'Required MediSathi update'
                      : 'New MediSathi build',
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  release.updateMandatory
                      ? 'This version must be installed to continue using the app safely.'
                      : 'Version ${release.versionLabel} is available.',
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'You are on build $localVc. Latest published build is ${release.versionCode} (released $pub).',
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.bodyMedium?.copyWith(height: 1.42),
                ),
                const SizedBox(height: 14),
                Text(
                  'Technical details (for debugging)',
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      dialogContext,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    detailBuf.toString(),
                    style: detailStyle,
                  ),
                ),
                if (release.releaseNotes.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'What’s new',
                    style: Theme.of(dialogContext).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    release.releaseNotes.trim(),
                    style: Theme.of(
                      dialogContext,
                    ).textTheme.bodySmall?.copyWith(height: 1.42),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!release.updateMandatory)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('later'),
                child: const Text('Later'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('download'),
              child: const Text('Download update'),
            ),
          ],
        );

        if (release.updateMandatory) {
          return PopScope(canPop: false, child: alert);
        }
        return alert;
      },
    );

    if (!release.updateMandatory && result != 'download') {
      await prefs.setInt(_prefDismissedVc, release.versionCode);
    }
    if (result == 'download' && navigatorContext.mounted) {
      await AppReleaseDownloadLauncher.launchAndroid(navigatorContext, release);
    }
  }
}
