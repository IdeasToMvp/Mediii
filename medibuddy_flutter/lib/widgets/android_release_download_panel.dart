import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_release.dart';
import '../services/app_release_api.dart';
import '../theme/medisathi_colors.dart';
import 'app_release_download_launcher.dart';

/// Shown on landing for web and Android — fetches latest public release from the API.
class AndroidReleaseDownloadPanel extends StatefulWidget {
  const AndroidReleaseDownloadPanel({super.key, this.sharedSnapshotFuture});

  /// When set (e.g. from [LandingScreen]), reuses the same Android latest fetch as [LandingTopBuildDownloads].
  final Future<AndroidLatestSnapshot>? sharedSnapshotFuture;

  static bool get offerApkHere {
    if (kIsWeb) return true;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  @override
  State<AndroidReleaseDownloadPanel> createState() => _AndroidReleaseDownloadPanelState();
}

class _AndroidReleaseDownloadPanelState extends State<AndroidReleaseDownloadPanel> {
  late final Future<_PanelState> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.sharedSnapshotFuture != null
        ? widget.sharedSnapshotFuture!.then(_snapshotToPanelState)
        : _defaultLoad();
  }

  Future<_PanelState> _snapshotToPanelState(AndroidLatestSnapshot snapshot) async {
    if (!AndroidReleaseDownloadPanel.offerApkHere) return const _Hidden();
    if (snapshot.error != null) return _Error(snapshot.error.toString());
    return _Ready(snapshot.release);
  }

  Future<_PanelState> _defaultLoad() async {
    if (!AndroidReleaseDownloadPanel.offerApkHere) {
      return const _Hidden();
    }
    try {
      final r = await AppReleaseApi().fetchLatest(platform: 'android');
      return _Ready(r);
    } catch (e) {
      return _Error(e.toString());
    }
  }

  Future<void> _openDownload(AppRelease r) async {
    setState(() => _downloadingId = r.id);
    try {
      await AppReleaseDownloadLauncher.launchAndroid(context, r);
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  String? _downloadingId;

  @override
  Widget build(BuildContext context) {
    if (!AndroidReleaseDownloadPanel.offerApkHere) return const SizedBox.shrink();
    return FutureBuilder<_PanelState>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _PanelShell(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final state = snap.data!;
        if (state is _Hidden) return const SizedBox.shrink();
        if (state is _Error) {
          final message = state.message;
          return _PanelShell(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Android build',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E3A5F),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Release information is temporarily unavailable.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MediSathiColors.mutedText),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                  ],
                ],
              ),
            ),
          );
        }
        if (state is _Ready) {
          final release = state.release;
          if (release != null) {
            return _ReleaseCard(
              release: release,
              downloading: _downloadingId == release.id,
              onDownload: () => _openDownload(release),
            );
          }
          return _PanelShell(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Android app',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E3A5F),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No public Android build is published yet. Check back soon.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MediSathiColors.mutedText),
                  ),
                ],
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

sealed class _PanelState {
  const _PanelState();
}

class _Hidden extends _PanelState {
  const _Hidden();
}

class _Error extends _PanelState {
  const _Error(this.message);
  final String message;
}

class _Ready extends _PanelState {
  const _Ready(this.release);
  final AppRelease? release;
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      elevation: 0,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
          boxShadow: [
            BoxShadow(
              color: MediSathiColors.brandBlue.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.downloading,
    required this.onDownload,
  });

  final AppRelease release;
  final bool downloading;
  final VoidCallback onDownload;

  static String _formatBytes(int b) {
    if (b < 1024) return '$b B';
    final kb = b / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  static String _shortSha(String hex) {
    if (hex.length <= 14) return hex;
    return '${hex.substring(0, 8)}…${hex.substring(hex.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat.yMMMd().add_jm().format(release.createdAt.toLocal());
    final chips = <Widget>[
      _InfoChip(icon: Icons.label_outline, label: release.versionLabel),
      _InfoChip(icon: Icons.developer_board_outlined, label: 'Build ${release.versionCode}'),
      if (release.apkByteSize != null) _InfoChip(icon: Icons.sd_storage_outlined, label: _formatBytes(release.apkByteSize!)),
    ];
    if (release.channel != 'production') {
      chips.add(_InfoChip(icon: Icons.science_outlined, label: release.channel.toUpperCase()));
    }

    return _PanelShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF052E16).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.android, color: Color(0xFF047857), size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Download for Android',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1E3A5F),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        release.apkFilename,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: MediSathiColors.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Published $dateStr',
                        style: theme.textTheme.labelSmall?.copyWith(color: MediSathiColors.mutedText.withValues(alpha: 0.9)),
                      ),
                      if (release.resolvedLaunchUri != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Hosted link — opens in your browser (Google Drive may show a scan warning before download).',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: MediSathiColors.mutedText.withValues(alpha: 0.88),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
            if (release.releaseNotes.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Release notes',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E3A5F),
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                release.releaseNotes.trim(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: MediSathiColors.mutedText,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if ((release.apkSha256Hex ?? '').isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'SHA-256  ${_shortSha(release.apkSha256Hex!)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: MediSathiColors.mutedText,
                      fontFamily: 'monospace',
                    ),
                  ),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    SelectableText(
                      release.apkSha256Hex!,
                      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.35),
                    ),
                  ],
                ),
              ),
            if ((release.apkSha256Hex ?? '').isNotEmpty) const SizedBox(height: 8),
            Text(
              'Install: open the APK and allow installs from this source when Android prompts. Same sign-in as web.',
              style: theme.textTheme.bodySmall?.copyWith(color: MediSathiColors.mutedText, height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: downloading ? null : onDownload,
                icon: downloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(downloading ? 'Preparing download…' : 'Download APK'),
                style: FilledButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFF047857),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MediSathiColors.brandBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MediSathiColors.brandBlue.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: MediSathiColors.brandBlue),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E3A5F),
                ),
          ),
        ],
      ),
    );
  }
}
