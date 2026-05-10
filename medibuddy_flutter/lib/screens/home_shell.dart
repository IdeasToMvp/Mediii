import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prescription.dart';
import '../services/medibuddy_api.dart';
import 'add_prescription_manual_screen.dart';
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

class _HomeAuthenticated extends StatefulWidget {
  const _HomeAuthenticated();

  @override
  State<_HomeAuthenticated> createState() => _HomeAuthenticatedState();
}

class _HomeAuthenticatedState extends State<_HomeAuthenticated> {
  final _api = MediBuddyApi();
  Future<List<Map<String, dynamic>>>? _future;

  Future<void> _reload() async {
    setState(() {
      _future = _api.listPrescriptions();
    });
    await _future;
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _future = _api.listPrescriptions();
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _openAddManual() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddPrescriptionManualScreen()),
    );
    if (saved == true && mounted) {
      await _reload();
    }
  }

  Future<void> _openUpload() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const UploadPrescriptionScreen()),
    );
    if (saved == true && mounted) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MediSathi'),
        actions: [
          IconButton(onPressed: _reload, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (v) async {
              if (v == 'logout') await _signOut();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              final err = snap.error!;
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Could not load prescriptions.', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_shortNetworkError(err), style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Try again')),
                ],
              );
            }
            final rows = snap.data ?? [];
            if (rows.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (userEmail != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Signed in as $userEmail',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  Text(
                    'No prescriptions yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Add one manually or upload a prescription image — the Node API analyzes it using OpenAI, then saves it to Supabase.',
                  ),
                ],
              );
            }

            final fmt = DateFormat.yMMMEd().add_jm();
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
              itemCount: rows.length + (userEmail == null ? 0 : 1),
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                if (userEmail != null && idx == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('Signed in as $userEmail', style: Theme.of(context).textTheme.bodySmall),
                  );
                }
                final dataIdx = userEmail != null ? idx - 1 : idx;
                final p = Prescription.fromJson(rows[dataIdx]);

                final created = p.createdAt == null ? '—' : fmt.format(p.createdAt!.toLocal());
                final title = (p.title != null && p.title!.trim().isNotEmpty)
                    ? p.title!.trim()
                    : (p.doctorName != null ? 'Rx · ${p.doctorName}' : 'Prescription');

                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showDetail(context, p),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  p.source == 'analyzed' ? 'AI-assisted' : 'Manual',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Saved: $created', style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 10),
                          Text(
                            p.medications.isEmpty ? 'Medications: —' : 'Medications: ${p.medications.length}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if ((p.generalInstructions ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              p.generalInstructions!.trim(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
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
                    subtitle: const Text('Photo → OpenAI → review → save'),
                    onTap: () => Navigator.pop(context, 'upload'),
                  ),
                  const SizedBox(height: 6),
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
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
    );
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

  Future<void> _showDetail(BuildContext context, Prescription p) async {
    final buffer = StringBuffer();
    buffer.writeln(p.patientName != null ? 'Patient: ${p.patientName}' : 'Patient: —');
    buffer.writeln(p.doctorName != null ? 'Doctor: ${p.doctorName}' : 'Doctor: —');
    buffer.writeln(p.prescriptionDate != null ? 'Date: ${p.prescriptionDate}' : 'Date: —');
    buffer.writeln(p.diagnosis != null ? 'Diagnosis: ${p.diagnosis}' : 'Diagnosis: —');
    buffer.writeln();
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Prescription detail'),
          content: SingleChildScrollView(child: SelectableText(buffer.toString())),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        );
      },
    );
  }
}
