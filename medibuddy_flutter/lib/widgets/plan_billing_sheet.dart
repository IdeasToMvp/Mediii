import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../platform/razorpay_web_checkout.dart'
    show openRazorpaySubscriptionCheckoutWeb;
import '../services/medibuddy_api.dart';
import '../theme/medisathi_colors.dart';

/// Bottom sheet: current usage + upgrade to **Pro** (only paid tier).
class PlanBillingSheet extends StatefulWidget {
  const PlanBillingSheet({
    super.key,
    required this.planLabel,
    required this.famSlots,
    required this.famCap,
    required this.api,
    required this.currentPlanSlug,
    this.proAccessUntilIso,
    required this.userEmail,
    required this.onPurchased,
  });

  final String planLabel;
  final String famSlots;
  final String famCap;
  final MediBuddyApi api;
  final String currentPlanSlug;

  /// From `/api/me` → `plan.pro_access_until` (ISO-8601). Current period end / prepaid access end.
  final String? proAccessUntilIso;
  final String? userEmail;
  final Future<void> Function() onPurchased;

  @override
  State<PlanBillingSheet> createState() => _PlanBillingSheetState();
}

class _PlanBillingSheetState extends State<PlanBillingSheet> {
  Razorpay? _rzp;
  bool _busy = false;

