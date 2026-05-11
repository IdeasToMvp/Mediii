import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/document_upload_limits.dart';
import '../models/prescription.dart';
import '../theme/medisathi_colors.dart';

/// Prescriptions and lab reports in one place (second bottom-nav tab).
class DocumentsLibraryTab extends StatelessWidget {
  const DocumentsLibraryTab({
    super.key,
    required this.records,
    required this.onRefresh,
    required this.onOpen,
    required this.planSlug,
  });

  final List<Prescription> records;
  final Future<void> Function() onRefresh;
  final void Function(Prescription p) onOpen;
  final String planSlug;

  @override
  Widget build(BuildContext context) {
    final paid = DocumentUploadLimits.paidTier(planSlug);
    final dt = DateFormat.yMMMd();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Material(
            color: MediSathiColors.brandBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: MediSathiColors.brandBlue),
                      const SizedBox(width: 8),
                      Text(
                        'Upload limits (${DocumentUploadLimits.humanMaxSize()} max per file)',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: MediSathiColors.brandBlue,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DocumentUploadLimits.summaryLine(paid: paid),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black87, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: records.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Icon(Icons.folder_open_rounded, size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'No prescriptions or reports yet.\nUse Add to capture a document — we keep the original file when you save.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black45, height: 1.4),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final p = records[index];
                      final label = p.title?.trim().isNotEmpty == true
                          ? p.title!.trim()
                          : p.patientName?.trim().isNotEmpty == true
                              ? p.patientName!.trim()
                              : p.isReport
                                  ? 'Report'
                                  : 'Prescription';
                      final dateLine = p.createdAt != null ? dt.format(p.createdAt!.toLocal()) : '—';

                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onOpen(p),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SourceThumb(prescription: p),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Chip(
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            label:
                                                Text(p.isReport ? 'Report' : 'Prescription', style: const TextStyle(fontSize: 11)),
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          Text(dateLine, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                          if (p.sourceStoragePath != null)
                                            Icon(Icons.attach_file_rounded, size: 15, color: Colors.grey.shade600),
                                        ],
                                      ),
                                      if ((p.prescriptionDate ?? '').trim().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Document date: ${p.prescriptionDate}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _SourceThumb extends StatefulWidget {
  const _SourceThumb({required this.prescription});

  final Prescription prescription;

  @override
  State<_SourceThumb> createState() => _SourceThumbState();
}

class _SourceThumbState extends State<_SourceThumb> {
  late final Future<String?> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = _load();
  }

  Future<String?> _load() async {
    final path = widget.prescription.sourceStoragePath;
    final mime = (widget.prescription.sourceMime ?? '').toLowerCase();
    if (path == null || path.isEmpty) return null;
    if (!mime.startsWith('image/')) return null;
    try {
      return Supabase.instance.client.storage.from('prescription-sources').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mime = (widget.prescription.sourceMime ?? '').toLowerCase();
    final w = 56.0;
    final h = 56.0;
    if (mime == 'application/pdf' || (!mime.startsWith('image/') && widget.prescription.sourceStoragePath != null)) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.picture_as_pdf_rounded, color: Colors.red.shade700),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: w,
        height: h,
        child: FutureBuilder<String?>(
          future: _urlFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return ColoredBox(color: Colors.grey.shade200, child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
            }
            final u = snap.data;
            if (u == null || u.isEmpty) {
              return ColoredBox(
                color: MediSathiColors.brandBlue.withValues(alpha: 0.12),
                child: Icon(Icons.description_outlined, color: MediSathiColors.brandBlue),
              );
            }
            return Image.network(u, fit: BoxFit.cover, errorBuilder: (_, _, _) {
              return ColoredBox(
                color: MediSathiColors.brandBlue.withValues(alpha: 0.12),
                child: Icon(Icons.broken_image_outlined, color: MediSathiColors.brandBlue),
              );
            });
          },
        ),
      ),
    );
  }
}
