import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/prescription.dart';
import '../theme/medisathi_colors.dart';

Future<void> showPrescriptionDetailSheet(
  BuildContext context, {
  required Prescription p,
  required Future<void> Function() onEdit,
  required Future<void> Function() onDeleteConfirmed,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    barrierColor: Colors.black54,
    builder: (ctx) => PrescriptionDetailSheet(
      prescription: p,
      onEdit: () async {
        Navigator.of(ctx).pop();
        await onEdit();
      },
      onDeleteConfirmed: () async {
        Navigator.of(ctx).pop();
        await onDeleteConfirmed();
      },
    ),
  );
}

class PrescriptionDetailSheet extends StatefulWidget {
  const PrescriptionDetailSheet({
    super.key,
    required this.prescription,
    required this.onEdit,
    required this.onDeleteConfirmed,
  });

  final Prescription prescription;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDeleteConfirmed;

  @override
  State<PrescriptionDetailSheet> createState() => _PrescriptionDetailSheetState();
}

class _PrescriptionDetailSheetState extends State<PrescriptionDetailSheet> {
  static const _bucket = 'prescription-sources';
  static const _signTtl = 7200;

  String? _signedUrl;
  Object? _signError;
  bool _downloading = false;

  Prescription get p => widget.prescription;

  @override
  void initState() {
    super.initState();
    _signAttachment();
  }

  Future<void> _signAttachment() async {
    final path = p.sourceStoragePath?.trim();
    if (path == null || path.isEmpty) return;
    try {
      final url = await Supabase.instance.client.storage.from(_bucket).createSignedUrl(path, _signTtl);
      if (mounted) setState(() => _signedUrl = url);
    } catch (e, st) {
      debugPrint('sign url: $e\n$st');
      if (mounted) setState(() => _signError = e);
    }
  }

  bool get _isImageMime =>
      _looksLikeImageFromFilename((p.sourceOriginalName ?? '').toLowerCase()) ||
      (p.sourceMime ?? '').toLowerCase().startsWith('image/');

  static bool _looksLikeImageFromFilename(String n) {
    return n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.webp') ||
        n.endsWith('.gif') ||
        n.endsWith('.heic');
  }

  bool get _isPdfMime =>
      (p.sourceMime ?? '').toLowerCase() == 'application/pdf' ||
      (p.sourceOriginalName ?? '').toLowerCase().endsWith('.pdf');

  String get _friendlyFileName =>
      _sanitizeBaseName((p.sourceOriginalName ?? '').trim().isEmpty ? 'original' : p.sourceOriginalName!.trim());

  static String _sanitizeBaseName(String raw) {
    var s = raw.replaceAll(RegExp(r'[^\w\s\-\.]'), '').replaceAll(RegExp(r'\s+'), '_').trim();
    if (s.isEmpty || s == '.') s = 'document';
    return s.length > 100 ? '${s.substring(0, 100)}…' : s;
  }

