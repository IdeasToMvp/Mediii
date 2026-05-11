import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../platform/razorpay_web_checkout.dart' show openRazorpaySubscriptionCheckoutWeb;
import '../services/medibuddy_api.dart';

/// Bottom sheet: current usage + upgrade to **Pro** (only paid tier).
class PlanBillingSheet extends StatefulWidget {
  const PlanBillingSheet({
    super.key,
    required this.planLabel,
    required this.famSlots,
    required this.famCap,
    required this.api,
    required this.currentPlanSlug,
    required this.userEmail,
    required this.onPurchased,
  });

  final String planLabel;
  final String famSlots;
  final String famCap;
  final MediBuddyApi api;
  final String currentPlanSlug;
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
      _snack('Could not sync plan yet: ${_readableApiError(e)} Try pull-to-refresh on Profile.');
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
          _snack('You are on Pro (synced). Pull to refresh if something still looks off.');
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
          if (widget.userEmail != null && widget.userEmail!.trim().isNotEmpty) 'email': widget.userEmail!.trim(),
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

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 28 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your plan', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(widget.planLabel.isEmpty ? 'Free' : widget.planLabel, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text(
            'Free: up to 2 household profiles · Pro: up to 10, PDF & batch uploads, higher AI allowance (limits apply server-side).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Household profiles'),
            trailing:
                Text('${widget.famSlots} / ${widget.famCap}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 16),
          if (!onPro) ...[
            Text('Upgrade', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : () => _checkoutPro('monthly'),
              child: const Text('Pro — billed monthly'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy ? null : () => _checkoutPro('annual'),
              child: const Text('Pro — billed yearly'),
            ),
            const SizedBox(height: 8),
            Text(
              kIsWeb ?
                  'Razorpay loads many small scripts when checkout opens — normal. Use Test keys while developing.'
              : 'Uses Razorpay Checkout. Set RAZORPAY_PLAN_ID_PRO_MONTHLY, RAZORPAY_PLAN_ID_PRO_ANNUAL, and webhook secret on the server.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ] else
            Text(
              'You are on Pro. Manage billing via Razorpay receipts or support if you need to cancel.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          if (_busy) ...[const SizedBox(height: 16), const Center(child: CircularProgressIndicator(strokeWidth: 2))],
        ],
      ),
    );
  }
}