  /// From create-subscription; used after native Checkout success to call sync endpoint.
  String? _pendingSubscriptionId;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _rzp = Razorpay();
      _rzp!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
      _rzp!.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
      _rzp!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    }
  }

  @override
  void dispose() {
    _rzp?.clear();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Prefers Razorpay/backend [detail] field when present (502 JSON body).
  String _readableApiError(MediBuddyApiException e) {
    try {
      final m = jsonDecode(e.body);
      if (m is Map && m['detail'] != null) return m['detail'].toString();
      if (m is Map && m['error'] != null) return m['error'].toString();
    } catch (_) {}
    return e.body;
  }

  /// Pull plan from Razorpay into Supabase (works without waiting for webhooks).
  Future<void> _syncPlanWithBackend(String subscriptionId) async {
    try {
      await widget.api.syncRazorpaySubscription(subscriptionId: subscriptionId);
    } on MediBuddyApiException catch (e) {
      _snack(
        'Could not sync plan yet: ${_readableApiError(e)} Try pull-to-refresh on Profile.',
      );
    }
  }

  Future<void> _checkoutPro(String billingInterval) async {
    setState(() => _busy = true);
    try {
      final created = await widget.api.createRazorpaySubscription(
        planSlug: 'pro',
        billingInterval: billingInterval,
      );
      final keyId = created['key_id']?.toString();
      final subId = created['subscription_id']?.toString();
      if (keyId == null || keyId.isEmpty || subId == null || subId.isEmpty) {
        _snack('Invalid subscription response from server.');
        return;
      }

      _pendingSubscriptionId = subId;

      if (kIsWeb) {
        final webErr = await openRazorpaySubscriptionCheckoutWeb(
          keyId: keyId,
          subscriptionId: subId,
          email: widget.userEmail,
        );
        if (!mounted) return;
        if (webErr == null) {
          await _syncPlanWithBackend(subId);
          if (!mounted) return;
          await widget.onPurchased();
          if (!mounted) return;
          Navigator.of(context).maybePop();
          _snack(
            'You are on Pro (synced). Pull to refresh if something still looks off.',
          );
          return;
        }
        if (webErr == 'dismissed') {
          return;
        }
        _snack(webErr);
        return;
      }

      _rzp!.open({
        'key': keyId,
        'subscription_id': subId,
        'name': 'MediSathi',
        'description': 'Pro subscription',
        'prefill': {
          if (widget.userEmail != null && widget.userEmail!.trim().isNotEmpty)
            'email': widget.userEmail!.trim(),
        },
      });
    } on MediBuddyApiException catch (e) {
      _snack('Could not start checkout: ${_readableApiError(e)}');
    } catch (e) {
      _snack('Could not start checkout: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    final sid = _pendingSubscriptionId;
    if (sid != null && sid.isNotEmpty) {
      await _syncPlanWithBackend(sid);
    }
    _pendingSubscriptionId = null;
    if (!mounted) return;
    await widget.onPurchased();
    if (mounted) Navigator.of(context).maybePop();
    _snack('Pro activated. Pull to refresh if the profile label lags.');
  }

  void _onPaymentError(PaymentFailureResponse r) {
    final m = r.message ?? r.code?.toString() ?? 'Payment failed';
    _snack(m);
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    _snack(r.walletName ?? 'External wallet');
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.currentPlanSlug.trim().toLowerCase();
    final onPro = slug == 'pro';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final accessEnd = _parseAccessIso(widget.proAccessUntilIso);
    final dateFormat = DateFormat.yMMMEd();
    final famUsed = int.tryParse(widget.famSlots.trim());
    final famCapNum = widget.famCap.trim() == '∞'
        ? null
        : int.tryParse(widget.famCap.trim());
    final famProgress = (famUsed != null && famCapNum != null && famCapNum > 0)
        ? (famUsed / famCapNum).clamp(0.0, 1.0)
        : null;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: onPro
                        ? LinearGradient(
                            colors: [
                              MediSathiColors.brandBlue.withValues(alpha: 0.2),
                              const Color(0xFF0369A1).withValues(alpha: 0.18),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: onPro ? null : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: onPro
                          ? MediSathiColors.brandBlue.withValues(alpha: 0.25)
                          : cs.outlineVariant,
                    ),
                  ),
                  child: Icon(
                    onPro
                        ? Icons.workspace_premium_rounded
                        : Icons.person_outline_rounded,
                    color: onPro
                        ? const Color(0xFF0369A1)
                        : cs.onSurfaceVariant,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your plan',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        onPro
                            ? 'Premium · more room for your family'
                            : 'See what you get on Pro',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: onPro
                    ? LinearGradient(
                        colors: [
                          const Color(0xFF0C4A6E).withValues(alpha: 0.06),
                          MediSathiColors.brandBlue.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: onPro ? null : cs.surfaceContainerLow,
                border: Border.all(
                  color: onPro
                      ? MediSathiColors.brandBlue.withValues(alpha: 0.22)
                      : cs.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: onPro
                                ? const Color(0xFF0369A1)
                                : cs.onSurfaceVariant.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            onPro ? 'PRO' : 'FREE',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: onPro ? Colors.white : cs.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (onPro)
                          Icon(
                            Icons.verified_rounded,
                            color: MediSathiColors.brandBlue.withValues(
                              alpha: 0.85,
                            ),
                            size: 22,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.planLabel.isEmpty ? 'Free' : widget.planLabel,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    if (onPro) ...[
                      const SizedBox(height: 14),
                      if (accessEnd != null)
                        _AccessDateRow(
                          icon: Icons.event_available_rounded,
                          label: 'Paid through',
                          value: dateFormat.format(accessEnd.toLocal()),
                          sub:
                              'End of your current billing period. Renews unless you cancel.',
                          emphasisColor: const Color(0xFF0369A1),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 20,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Billing period date appears after checkout or sync. Pull down on this screen to refresh.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Included with your plan',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _FeatureLine(
              icon: Icons.groups_outlined,
              text: 'Household profiles — Free: 2 · Pro: up to 10',
            ),
            const SizedBox(height: 8),
            _FeatureLine(
              icon: Icons.picture_as_pdf_outlined,
              text:
                  'PDF uploads, batch scans, higher AI allowance (enforced on the server)',
            ),
            const SizedBox(height: 18),
            Text(
              'Usage',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Household profiles',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${widget.famSlots} / ${widget.famCap}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  if (famProgress != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: famProgress,
                        minHeight: 6,
                        backgroundColor: cs.outlineVariant.withValues(
                          alpha: 0.35,
                        ),
                        color: MediSathiColors.brandBlue,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              onPro ? 'Manage or upgrade your Pro plan' : 'Upgrade to Pro',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (!onPro) ...[
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: MediSathiColors.brandBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : () => _checkoutPro('monthly'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pro — Monthly'),
                    const SizedBox(height: 2),
                    Text(
                      '₹99 / month',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _busy ? null : () => _checkoutPro('annual'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pro — Yearly'),
                  const SizedBox(height: 2),
                  Text(
                    '₹990 / year',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              kIsWeb
                  ? 'Razorpay loads scripts when checkout opens — normal with test keys.'
                  : 'Secured by Razorpay Checkout.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
            if (onPro) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 22,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Manage or cancel from your Razorpay receipts and emails, or contact support — you keep Pro until the paid-through date above.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator(strokeWidth: 2.3)),
            ],
          ],
        ),
      ),
    );
  }
}

DateTime? _parseAccessIso(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  return DateTime.tryParse(t);
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: MediSathiColors.brandBlue.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _AccessDateRow extends StatelessWidget {
  const _AccessDateRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.emphasisColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color emphasisColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: emphasisColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: emphasisColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: emphasisColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            sub,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
