import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/medibuddy_api.dart';

const Map<String, String> kGenderLabels = {
  'female': 'Female',
  'male': 'Male',
  'non_binary': 'Non-binary',
  'prefer_not_say': 'Prefer not to say',
  'other': 'Other',
};

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.api,
    required this.initialProfile,
    required this.displayFallback,
  });

  final MediBuddyApi api;
  final Map<String, dynamic>? initialProfile;
  final String displayFallback;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _birthYear;
  String? _gender;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _name = TextEditingController(text: (p?['display_name'] ?? '').toString());
    final by = p?['birth_year'];
    _birthYear = TextEditingController(text: by == null ? '' : '$by');
    final g = (p?['gender'] ?? '').toString().trim();
    _gender = g.isEmpty ? null : g.toLowerCase();
  }

  @override
  void dispose() {
    _name.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final nameTrim = _name.text.trim();
      final yearRaw = _birthYear.text.trim();
      int? yearVal;
      if (yearRaw.isNotEmpty) {
        yearVal = int.tryParse(yearRaw);
        if (yearVal == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Birth year must be a number.')));
          return;
        }
        final cy = DateTime.now().year;
        if (yearVal < 1900 || yearVal > cy) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Use a year between 1900 and $cy.')));
          return;
        }
      }

      final patch = <String, dynamic>{
        'display_name': nameTrim.isEmpty ? widget.displayFallback : nameTrim,
        if (yearRaw.isEmpty) 'birth_year': null else 'birth_year': yearVal,
        'gender': _gender,
      };

      await widget.api.updateProfile(patch);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      var msg = e.toString();
      if (e is MediBuddyApiException) {
        try {
          final m = jsonDecode(e.body);
          if (m is Map && m['error'] != null) msg = m['error'].toString();
        } catch (_) {}
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $msg')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(
            'Basic details',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Used to personalize MediSathi. You can clear birth year or gender anytime.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _birthYear,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Birth year',
              hintText: 'e.g. 1990 · leave blank to remove',
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Gender'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _gender,
                hint: const Text('— Not specified —'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('— Not specified —')),
                  for (final e in kGenderLabels.entries)
                    DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _gender = v),
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded),
            label: Text(_busy ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
