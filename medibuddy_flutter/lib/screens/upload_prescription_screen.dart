import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/document_upload_limits.dart';
import '../models/prescription.dart';
import '../services/medibuddy_api.dart';

class UploadPrescriptionScreen extends StatefulWidget {
  const UploadPrescriptionScreen({
    super.key,
    this.planSlug = 'free',
    this.uploadMaxBytes = DocumentUploadLimits.maxBytes,
  });

  final String planSlug;
  final int uploadMaxBytes;

  @override
  State<UploadPrescriptionScreen> createState() => _UploadPrescriptionScreenState();
}

class _UploadPrescriptionScreenState extends State<UploadPrescriptionScreen> {
  final _picker = ImagePicker();
  final _api = MediBuddyApi();

  final List<XFile> _files = [];
  int _cursor = 0;

  bool _analyzing = false;
  bool _saving = false;
  Map<String, dynamic>? _analysis;

  final _title = TextEditingController();
  final _patient = TextEditingController();
  final _doctor = TextEditingController();
  final _date = TextEditingController();
  final _diagnosis = TextEditingController();
  final _general = TextEditingController();
  final _notes = TextEditingController();
  final List<_MedRow> _meds = [];

  bool get _paid => DocumentUploadLimits.paidTier(widget.planSlug);

  XFile? get _active => _files.isNotEmpty && _cursor < _files.length ? _files[_cursor] : null;

  bool get _currentIsPdf {
    final f = _active;
    if (f == null) return false;
    final n = f.name.toLowerCase();
    return n.endsWith('.pdf');
  }

  bool get _isAnalysisReport =>
      _analysis != null &&
      (_analysis!['document_kind'] ?? 'prescription').toString().toLowerCase().trim() == 'report';

  @override
  void initState() {
    super.initState();
    _meds.add(_MedRow());
  }

