import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_release.dart';
import '../services/app_release_api.dart';

/// Shared fetch result for landing + panels (single request).
class AndroidLatestSnapshot {
  const AndroidLatestSnapshot({this.release, this.error});

  final AppRelease? release;
  final Object? error;

  bool get hasRelease => release != null;
}

/// Opens an Android artifact (direct apk_download_url or signed Storage URL fallback).
class AppReleaseDownloadLauncher {
  AppReleaseDownloadLauncher._();

  static Future<bool> launchAndroid(BuildContext context, AppRelease release) async {
    if (release.platform.toLowerCase() != 'android') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This link is not tagged as an Android build.')),
        );
      }
      return false;
    }
    try {
      final uri =
          release.resolvedLaunchUri ??
          await AppReleaseApi().fetchDownloadUri(release.id);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open download link.')),
        );
      }
      return ok;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
      return false;
    }
  }
}
