import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prescription.dart';
import '../services/medibuddy_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_update_prompt.dart';
import '../widgets/family_member_bottom_sheet.dart';
import '../widgets/medisathi_loader.dart';
import '../widgets/prescription_detail_sheet.dart';
import 'documents_library_tab.dart';
import 'medicine_reminders_tab.dart';
import 'add_prescription_manual_screen.dart';
import 'dashboard_home_screen.dart';
import 'edit_profile_screen.dart';
import 'landing_screen.dart';
import 'login_screen.dart';
import 'profile_tab.dart';
import 'upload_prescription_screen.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShellUpdateTrigger(
      child: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = Supabase.instance.client.auth.currentSession;
          // Marketing landing (WelcomeWebFlow) is web-only; Android / iOS go straight to sign-in.
          if (session == null) {
            return kIsWeb ? const WelcomeWebFlow() : const LoginScreen();
          }
          // Web: landing stays full viewport; authenticated app mirrors phone layout.
          if (kIsWeb) {
            return AppTheme.constrainMobileWidth(
              maxWidth: 640,
              child: const _HomeAuthenticated(),
            );
          }
          return const _HomeAuthenticated();
        },
      ),
    );
  }
}

/// First time the post-bootstrap shell is in the tree: call release API vs [PackageInfo.buildNumber].
class _ShellUpdateTrigger extends StatefulWidget {
  const _ShellUpdateTrigger({required this.child});

  final Widget child;

  @override
  State<_ShellUpdateTrigger> createState() => _ShellUpdateTriggerState();
}

class _ShellUpdateTriggerState extends State<_ShellUpdateTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppUpdatePrompt.scheduleWhenShellReady(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
    final dn = (p is Map && p['display_name'] != null)
        ? p['display_name'].toString().trim()
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
    final famList = famWrap['members'] is List
        ? (famWrap['members'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
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

  List<Prescription> _documentsSorted(_HomeSnapshot d) {
    final all = [...d.prescriptions, ...d.reports];
    all.sort((a, b) {
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return all;
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
    var slug = 'free';
    try {
      final me = await _api.getMe();
      final p = me['plan'];
      if (p is Map && p['slug'] != null) {
        slug = p['slug'].toString().trim().toLowerCase();
      }
    } catch (_) {}
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => UploadPrescriptionScreen(planSlug: slug),
      ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Family member added.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add: ${_shortNetworkError(e)}')),
      );
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
      MaterialPageRoute(
        builder: (_) => AddPrescriptionManualScreen(prescriptionId: p.id),
      ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.deletePrescription(p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${_shortNetworkError(e)}')),
      );
    }
    await _reload();
  }

  Future<void> _promptEditFamily(Map<String, dynamic> member) async {
    final id = member['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final draft = await showFamilyMemberEditorSheet(
      context,
      initial: FamilyMemberDraft.fromApiRow(member),
    );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Family member updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: ${_shortNetworkError(e)}')),
      );
    }
    await _reload();
  }

  Future<void> _deleteFamilyMemberAfterConfirm(
    Map<String, dynamic> member,
  ) async {
    final id = member['id']?.toString() ?? '';
    final label = (member['display_name'] ?? '').toString();
    if (id.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove family member?'),
        content: Text(
          label.isEmpty
              ? 'This profile will be removed.'
              : 'Remove $label from your household?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.deleteFamilyMember(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Family member removed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove: ${_shortNetworkError(e)}')),
      );
    }
    await _reload();
  }

  Future<void> _showDetail(BuildContext context, Prescription p) async {
    if (!context.mounted) return;
    await showPrescriptionDetailSheet(
      context,
      p: p,
      onEdit: () => _openEditPrescription(p),
      onDeleteConfirmed: () => _deletePrescriptionAfterConfirm(p),
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
              subtitle: const Text(
                'Photo → AI classify → prescription or report → save',
              ),
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
            final errText = _shortNetworkError(err);
            final suggestInAppBrowser =
                kIsWeb && errText.contains('Load failed');
            return Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Could not load dashboard data.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(errText, style: Theme.of(context).textTheme.bodySmall),
                  if (suggestInAppBrowser) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Links opened inside chat apps sometimes block loading the API. Open this site in Safari or Chrome instead, then tap Retry.',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                  if (userEmail != null) ...[
                    const SizedBox(height: 28),
                    Text(
                      'Signed in as $userEmail',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            );
          }

          final data = snap.data!;
          final latestReport = data.reports.isEmpty ? null : data.reports.first;
          final displayName = data.displayName(userEmail);
          final mergedDocs = _documentsSorted(data);
          final planRaw = data.me?['plan'];
          final planSlug = planRaw is Map && planRaw['slug'] != null
              ? planRaw['slug'].toString().trim().toLowerCase()
              : 'free';

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
              Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () => setState(() => _tabIndex = 0),
                  ),
                  title: const Text('Prescriptions & reports'),
                ),
                body: DocumentsLibraryTab(
                  records: mergedDocs,
                  onRefresh: _reload,
                  onOpen: (p) => _showDetail(context, p),
                  planSlug: planSlug,
                ),
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
                appBar: AppBar(
                  title: const Text('MediSathi'),
                  centerTitle: false,
                  actions: [
                    IconButton(
                      tooltip: 'Notifications',
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Notification center is coming soon.',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                body: RefreshIndicator(
                  onRefresh: _reload,
                  child: ProfileTab(
                    displayName: displayName,
                    userEmail: userEmail,
                    profile: data.me?['profile'] as Map<String, dynamic>?,
                    plan: data.me?['plan'] as Map<String, dynamic>?,
                    medibuddyApi: _api,
                    planSlug: planSlug,
                    onSubscriptionUpdated: _reload,
                    onSignOut: _signOut,
                    onEditAccount: () async {
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(
                            api: _api,
                            initialProfile:
                                data.me?['profile'] as Map<String, dynamic>?,
                            displayFallback: displayName,
                          ),
                        ),
                      );
                      if (ok == true && context.mounted) await _reload();
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: (_tabIndex == 0 || _tabIndex == 1)
          ? FloatingActionButton.extended(
              onPressed: _pickAddFlow,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex.clamp(0, 3),
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'HOME',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy_rounded),
            label: 'RECORDS',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            label: 'REMINDERS',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'PROFILE',
          ),
        ],
      ),
    );
  }
}
