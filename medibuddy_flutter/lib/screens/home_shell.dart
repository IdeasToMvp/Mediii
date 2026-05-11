import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prescription.dart';
import '../services/medibuddy_api.dart';
import '../widgets/family_member_bottom_sheet.dart';
import '../widgets/medisathi_loader.dart';
import 'medicine_reminders_tab.dart';
import 'add_prescription_manual_screen.dart';
import 'dashboard_home_screen.dart';
import 'login_screen.dart';
import 'upload_prescription_screen.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const LoginScreen();
        return const _HomeAuthenticated();
      },
    );
  }
}

class _HomeSnapshot {
  _HomeSnapshot({
    required this.me,
    required this.occurrences,
    required this.familyMembers,
    required this.prescriptions,
    required this.reports,
    required this.medicineSchedules,
  });

  final Map<String, dynamic>? me;
  final List<Map<String, dynamic>> occurrences;
  final List<Map<String, dynamic>> familyMembers;
  final List<Prescription> prescriptions;
  final List<Prescription> reports;
  final List<Map<String, dynamic>> medicineSchedules;

  String displayName([String? emailFallback]) {
    final p = me?['profile'];
    final dn =
        (p is Map && p['display_name'] != null) ?
            p['display_name'].toString().trim()
        : '';
    if (dn.isNotEmpty) return dn;
    final em = emailFallback ?? '';
    if (em.contains('@')) return em.split('@').first;
    return 'Friend';
  }
}

class _HomeAuthenticated extends StatefulWidget {
  const _HomeAuthenticated();

  @override
  State<_HomeAuthenticated> createState() => _HomeAuthenticatedState();
}

class _HomeAuthenticatedState extends State<_HomeAuthenticated> {
  final _api = MediBuddyApi();

  Future<_HomeSnapshot>? _future;
  int _tabIndex = 0;

