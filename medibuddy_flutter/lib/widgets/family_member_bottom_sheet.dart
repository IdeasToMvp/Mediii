import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/medisathi_colors.dart';

/// Data returned when the user saves the family-member form.
class FamilyMemberDraft {
  const FamilyMemberDraft({
    required this.displayName,
    this.relation,
    this.birthYear,
    this.notes,
    this.clearRelation = false,
    this.clearBirthYear = false,
    this.clearNotes = false,
  });

  final String displayName;
  final String? relation;
  final int? birthYear;
  final String? notes;
  /// When true, PATCH should set `relation` to null.
  final bool clearRelation;
  /// When true (edit mode), PATCH should set `birth_year` to null.
  final bool clearBirthYear;
  /// When true, PATCH should clear stored notes.
  final bool clearNotes;

  factory FamilyMemberDraft.fromApiRow(Map<String, dynamic> row) {
    int? by;
    final raw = row['birth_year'];
    if (raw is num) by = raw.toInt();
    final n = row['notes']?.toString().trim();
    final r = row['relation']?.toString().trim();
    return FamilyMemberDraft(
      displayName: (row['display_name'] ?? '').toString().trim(),
      relation: r == null || r.isEmpty ? null : r,
      birthYear: by,
      notes: (n == null || n.isEmpty) ? null : n,
    );
  }
}

const _relationPresets = [
  'Spouse',
  'Parent',
  'Child',
  'Sibling',
  'Partner',
  'Grandparent',
  'Friend',
];

Future<FamilyMemberDraft?> showFamilyMemberEditorSheet(
  BuildContext context, {
  FamilyMemberDraft? initial,
}) {
  return showModalBottomSheet<FamilyMemberDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _FamilyMemberSheet(initial: initial),
  );
}

class _FamilyMemberSheet extends StatefulWidget {
  const _FamilyMemberSheet({this.initial});

  final FamilyMemberDraft? initial;

  @override
  State<_FamilyMemberSheet> createState() => _FamilyMemberSheetState();
}

class _FamilyMemberSheetState extends State<_FamilyMemberSheet> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _relation = TextEditingController();
  final _notes = TextEditingController();
  String? _selectedPreset;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _name.text = i.displayName;
      _relation.text = i.relation ?? '';
      _notes.text = i.notes ?? '';
      final by = i.birthYear;
      if (by != null) {
        final approxAge = DateTime.now().year - by;
        if (approxAge >= 0 && approxAge < 130) _age.text = '$approxAge';
      }
      if (i.relation != null && _relationPresets.contains(i.relation)) {
        _selectedPreset = i.relation;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _relation.dispose();
    _notes.dispose();
    super.dispose();
  }

  int? _parseBirthYearFromAgeField() {
    final t = _age.text.trim();
    if (t.isEmpty) return null;
    final age = int.tryParse(t);
    if (age == null || age < 0 || age > 130) return null;
    final y = DateTime.now().year - age;
    if (y < 1900 || y > DateTime.now().year) return null;
    return y;
  }

  void _applyPreset(String label) {
    setState(() {
      _selectedPreset = label;
      _relation.text = label;
    });
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    final relTrim = _relation.text.trim();
    final hadRelation = (widget.initial?.relation ?? '').trim().isNotEmpty;
    final clearRelation = _isEdit && hadRelation && relTrim.isEmpty;
    final relation = relTrim.isEmpty ? null : relTrim;

    final hadBirthYear = widget.initial?.birthYear != null;
    final ageTextEmpty = _age.text.trim().isEmpty;
    int? birthYear;
    bool clearBirthYear = false;
    if (ageTextEmpty) {
      if (_isEdit && hadBirthYear) clearBirthYear = true;
      birthYear = null;
    } else {
      birthYear = _parseBirthYearFromAgeField();
      if (birthYear == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid age (0–130) or leave blank.')),
        );
        return;
      }
    }

    final notesTrim = _notes.text.trim();
    final hadNotes = (widget.initial?.notes ?? '').trim().isNotEmpty;
    final clearNotes = _isEdit && hadNotes && notesTrim.isEmpty;
    final notes = notesTrim.isEmpty ? null : notesTrim;

    Navigator.of(context).pop(
      FamilyMemberDraft(
        displayName: name,
        relation: relation,
        birthYear: birthYear,
        notes: notes,
        clearRelation: clearRelation,
        clearBirthYear: clearBirthYear,
        clearNotes: clearNotes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom.clamp(0.0, double.infinity);
    final theme = Theme.of(context);
    const heroTitle = Color(0xFFF8FAFC);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              MediSathiColors.surfaceDeep,
              theme.colorScheme.surface,
            ],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: MediSathiColors.neonAccent.withValues(alpha: 0.08),
              blurRadius: 32,
              spreadRadius: 0,
              offset: const Offset(0, -8),
            ),
          ],
          border: Border.all(color: MediSathiColors.glassBorder),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isEdit ? 'Update profile' : 'Add household member',
                  style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: heroTitle,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isEdit
                      ? 'Keep details current for smarter prescription matching and reminders.'
                      : 'Age helps us personalize care context. Relation makes records easier to read.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 22),
                _GlassField(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Full name', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Priya Sharma',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _GlassField(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Age',
                              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _age,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                              decoration: const InputDecoration(
                                hintText: 'years',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GlassField(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Relation',
                              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _relation,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                hintText: 'custom',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (_) {
                                setState(() {
                                  final t = _relation.text.trim();
                                  _selectedPreset = _relationPresets.contains(t) ? t : null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Quick relation',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in _relationPresets)
                      ChoiceChip(
                        label: Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color:
                                _selectedPreset == label ? const Color(0xFF0F172A) : Colors.white.withValues(alpha: 0.92),
                          ),
                        ),
                        selected: _selectedPreset == label,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        selectedColor: MediSathiColors.neonAccent.withValues(alpha: 0.38),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                        onSelected: (_) => _applyPreset(label),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _GlassField(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Health notes',
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Allergies, conditions, anything caregivers should see (optional).',
                        style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notes,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Penicillin allergy · Type 2 diabetes',
                          border: InputBorder.none,
                          alignLabelWithHint: true,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: Icon(_isEdit ? Icons.save_rounded : Icons.person_add_rounded),
                  label: Text(_isEdit ? 'Save changes' : 'Add member'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: MediSathiColors.brandBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  const _GlassField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MediSathiColors.glassBorder.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: child,
      ),
    );
  }
}
