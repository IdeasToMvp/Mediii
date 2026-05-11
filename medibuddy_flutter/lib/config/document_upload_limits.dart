/// Matches backend `UPLOAD_MAX_BYTES` and plan rules in `server.js`.
class DocumentUploadLimits {
  DocumentUploadLimits._();

  static const int maxBytes = 10 * 1024 * 1024;

  static bool paidTier(String planSlug) {
    final s = planSlug.trim().toLowerCase();
    // Legacy `plus` tier removed — treat as paid until client refreshes entitlements.
    return s == 'pro' || s == 'plus';
  }

  static String humanMaxSize() {
    const mb = maxBytes ~/ (1024 * 1024);
    return '$mb MB';
  }

  /// Short line for list / app bars.
  static String summaryLine({required bool paid}) {
    if (paid) {
      return 'Pro: multiple photos or PDFs per batch · JPEG, PNG, WebP, GIF, PDF · max ${humanMaxSize()} each · originals stored.';
    }
    return 'Free: one photo at a time · JPEG, PNG, WebP, GIF · max ${humanMaxSize()} · AI reads camera/photos only (not PDF).';
  }
}
