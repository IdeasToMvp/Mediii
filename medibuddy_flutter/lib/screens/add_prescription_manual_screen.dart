import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/prescription.dart';
import '../services/medibuddy_api.dart';

class AddPrescriptionManualScreen extends StatefulWidget {
  const AddPrescriptionManualScreen({super.key, this.prescriptionId});

  /// When set, loads the record and saves with PATCH.
  final String? prescriptionId;

  @override
  State<AddPrescriptionManualScreen> createState() => _AddPrescriptionManualScreenState();
}

class _AddPrescriptionManualScreenState extends State<AddPrescriptionManualScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _patient = TextEditingController();
  final _doctor = TextEditingController();
  final _date = TextEditingController();
  final _diagnosis = TextEditingController();
  final _general = TextEditingController();
  final List<_MedRow> _meds = [_MedRow()];

  final _api = MediBuddyApi();
  bool _saving = false;
  bool _hydrating = false;
  String? _hydrateError;
  String? _hydratedSource;

  @override
  void initState() {
    super.initState();
    final id = widget.prescriptionId?.trim();
    if (id != null && id.isNotEmpty) {
      _hydrating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate(id));
    }
  }

  Future<void> _hydrate(String id) async {
    try {
      final wrap = await _api.getPrescription(id);
      final raw = wrap['prescription'];
      if (raw is! Map<String, dynamic>) throw const FormatException('Missing prescription');
      final p = Prescription.fromJson(raw);
      if (!mounted) return;
      setState(() {
        if (p.isReport) {
          _hydrateError = 'Open report records from the Reports card; editing uses the prescription form.';
        } else {
          _applyPrescription(p);
          _hydratedSource = p.source;
        }
        _hydrating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hydrating = false;
        _hydrateError = _shortError(e);
      });
    }
  }

  void _applyPrescription(Prescription p) {
    _title.text = p.title ?? '';
    _patient.text = p.patientName ?? '';
    _doctor.text = p.doctorName ?? '';
    _date.text = p.prescriptionDate ?? '';
    _diagnosis.text = p.diagnosis ?? '';
    _general.text = p.generalInstructions ?? '';

    for (final m in _meds) {
      m.dispose();
    }
    _meds.clear();
    for (final med in p.medications) {
      final row = _MedRow();
      row.name.text = (med['name'] ?? '').toString();
      row.dosage.text = med['dosage']?.toString() ?? '';
      row.frequency.text = med['frequency']?.toString() ?? '';
      row.duration.text = med['duration']?.toString() ?? '';
      row.instructions.text = med['instructions']?.toString() ?? '';
      _meds.add(row);
    }
    if (_meds.isEmpty) {
      _meds.add(_MedRow());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _patient.dispose();
    _doctor.dispose();
    _date.dispose();
    _diagnosis.dispose();
    _general.dispose();
    for (final m in _meds) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final meds = <Map<String, dynamic>>[];
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one medication name.')),
        );
        return;
      }

      final pid = widget.prescriptionId?.trim();
      if (pid != null && pid.isNotEmpty) {
        final patch = <String, dynamic>{
          'title': _nullIfEmpty(_title.text),
          'patient_name': _nullIfEmpty(_patient.text),
          'doctor_name': _nullIfEmpty(_doctor.text),
          'prescription_date': _nullIfEmpty(_date.text),
          'diagnosis': _nullIfEmpty(_diagnosis.text),
          'general_instructions': _nullIfEmpty(_general.text),
          'medications': meds,
          'document_kind': 'prescription',
        };
        final src = _hydratedSource?.trim().toLowerCase();
        if (src == 'analyzed' || src == 'manual') {
          patch['source'] = src;
        }
        await _api.updatePrescription(pid, patch);
      } else {
        await _api.createPrescription(
          source: 'manual',
          title: _title.text,
          patientName: _patient.text,
          doctorName: _doctor.text,
          prescriptionDate: _date.text,
          diagnosis: _diagnosis.text,
          generalInstructions: _general.text,
          medications: meds,
        );
      }
      if (!mounted) return;
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
    final isEdit = widget.prescriptionId != null && widget.prescriptionId!.trim().isNotEmpty;

    if (_hydrating) {
      return Scaffold(
        appBar: AppBar(title: Text(isEdit ? 'Edit prescription' : 'Add prescription')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_hydrateError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(isEdit ? 'Edit prescription' : 'Add prescription')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_hydrateError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit prescription' : 'Add prescription')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Details', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Title (optional)')),
            const SizedBox(height: 10),
            TextFormField(controller: _patient, decoration: const InputDecoration(labelText: 'Patient name (optional)')),
            const SizedBox(height: 10),
            TextFormField(controller: _doctor, decoration: const InputDecoration(labelText: 'Doctor name (optional)')),
            const SizedBox(height: 10),
            TextFormField(controller: _date, decoration: const InputDecoration(labelText: 'Date (optional, free text)')),
            const SizedBox(height: 10),
            TextFormField(controller: _diagnosis, decoration: const InputDecoration(labelText: 'Diagnosis (optional)')),
            const SizedBox(height: 10),
            TextFormField(
              controller: _general,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'General instructions'),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Text('Medications', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _meds.add(_MedRow())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add row'),
                ),
              ],
            ),
            const SizedBox(height: 4),
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
              const Divider(height: 24),
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
              label: Text(_saving ? 'Saving…' : (isEdit ? 'Save changes' : 'Save prescription')),
            ),
          ],
        ),
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
        TextFormField(
          controller: row.name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 10),
        TextFormField(controller: row.dosage, decoration: const InputDecoration(labelText: 'Dosage')),
        const SizedBox(height: 10),
        TextFormField(controller: row.frequency, decoration: const InputDecoration(labelText: 'Frequency')),
        const SizedBox(height: 10),
        TextFormField(controller: row.duration, decoration: const InputDecoration(labelText: 'Duration')),
        const SizedBox(height: 10),
        TextFormField(
          controller: row.instructions,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Instructions'),
        ),
      ],
    );
  }
}