  Future<_HomeSnapshot> _load() async {
    final meRaw = await _api.getMe();
    final occurrences = await _api.fetchUpcomingMedicineOccurrences(days: 3);
    final famWrap = await _api.listFamilyPayload();
    final famList =
        famWrap['members'] is List ?
            (famWrap['members'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    final rxMaps = await _api.listPrescriptions(kind: 'prescription');
    final repMaps = await _api.listPrescriptions(kind: 'report');
    final schedMaps = await _api.listMedicineSchedules();

    return _HomeSnapshot(
      me: meRaw,
      occurrences: occurrences,
      familyMembers: famList,
      prescriptions: rxMaps.map(Prescription.fromJson).toList(),
      reports: repMaps.map(Prescription.fromJson).toList(),
      medicineSchedules: schedMaps,
    );
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _reload() async {
    final reloadFuture = _load();
    if (!mounted) return;
    setState(() {
      _future = reloadFuture;
    });
    await reloadFuture;
    if (mounted) setState(() {});
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _openAddManual() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddPrescriptionManualScreen()),
    );
    if (saved == true && mounted) await _reload();
  }

  Future<void> _openUpload() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const UploadPrescriptionScreen()),
    );
    if (saved == true && mounted) await _reload();
  }

  Future<void> _promptAddFamily() async {
    final draft = await showFamilyMemberEditorSheet(context);
    if (draft == null || !mounted) return;

    try {
      await _api.createFamilyMember(
        displayName: draft.displayName,
        relation: draft.relation,
        birthYear: draft.birthYear,
        notes: draft.notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Family member added.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add: ${_shortNetworkError(e)}')));
    }
    await _reload();
  }

  static String _shortNetworkError(Object e) {
    if (e is MediBuddyApiException) {
      try {
        final m = jsonDecode(e.body);
        if (m is Map && m['error'] != null) return m['error'].toString();
      } catch (_) {}
      return '${e.statusCode}: ${e.body}';
    }
    return e.toString();
  }

  Future<void> _openEditPrescription(Prescription p) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddPrescriptionManualScreen(prescriptionId: p.id)),
    );
    if (saved == true && mounted) await _reload();
  }

  Future<void> _deletePrescriptionAfterConfirm(Prescription p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text(
          p.isReport
              ? 'This report will be removed permanently.'
              : 'This prescription and its generated reminder links will be removed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.deletePrescription(p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: ${_shortNetworkError(e)}')));
    }
    await _reload();
  }

  Future<void> _promptEditFamily(Map<String, dynamic> member) async {
    final id = member['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final draft = await showFamilyMemberEditorSheet(context, initial: FamilyMemberDraft.fromApiRow(member));
    if (draft == null || !mounted) return;

    try {
      await _api.updateFamilyMember(
        id,
        displayName: draft.displayName,
        relation: draft.relation,
        clearRelation: draft.clearRelation,
        birthYear: draft.birthYear,
        clearBirthYear: draft.clearBirthYear,
        notes: draft.notes,
        clearNotes: draft.clearNotes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Family member updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: ${_shortNetworkError(e)}')));
    }
    await _reload();
  }

  Future<void> _deleteFamilyMemberAfterConfirm(Map<String, dynamic> member) async {
    final id = member['id']?.toString() ?? '';
    final label = (member['display_name'] ?? '').toString();
    if (id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove family member?'),
        content: Text(label.isEmpty ? 'This profile will be removed.' : 'Remove $label from your household?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.deleteFamilyMember(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Family member removed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove: ${_shortNetworkError(e)}')));
    }
    await _reload();
  }

  Future<void> _showDetail(BuildContext context, Prescription p) async {
    final buffer = StringBuffer();
    buffer.writeln('Kind: ${p.documentKind ?? 'prescription'}');
    buffer.writeln(p.patientName != null ? 'Patient: ${p.patientName}' : 'Patient: —');
    buffer.writeln(p.patientFamilyMemberId != null ? 'Linked family member id: ${p.patientFamilyMemberId}' : 'Linked family member id: —');
    buffer.writeln(p.doctorName != null ? 'Doctor: ${p.doctorName}' : 'Doctor: —');
    buffer.writeln(p.prescriptionDate != null ? 'Date: ${p.prescriptionDate}' : 'Date: —');
    buffer.writeln(p.diagnosis != null ? 'Diagnosis: ${p.diagnosis}' : 'Diagnosis: —');
    buffer.writeln();
    if (p.isReport && p.reportSummary != null && p.reportSummary!.isNotEmpty) {
      buffer.writeln('Report summary (JSON)');
      buffer.writeln(const JsonEncoder.withIndent('  ').convert(p.reportSummary));
      buffer.writeln();
    }
    buffer.writeln('Medications');
    var i = 1;
    for (final med in p.medications) {
      final name = med['name']?.toString() ?? '(unnamed)';
      buffer.writeln('$i. $name');
      for (final k in ['dosage', 'frequency', 'duration', 'instructions']) {
        final v = med[k]?.toString().trim();
        if (v == null || v.isEmpty) continue;
        buffer.writeln('   $k: $v');
      }
      i++;
    }
    if ((p.generalInstructions ?? '').trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('General instructions:\n${p.generalInstructions!.trim()}');
    }
    if ((p.extractionNotes ?? '').trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Extraction notes:\n${p.extractionNotes!.trim()}');
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(p.isReport ? 'Report detail' : 'Prescription detail'),
          content: SingleChildScrollView(child: SelectableText(buffer.toString())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
            if (!p.isReport)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openEditPrescription(p);
                },
                child: const Text('Edit'),
              ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _deletePrescriptionAfterConfirm(p);
              },
              style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAddFlow() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('Manual entry'),
              subtitle: const Text('Type medication lines yourself'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Upload & analyze'),
              subtitle: const Text('Photo → AI classify → prescription or report → save'),
              onTap: () => Navigator.pop(context, 'upload'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'manual') {
      await _openAddManual();
    } else {
      await _openUpload();
    }
  }

  Widget _profilePane(_HomeSnapshot snap) {
    final plan = snap.me?['plan'];
    final budget = plan is Map ? plan['ai_budget'] : null;

    final planName = plan is Map ? plan['display_name']?.toString() ?? '' : '';

    final used =
        budget is Map ?
            '${budget['used']}'
        : '—';
    final lim =
        budget is Map ?
            budget['monthly_limit'] == null ?
                '∞'
            : '${budget['monthly_limit']}'
        : '—';

    final famSlots = plan is Map ? plan['family_slots_used']?.toString() ?? '—' : '—';
    final famCap =
        plan is Map ?
          plan['max_family_members'] == null ?
              '∞'
          : '${plan['max_family_members']}'
        : '—';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      children: [
        Text('Plan', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(planName.isEmpty ? 'Freemium' : planName),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('AI extractions (this period)'), trailing: Text('$used / $lim')),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Family slots'), trailing: Text('$famSlots / $famCap')),
        const Divider(height: 32),
        FilledButton.tonal(onPressed: _signOut, child: const Text('Sign out')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      body: FutureBuilder<_HomeSnapshot>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: MediSathiLoader(
                message: 'Getting things ready',
                secondaryMessage: 'Syncing prescriptions and reminders...',
              ),
            );
          }

          if (snap.hasError) {
            final err = snap.error!;
            return Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Could not load dashboard data.', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_shortNetworkError(err), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                  if (userEmail != null) ...[
                    const SizedBox(height: 28),
                    Text('Signed in as $userEmail', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            );
          }

          final data = snap.data!;
          final latestReport = data.reports.isEmpty ? null : data.reports.first;
          final displayName = data.displayName(userEmail);

          return IndexedStack(
            index: _tabIndex,
            children: [
              DashboardHomeScreen(
                displayName: displayName,
                notificationsEnabled: true,
                upcomingMedicines: data.occurrences,
                familyMembers: data.familyMembers,
                recentPrescriptions: data.prescriptions,
                latestReport: latestReport,
                onRefresh: _reload,
                onViewScheduleTap: () => setState(() => _tabIndex = 2),
                onAddFamilyTap: _promptAddFamily,
                onEditFamilyMember: _promptEditFamily,
                onDeleteFamilyMember: _deleteFamilyMemberAfterConfirm,
                onRecentPrescriptionTap: (p) => _showDetail(context, p),
                onEditPrescription: _openEditPrescription,
                onDeletePrescription: _deletePrescriptionAfterConfirm,
              ),
              Column(
                children: [
                  const SafeArea(bottom: false, child: SizedBox(height: 8)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        IconButton(onPressed: () => setState(() => _tabIndex = 0), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                        Text('Upload', style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.icon(
                              onPressed: _pickAddFlow,
                              icon: const Icon(Icons.add_photo_alternate_rounded),
                              label: const Text('Add prescription or report'),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'We distinguish prescriptions vs diagnostics before saving.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Scaffold(
                appBar: AppBar(title: const Text('Medicine reminders')),
                body: MedicineRemindersTab(
                  occurrences: data.occurrences,
                  schedules: data.medicineSchedules,
                  familyMembers: data.familyMembers,
                  api: _api,
                  onRefresh: _reload,
                ),
              ),
              Scaffold(
                appBar: AppBar(title: const Text('Profile')),
                body: RefreshIndicator(onRefresh: _reload, child: _profilePane(data)),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _tabIndex == 0 ?
          FloatingActionButton.extended(onPressed: _pickAddFlow, icon: const Icon(Icons.add_rounded), label: const Text('Add'))
      : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex.clamp(0, 3),
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'HOME'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'UPLOAD'),
          NavigationDestination(icon: Icon(Icons.schedule_outlined), label: 'REMINDERS'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'PROFILE'),
        ],
      ),
    );
  }
}