  static String _stripExtension(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0) return name;
    return name.substring(0, i);
  }

  static String _fileExtensionLower(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i >= name.length - 1) return '';
    return name.substring(i + 1).toLowerCase().trim();
  }

  MimeType _mimeTypeForSaver() {
    final ext = _fileExtensionLower(_friendlyFileName);
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MimeType.jpeg;
      case 'png':
        return MimeType.png;
      case 'gif':
        return MimeType.gif;
      case 'webp':
        return MimeType.webp;
      case 'pdf':
        return MimeType.pdf;
      default:
        break;
    }
    final mime = (p.sourceMime ?? '').toLowerCase();
    if (mime == 'application/pdf') return MimeType.pdf;
    if (mime == 'image/png') return MimeType.png;
    if (mime == 'image/gif') return MimeType.gif;
    if (mime == 'image/webp') return MimeType.webp;
    if (mime == 'image/jpeg' || mime == 'image/jpg') return MimeType.jpeg;
    return MimeType.other;
  }

  Future<void> _openExternally() async {
    final u = _signedUrl;
    if (u == null || u.isEmpty) return;
    final uri = Uri.parse(u);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open in browser')));
    }
  }

  Future<void> _downloadOriginal() async {
    final u = _signedUrl;
    if (u == null || u.isEmpty) return;
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final uri = Uri.parse(u);
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw FormatException('Download failed (${resp.statusCode})');
      }
      final bytes = Uint8List.fromList(resp.bodyBytes);
      final saverMime = _mimeTypeForSaver();
      final extRaw = _fileExtensionLower(_friendlyFileName).replaceAll('.', '');
      final stem = extRaw.isNotEmpty ? _stripExtension(_friendlyFileName) : _friendlyFileName;
      final extParam = extRaw.isNotEmpty
          ? extRaw
          : (saverMime == MimeType.pdf
                ? 'pdf'
                : saverMime == MimeType.png
                    ? 'png'
                : saverMime == MimeType.gif
                        ? 'gif'
                : saverMime == MimeType.webp
                            ? 'webp'
                : saverMime == MimeType.jpeg
                                ? 'jpg'
                                    : 'bin');

      final customMime = (p.sourceMime ?? '').trim().isNotEmpty ? p.sourceMime!.trim() : 'application/octet-stream';

      if (saverMime == MimeType.other) {
        await FileSaver.instance.saveFile(
          name: stem,
          bytes: bytes,
          mimeType: MimeType.custom,
          customMimeType: customMime,
          fileExtension: extParam,
        );
      } else {
        await FileSaver.instance.saveFile(
          name: stem,
          bytes: bytes,
          mimeType: saverMime,
          fileExtension: extParam,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to device / Downloads')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final h = MediaQuery.sizeOf(context).height;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    Future<void> onDeleteTap() async {
      await widget.onDeleteConfirmed();
    }

    Widget attachmentBlock() {
      if ((p.sourceStoragePath ?? '').trim().isEmpty) {
        return Card(
          elevation: 0,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined, color: cs.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No original file was stored for this record.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: MediSathiColors.brandBlue.withValues(alpha: 0.2))),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: MediSathiColors.brandBlue.withValues(alpha: 0.06),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  Icon(Icons.attachment_rounded, size: 22, color: MediSathiColors.brandBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _friendlyFileName,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if ((p.sourceMime ?? '').isNotEmpty)
                    Chip(
                      label: Text(
                        (p.sourceMime!.length > 34 ? '${p.sourceMime!.substring(0, 31)}…' : p.sourceMime!),
                        style: theme.textTheme.labelSmall,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
            if (_signError != null && _signedUrl == null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 40, color: cs.error.withValues(alpha: 0.8)),
                    const SizedBox(height: 8),
                    Text('Could not load attachment preview.', style: theme.textTheme.bodySmall),
                  ],
                ),
              )
            else if (_signedUrl != null && _isImageMime && !_isPdfMime)
              GestureDetector(
                onTap: () => _showFullScreenImage(context, _signedUrl!),
                child: InteractiveViewer(
                  minScale: 0.85,
                  maxScale: 3.75,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image.network(
                      _signedUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (c, child, prog) {
                        if (prog == null) return child;
                        return ColoredBox(
                          color: cs.surfaceContainerHighest,
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      },
                      errorBuilder: (context, error, stack) => ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 48, color: cs.outline),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text('Preview unavailable', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (_signedUrl != null && (_isPdfMime || (!_isImageMime)))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    Icon(Icons.picture_as_pdf_rounded, size: 56, color: Colors.red.shade700),
                    const SizedBox(height: 8),
                    Text('PDF document', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 14),
                  ],
                ),
              )
            else
              SizedBox(height: 180, child: ColoredBox(color: cs.surfaceContainerHighest, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _signedUrl == null ? null : _openExternally,
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    label: const Text('Open'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: MediSathiColors.brandBlue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: (!_downloading && _signedUrl != null) ? _downloadOriginal : null,
                    icon: _downloading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download_rounded, size: 20),
                    label: Text(_downloading ? 'Saving…' : 'Download'),
                  ),
                  if (_isImageMime && !_isPdfMime && _signedUrl != null)
                    TextButton.icon(
                      onPressed: () => _showFullScreenImage(context, _signedUrl!),
                      icon: const Icon(Icons.zoom_in_rounded),
                      label: const Text('Fullscreen'),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: h * 0.92 - bottomPad * 0.25,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.isReport ? 'Report' : 'Prescription',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: MediSathiColors.brandBlue.withValues(alpha: 0.35)),
                      color: MediSathiColors.brandBlue.withValues(alpha: 0.09),
                    ),
                    child: Text(
                      (p.documentKind ?? 'prescription').toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + bottomPad),
                children: [
                  attachmentBlock(),
                  const SizedBox(height: 18),
                  Text('Summary', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _KvCard(
                    rows: [
                      _KvRow(Icons.person_outline_rounded, 'Patient', _orDash(p.patientName)),
                      _KvRow(Icons.medical_information_outlined, 'Doctor', _orDash(p.doctorName)),
                      _KvRow(Icons.calendar_month_outlined, 'Document date', _orDash(p.prescriptionDate)),
                      _KvRow(Icons.healing_outlined, 'Diagnosis', _orDash(p.diagnosis)),
                      if ((p.generalInstructions ?? '').trim().isNotEmpty)
                        _KvRow(Icons.notes_rounded, 'Instructions', p.generalInstructions!.trim()),
                      if ((p.title ?? '').trim().isNotEmpty) _KvRow(Icons.local_hospital_outlined, 'Title / clinic', p.title!.trim()),
                    ],
                  ),
                  if (p.patientFamilyMemberId != null && p.patientFamilyMemberId!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Linked to your household roster for reminders.',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (p.isReport && p.reportSummary != null && p.reportSummary!.isNotEmpty)
                    ExpansionTile(
                      initiallyExpanded: false,
                      tilePadding: EdgeInsets.zero,
                      title: Text('Report summary', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: SelectionArea(
                            child: Card(
                              elevation: 0,
                              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(
                                  const JsonEncoder.withIndent('  ').convert(p.reportSummary),
                                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.35),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  Text('Medications', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (p.isReport)
                    Text('Not applicable for pure report records.', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                  else if (p.medications.isEmpty)
                    Text('None listed.', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                  else
                    ...List.generate(p.medications.length, (i) {
                      final med = p.medications[i];
                      final name = med['name']?.toString() ?? '(unnamed)';
                      final parts = <String>[];
                      for (final k in ['dosage', 'frequency', 'duration', 'instructions']) {
                        final v = med[k]?.toString().trim();
                        if (v != null && v.isNotEmpty) parts.add('${k[0].toUpperCase()}${k.substring(1)}: $v');
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          elevation: 0,
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: MediSathiColors.brandBlue.withValues(alpha: 0.15),
                                      child: Text('${i + 1}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900, color: MediSathiColors.brandBlue)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                                  ],
                                ),
                                if (parts.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  for (final line in parts)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(line, style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  if ((p.extractionNotes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('AI extraction notes', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: SelectableText(p.extractionNotes!.trim(), style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                    const Spacer(),
                    if (!p.isReport)
                      TextButton(onPressed: () async => widget.onEdit(), child: const Text('Edit')),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onDeleteTap,
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _orDash(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? '—' : t;
  }

  Future<void> _showFullScreenImage(BuildContext ctx, String url) async {
    await showDialog<void>(
      context: ctx,
      builder: (dCtx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(child: Image.network(url, fit: BoxFit.contain)),
            ),
            Positioned(
              top: MediaQuery.paddingOf(dCtx).top + 8,
              left: 8,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.pop(dCtx),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KvRow {
  const _KvRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _KvCard extends StatelessWidget {
  const _KvCard({required this.rows});
  final List<_KvRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
        child: Column(
          children: rows.map((r) {
            return ListTile(
              leading: Icon(r.icon, size: 22, color: MediSathiColors.brandBlue.withValues(alpha: 0.9)),
              title: Text(r.label, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
              subtitle: SelectableText(r.value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.35)),
              isThreeLine: r.value.length > 80,
            );
          }).toList(),
        ),
      ),
    );
  }
}
