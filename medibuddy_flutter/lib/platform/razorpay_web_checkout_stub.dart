/// Non-web: unused.
Future<String?> openRazorpaySubscriptionCheckoutWeb({
  required String keyId,
  required String subscriptionId,
  String? email,
}) async {
  throw UnsupportedError('Razorpay web checkout is only for Flutter Web');
}
