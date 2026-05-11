import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/prescription.dart';
import '../services/medibuddy_api.dart';

class UploadPrescriptionScreen extends StatefulWidget {
  const UploadPrescriptionScreen({super.key});

  @override
  State<UploadPrescriptionScreen> createState() => _UploadPrescriptionScreenState();
}

class _UploadPrescriptionScreenState extends State<UploadPrescriptionScreen> {
  final _picker = ImagePicker();
  final _api = MediBuddyApi();

  XFile? _file;
  bool _analyzing = false;
  bool _saving = false;

  Map<String, dynamic>? _analysis;

  bool get _isAnalysisReport =>
      _analysis != null &&
      (_analysis!['document_kind'] ?? 'prescription').toString().toLowerCase().trim() == 'report';

  final _title = TextEditingController();
  final _patient = TextEditingController();
  final _doctor = TextEditingController();
  final _date = TextEditingController();
  final _diagnosis = TextEditingController();
  final _general = TextEditingController();
  final _notes = TextEditingController();
  final List<_MedRow> _meds = [];

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

  Future<void> _pick(ImageSource source) async {
    final img = await _picker.pickImage(source: source, maxWidth: 2000, imageQuality: 88);
    if (img == null) return;
    setState(() {
      _file = img;
      _analysis = null;
      _clearEditors();
    });
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
    final f = _file;
    if (f == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick an image first.')));
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

  Future<void> _save() async {
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
      );

      if (!mounted) return;

      final buf = StringBuffer('Saved.');
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
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: const Text('Upload prescription')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Take a clear photo or choose an image. The AI extraction is best-effort — always verify before saving.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_file != null)
            Text(
              'Selected: ${_file!.name}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (_analyzing || _file == null) ? null : _analyze,
            icon: _analyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            label: Text(_analyzing ? 'Analyzing…' : 'Analyze with AI'),
          ),
          if (_analysis != null) ...[
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
              onPressed: _saving ? null : _save,
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
