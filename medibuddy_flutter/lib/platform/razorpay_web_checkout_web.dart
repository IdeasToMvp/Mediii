// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;

/// Opens Razorpay **Standard Checkout** for a subscription (same idea as mobile SDK).
/// The hosted link `api.razorpay.com/v1/l/subscriptions/…` often returns "Hosted page is not available".
///
/// Returns `null` on success, error message on failure, `'dismissed'` if the user closed the modal without paying.
Future<String?> openRazorpaySubscriptionCheckoutWeb({
  required String keyId,
  required String subscriptionId,
  String? email,
}) async {
  final completer = Completer<String?>();

  late final void Function() removeListeners;

  void success(html.Event e) {
    removeListeners();
    if (!completer.isCompleted) completer.complete(null);
  }

  void failed(html.Event e) {
    removeListeners();
    final ev = e as html.CustomEvent;
    final raw = ev.detail?.toString() ?? '';
    var msg = 'Payment failed';
    try {
      final j = jsonDecode(raw);
      if (j is Map && j['description'] != null) {
        msg = j['description'].toString();
      } else if (j is Map && j['reason'] != null) {
        msg = j['reason'].toString();
      }
    } catch (_) {
      if (raw.isNotEmpty) msg = raw;
    }
    if (!completer.isCompleted) completer.complete(msg);
  }

  void dismiss(html.Event e) {
    removeListeners();
    if (!completer.isCompleted) completer.complete('dismissed');
  }

  removeListeners = () {
    html.window.removeEventListener('razorpay-success', success);
    html.window.removeEventListener('razorpay-failed', failed);
    html.window.removeEventListener('razorpay-dismiss', dismiss);
  };

  html.window.addEventListener('razorpay-success', success);
  html.window.addEventListener('razorpay-failed', failed);
  html.window.addEventListener('razorpay-dismiss', dismiss);

  final payload = jsonEncode({
    'key': keyId,
    'subscription_id': subscriptionId,
    'name': 'MediSathi',
    'description': 'Pro subscription',
    'prefill': {if (email != null && email.trim().isNotEmpty) 'email': email.trim()},
  });

  if (js.context['openRazorpaySubscriptionCheckout'] == null) {
    removeListeners();
    return 'Razorpay Checkout script not loaded. Rebuild web and ensure index.html includes checkout.js.';
  }
  js.context.callMethod('openRazorpaySubscriptionCheckout', [payload]);

  return completer.future;
}
