import 'package:flutter/material.dart';

import '../app_theme_scope.dart';
import '../theme/medisathi_colors.dart';
import 'edit_profile_screen.dart' show kGenderLabels;

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+'));
  if (p.isEmpty || p.first.isEmpty) return '?';
  if (p.length == 1) return p.first[0].toUpperCase();
  final a = p.first[0];
  final b = p.last.isNotEmpty ? p.last[0] : '';
  return '$a$b'.toUpperCase();
}

int? _parseBirthYear(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString().trim());
}

int? _approxAge(int? birthYear) {
  if (birthYear == null) return null;
  return DateTime.now().year - birthYear;
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({
    super.key,
    required this.displayName,
    required this.userEmail,
    required this.profile,
    required this.plan,
    required this.onSignOut,
    required this.onEditAccount,
    this.versionLabel = 'v1.0.0',
  });

  final String displayName;
  final String? userEmail;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? plan;
  final VoidCallback onSignOut;
  final VoidCallback onEditAccount;
  final String versionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AppThemeScope.maybeOf(context);
    final emailLine = userEmail ?? '';
    final birthYear = _parseBirthYear(profile?['birth_year']);
    final genderKey = (profile?['gender'] ?? '').toString().trim();
    final genderLabel = genderKey.isEmpty ? null : (kGenderLabels[genderKey.toLowerCase()] ?? genderKey);
    final age = _approxAge(birthYear);
    final sublines = <String?>[
      if (age != null) 'Age ~$age',
      genderLabel,
    ].whereType<String>().toList();

    final planName = plan is Map ? (plan!['display_name']?.toString() ?? '').trim() : '';
    final budget = plan is Map ? plan!['ai_budget'] : null;
    final used = budget is Map ? '${budget['used']}' : '—';
    final lim =
        budget is Map ?
            budget['monthly_limit'] == null ?
                '∞'
            : '${budget['monthly_limit']}'
        : '—';
    final famSlots = plan is Map ? plan!['family_slots_used']?.toString() ?? '—' : '—';
    final famCap =
        plan is Map ?
          plan!['max_family_members'] == null ?
              '∞'
          : '${plan!['max_family_members']}'
        : '—';

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.35),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: MediSathiColors.brandBlue.withValues(alpha: 0.2),
                    child: Text(
                      _initials(displayName),
                      style: theme.textTheme.headlineSmall?.copyWith(
                            color: MediSathiColors.brandBlue,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Material(
                      color: MediSathiColors.brandBlue,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onEditAccount,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    if (emailLine.isNotEmpty)
                      Text(emailLine, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (sublines.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        sublines.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _SectionHeading('GENERAL SETTINGS'),
          const SizedBox(height: 10),
          _ProfileCard(
            child: Column(
              children: [
                _SettingsRow(
                  icon: Icons.manage_accounts_outlined,
                  iconBg: MediSathiColors.brandBlue.withValues(alpha: 0.12),
                  iconColor: MediSathiColors.brandBlue,
                  title: 'Account',
                  subtitle: 'Name, birth year, gender',
                  onTap: onEditAccount,
                ),
                const Divider(height: 1),
                _SettingsRow(
                  icon: Icons.workspace_premium_outlined,
                  iconBg: const Color(0xFFE0F2FE),
                  iconColor: const Color(0xFF0369A1),
                  title: 'Subscription & plan',
                  subtitle: planName.isEmpty ? 'Free' : planName,
                  onTap: () => _showPlanSheet(context, planName, used, lim, famSlots, famCap),
                ),
                const Divider(height: 1),
                _SettingsRow(
                  icon: Icons.shield_outlined,
                  iconBg: const Color(0xFFCCFBF1),
                  iconColor: const Color(0xFF0D9488),
                  title: 'Privacy & security',
                  onTap: () => _snack(context, 'Privacy controls are coming soon.'),
                ),
                const Divider(height: 1),
                _SettingsRow(
                  icon: Icons.file_upload_outlined,
                  iconBg: const Color(0xFFFFEDD5),
                  iconColor: const Color(0xFFEA580C),
                  title: 'Export records',
                  onTap: () => _snack(context, 'Export will be available in a future update.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _SectionHeading('PREFERENCES'),
          const SizedBox(height: 10),
          _ProfileCard(
            child: Column(
              children: [
                _SettingsRow(
                  icon: Icons.dark_mode_outlined,
                  iconBg: const Color(0xFF1E3A5F),
                  iconColor: Colors.white,
                  title: 'Dark mode',
                  trailing: Switch.adaptive(
                    value: scope?.darkMode ?? false,
                    onChanged: scope == null ? null : (v) => scope.onDarkModeChanged(v),
                  ),
                ),
                const Divider(height: 1),
                _SettingsRow(
                  icon: Icons.notifications_outlined,
                  iconBg: MediSathiColors.brandBlue.withValues(alpha: 0.12),
                  iconColor: MediSathiColors.brandBlue,
                  title: 'Notifications',
                  onTap: () => _snack(context, 'Notification preferences coming soon.'),
                ),
                const Divider(height: 1),
                _SettingsRow(
                  icon: Icons.help_outline_rounded,
                  iconBg: const Color(0xFFE5E7EB),
                  iconColor: const Color(0xFF374151),
                  title: 'Help & support',
                  onTap: () => _snack(context, 'Support: reach out from your care portal or clinic contact.'),
                ),
                const Divider(height: 1),
                _SettingsRow(
                  icon: Icons.logout_rounded,
                  iconBg: const Color(0xFFFEE2E2),
                  iconColor: const Color(0xFFB91C1C),
                  title: 'Log out',
                  titleColor: const Color(0xFFB91C1C),
                  onTap: () => _confirmLogout(context, onSignOut),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                Text(
                  'MEDISATHI $versionLabel'.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Institutional trust & security verified',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showPlanSheet(
    BuildContext context,
    String planLabel,
    String used,
    String lim,
    String famSlots,
    String famCap,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your plan', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(planLabel.isEmpty ? 'Free' : planLabel, style: Theme.of(ctx).textTheme.bodyLarge),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('AI extractions (this period)'),
              trailing: Text('$used / $lim', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Family slots'),
              trailing: Text('$famSlots / $famCap', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, VoidCallback onSignOut) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to view records and reminders.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) onSignOut();
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.black45,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: titleColor)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
        ],
      ),
    );
    if (onTap != null) {
      return InkWell(onTap: onTap, child: row);
    }
    return row;
  }
}