  @override
  void dispose() {
    _title.dispose();
    _patient.dispose();
    _doctor.dispose();
    _date.dispose();
    _diagnosis.dispose();
    _general.dispose();
    _notes.dispose();
    for (final m in _meds) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> _assertFileSize(XFile f) async {
    final len = await f.length();
    if (len > widget.uploadMaxBytes) {
      throw Exception('File is too large (max ${DocumentUploadLimits.humanMaxSize()}).');
    }
  }

  /// One batch must be all images or all PDFs (server / AI constraints).
  bool _homogeneous(List<XFile> xs) {
    if (xs.isEmpty) return true;
    final pdfs = xs.where((e) => e.name.toLowerCase().endsWith('.pdf')).length;
    return pdfs == 0 || pdfs == xs.length;
  }

  Future<void> _setQueue(List<XFile> next) async {
    for (final f in next) {
      await _assertFileSize(f);
    }
    if (!_homogeneous(next)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick either photos only or PDFs only in one batch — not mixed.')),
      );
      return;
    }
    if (!_paid && next.length > 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Free plan: one image at a time.')),
      );
      return;
    }
    setState(() {
      _files
        ..clear()
        ..addAll(next);
      _cursor = 0;
      _analysis = null;
      _clearEditors();
    });
  }

  Future<void> _pickFreeGallery() async {
    final img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (img == null) return;
    await _setQueue([img]);
  }

  Future<void> _pickFreeCamera() async {
    final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 100);
    if (img == null) return;
    await _setQueue([img]);
  }

  Future<void> _pickPaidPhotos() async {
    final list = await _picker.pickMultiImage(imageQuality: 100);
    if (list.isEmpty) return;
    await _setQueue(list);
  }

  Future<void> _pickPaidPdfs() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: kIsWeb,
    );
    if (r == null || r.files.isEmpty) return;
    final out = <XFile>[];
    for (final pf in r.files) {
      if (pf.path != null && pf.path!.isNotEmpty) {
        out.add(XFile(pf.path!));
      } else if (pf.bytes != null) {
        out.add(XFile.fromData(pf.bytes!, name: pf.name.isNotEmpty ? pf.name : 'document.pdf'));
      }
    }
    if (out.isEmpty) return;
    await _setQueue(out);
  }

  Future<void> _pickPaidCamera() async {
    final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 100);
    if (img == null) return;
    await _setQueue([img]);
  }

  void _showPaidPickerSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos (multi-select)'),
              subtitle: const Text('JPEG, PNG, WebP, GIF — processed one after another'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPaidPhotos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF files'),
              subtitle: const Text('Stored as-is; add details manually (no AI on PDF yet)'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPaidPdfs();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPaidCamera();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _clearEditors() {
    _title.clear();
    _patient.clear();
    _doctor.clear();
    _date.clear();
    _diagnosis.clear();
    _general.clear();
    _notes.clear();
    for (final m in _meds) {
      m.dispose();
    }
    _meds.clear();
    _meds.add(_MedRow());
  }

  void _applyAnalysis(Map<String, dynamic> a) {
    _patient.text = (a['patient_name'] ?? '').toString();
    _doctor.text = (a['doctor_name'] ?? '').toString();
    _date.text = (a['prescription_date'] ?? '').toString();
    _diagnosis.text = (a['diagnosis'] ?? '').toString();
    _general.text = (a['general_instructions'] ?? '').toString();
    _notes.text = (a['extraction_notes'] ?? '').toString();

    final clinic = (a['clinic_or_hospital'] ?? '').toString().trim();
    if (clinic.isNotEmpty) {
      _title.text = clinic;
    }

    for (final m in _meds) {
      m.dispose();
    }
    _meds.clear();

    final meds = a['medications'];
    if (meds is List) {
      for (final item in meds) {
        if (item is! Map) continue;
        final row = _MedRow();
        final m = Map<String, dynamic>.from(item);
        row.name.text = (m['name'] ?? '').toString();
        row.dosage.text = (m['dosage'] ?? '').toString();
        row.frequency.text = (m['frequency'] ?? '').toString();
        row.duration.text = (m['duration'] ?? '').toString();
        row.instructions.text = (m['instructions'] ?? '').toString();
        _meds.add(row);
      }
    }
    if (_meds.isEmpty) {
      _meds.add(_MedRow());
    }
  }

  Future<void> _analyze() async {
    final f = _active;
    if (f == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a document first.')));
      return;
    }
    if (_currentIsPdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI analysis works on photos. PDFs are stored as originals — fill the form and save.')),
      );
      return;
    }
    setState(() => _analyzing = true);
    try {
      final res = await _api.analyzeImage(f);
      final analysis = res['analysis'];
      if (analysis is! Map<String, dynamic>) {
        throw const FormatException('Missing analysis object');
      }
      setState(() {
        _analysis = analysis;
        _applyAnalysis(analysis);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: ${_shortError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<Map<String, dynamic>> _uploadActiveOriginal() async {
    final f = _active;
    if (f == null) throw StateError('No file');
    final meta = await _api.uploadPrescriptionSource(f);
    return meta;
  }

  void _advanceOrPopAfterSave() {
    if (_cursor + 1 < _files.length) {
      setState(() {
        _cursor++;
        _analysis = null;
        _clearEditors();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved. Now review document ${_cursor + 1} of ${_files.length}.')),
        );
      }
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _savePdfManual() async {
    final f = _active;
    if (f == null) return;

    setState(() => _saving = true);
    try {
      final up = await _uploadActiveOriginal();
      final path = up['storage_path']?.toString();
      final mime = up['mime']?.toString() ?? 'application/pdf';
      final orig = up['original_name']?.toString() ?? f.name;
      if (path == null || path.isEmpty) throw const FormatException('Missing storage_path');

      final title = _title.text.trim().isNotEmpty ? _title.text.trim() : orig;

      final res = await _api.createPrescription(
        source: 'manual',
        title: title,
        patientName: _patient.text,
        doctorName: _doctor.text,
        prescriptionDate: _date.text,
        diagnosis: _diagnosis.text,
        generalInstructions: _general.text,
        extractionNotes: _notes.text,
        medications: const [],
        rawAnalysis: null,
        documentKind: 'prescription',
        reportSummary: null,
        sourceStoragePath: path,
        sourceMime: mime,
        sourceOriginalName: orig,
      );

      if (!mounted) return;
      final buf = StringBuffer('PDF saved with original file attached.');
      final pf = res['patient_family_resolution'];
      if (pf is Map && pf['mode'] != null) {
        buf.write(' (${pf['mode']})');
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(buf.toString())));
      _advanceOrPopAfterSave();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: ${_shortError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAnalyzed() async {
    if (_analysis == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Run analysis before saving (AI-filled fields should be reviewed).')),
      );
      return;
    }
    final kind = (_analysis?['document_kind'] ?? 'prescription').toString().toLowerCase().trim();
    final isReport = kind == 'report';

    final meds = <Map<String, dynamic>>[];
    if (!isReport) {
      for (final row in _meds) {
        final name = row.name.text.trim();
        if (name.isEmpty) continue;
        meds.add(
          PrescriptionMedication(
            name: name,
            dosage: _nullIfEmpty(row.dosage.text),
            frequency: _nullIfEmpty(row.frequency.text),
            duration: _nullIfEmpty(row.duration.text),
            instructions: _nullIfEmpty(row.instructions.text),
          ).toApiMap(),
        );
      }
      if (meds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one medication name after review.')),
        );
        return;
      }
    }

    Map<String, dynamic>? reportSummary;
    if (isReport) {
      final raw = _analysis!['report_summary'];
      if (raw is Map<String, dynamic>) {
        reportSummary = Map<String, dynamic>.from(raw);
      } else if (raw is Map) {
        reportSummary = Map<String, dynamic>.from(raw);
      } else {
        reportSummary = {};
      }
    }

    setState(() => _saving = true);
    try {
      final up = await _uploadActiveOriginal();
      final path = up['storage_path']?.toString();
      final mime = up['mime']?.toString();
      final orig = up['original_name']?.toString() ?? (_active?.name ?? 'upload');
      if (path == null || path.isEmpty) throw const FormatException('Missing storage_path');

      final res = await _api.createPrescription(
        source: 'analyzed',
        title: _title.text,
        patientName: _patient.text,
        doctorName: _doctor.text,
        prescriptionDate: _date.text,
        diagnosis: _diagnosis.text,
        generalInstructions: _general.text,
        extractionNotes: _notes.text,
        medications: isReport ? [] : meds,
        rawAnalysis: _analysis,
        documentKind: isReport ? 'report' : 'prescription',
        reportSummary: reportSummary,
        sourceStoragePath: path,
        sourceMime: mime,
        sourceOriginalName: orig,
      );

      if (!mounted) return;

      final buf = StringBuffer('Saved with original attachment.');
      final pf = res['patient_family_resolution'];
      if (!isReport && pf is Map) {
        final mode = pf['mode']?.toString() ?? '';
        if (mode == 'matched') {
          buf.write(' Linked patient to a matching family member.');
        } else if (mode == 'random') {
          buf.write(' Patient name had no match — linked reminders to a random household profile.');
        } else if (mode == 'explicit') {
          buf.write(' Patient linked to the selected household profile.');
        } else if (mode == 'none') {
          buf.write(' No household profile match (empty name or no members). Reminders attach to your account.');
        }
      }

      final reminders = res['reminders'];
      if (!isReport && reminders is Map) {
        final gen = reminders['generated'];
        if (gen is int && gen > 0) {
          buf.write(' Created $gen reminder schedule(s).');
        } else if (reminders['error'] != null) {
          buf.write(' Reminders: ${reminders['error']}');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(buf.toString())));
      _advanceOrPopAfterSave();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: ${_shortError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _shortError(Object e) {
    if (e is MediBuddyApiException) {
      try {
        final m = jsonDecode(e.body);
        if (m is Map && m['error'] != null) return m['error'].toString();
      } catch (_) {}
    }
    return e.toString();
  }

  String? _nullIfEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add prescription or report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            DocumentUploadLimits.summaryLine(paid: _paid),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 6),
          Text(
            'Max ${DocumentUploadLimits.humanMaxSize()} per file — files are stored exactly as uploaded.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Document ${_files.isEmpty ? 0 : _cursor + 1} of ${_files.length}: ${_active?.name ?? '—'}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          if (_paid) ...[
            FilledButton.tonalIcon(
              onPressed: _showPaidPickerSheet,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Choose files (Pro)'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickPaidCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFreeCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFreeGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (_active != null && !_currentIsPdf) ...[
            FutureBuilder<Uint8List>(
              future: _active!.readAsBytes(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(snap.data!, fit: BoxFit.contain, height: 220),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          if (_currentIsPdf) ...[
            Card(
              child: ListTile(
                leading: Icon(Icons.picture_as_pdf_rounded, color: Colors.red.shade700, size: 36),
                title: const Text('PDF selected'),
                subtitle: const Text('Fill optional fields below, then save — the PDF is kept as your original.'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_active != null && !_currentIsPdf)
            FilledButton.icon(
              onPressed: (_analyzing || _saving) ? null : _analyze,
              icon: _analyzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(_analyzing ? 'Analyzing…' : 'Analyze with AI'),
            ),
          if (_currentIsPdf) ...[
            const SizedBox(height: 8),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title (defaults to file name)')),
            const SizedBox(height: 10),
            TextField(controller: _patient, decoration: const InputDecoration(labelText: 'Patient name (optional)')),
            const SizedBox(height: 10),
            TextField(controller: _date, decoration: const InputDecoration(labelText: 'Record date (optional)')),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _savePdfManual,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_saving ? 'Saving…' : 'Save PDF to library'),
            ),
          ],
          if (_analysis != null && !_currentIsPdf) ...[
            const SizedBox(height: 22),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: Icon(
                  ((_analysis!['document_kind'] ?? 'prescription').toString().toLowerCase()) == 'report'
                      ? Icons.analytics_outlined
                      : Icons.medication_outlined,
                  size: 18,
                ),
                label: Text(
                  ((_analysis!['document_kind'] ?? 'prescription').toString().toLowerCase()) == 'report'
                      ? 'Detected: report / labs'
                      : 'Detected: prescription',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Review & edit', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title / clinic name')),
            const SizedBox(height: 10),
            TextField(controller: _patient, decoration: const InputDecoration(labelText: 'Patient name')),
            const SizedBox(height: 10),
            TextField(controller: _doctor, decoration: const InputDecoration(labelText: 'Doctor name')),
            const SizedBox(height: 10),
            TextField(controller: _date, decoration: const InputDecoration(labelText: 'Date on document')),
            const SizedBox(height: 10),
            TextField(controller: _diagnosis, decoration: const InputDecoration(labelText: 'Diagnosis')),
            const SizedBox(height: 10),
            TextField(
              controller: _general,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'General instructions'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Extraction notes (from AI / caveats)'),
            ),
            const SizedBox(height: 16),
            if (!_isAnalysisReport) ...[
              Row(
                children: [
                  Text('Medications', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _meds.add(_MedRow())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add row'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Duration (e.g. "7 days" or "2 weeks") is optional — when present we set an end date for reminders automatically. Leave duration blank or "as needed" for open-ended reminders.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.35),
                ),
              ),
              for (var i = 0; i < _meds.length; i++) ...[
                _MedicationEditor(
                  index: i,
                  row: _meds[i],
                  onRemove: _meds.length > 1
                      ? () {
                          setState(() {
                            final r = _meds.removeAt(i);
                            r.dispose();
                          });
                        }
                      : null,
                ),
                const Divider(height: 22),
              ],
            ] else ...[
              Text(
                'This upload is flagged as a report or lab listing — medications aren’t required.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: (_saving || _analysis == null) ? null : _saveAnalyzed,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save to MediSathi'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MedRow {
  final name = TextEditingController();
  final dosage = TextEditingController();
  final frequency = TextEditingController();
  final duration = TextEditingController();
  final instructions = TextEditingController();

  void dispose() {
    name.dispose();
    dosage.dispose();
    frequency.dispose();
    duration.dispose();
    instructions.dispose();
  }
}

class _MedicationEditor extends StatelessWidget {
  const _MedicationEditor({
    required this.index,
    required this.row,
    this.onRemove,
  });

  final int index;
  final _MedRow row;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Medication ${index + 1}', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(controller: row.name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 10),
        TextField(controller: row.dosage, decoration: const InputDecoration(labelText: 'Dosage')),
        const SizedBox(height: 10),
        TextField(controller: row.frequency, decoration: const InputDecoration(labelText: 'Frequency')),
        const SizedBox(height: 10),
        TextField(controller: row.duration, decoration: const InputDecoration(labelText: 'Duration')),
        const SizedBox(height: 10),
        TextField(
          controller: row.instructions,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Instructions'),
        ),
      ],
    );
  }
}
