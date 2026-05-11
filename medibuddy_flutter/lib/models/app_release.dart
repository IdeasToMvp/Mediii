class AppRelease {
  const AppRelease({
    required this.id,
    this.platform = 'android',
    required this.versionLabel,
    required this.versionCode,
    required this.channel,
    required this.releaseNotes,
    required this.apkFilename,
    this.apkByteSize,
    this.apkSha256Hex,
    this.apkDownloadUrl,
    this.updateMandatory = false,
    required this.createdAt,
  });

  final String id;
  final String platform;
  final String versionLabel;
  final int versionCode;
  final String channel;
  final String releaseNotes;
  /// Display/install filename (.apk Android, .ipa iOS).
  final String apkFilename;
  final int? apkByteSize;
  final String? apkSha256Hex;
  /// HTTPS link when not using Storage.
  final String? apkDownloadUrl;
  /// When true, app should treat the update as required (blocking prompt).
  final bool updateMandatory;
  final DateTime createdAt;

  Uri? get resolvedLaunchUri {
    final u = apkDownloadUrl?.trim();
    if (u == null || u.isEmpty) return null;
    return Uri.tryParse(u);
  }

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'];
    final sz = json['apk_byte_size'];
    return AppRelease(
      id: json['id'] as String,
      platform: json['platform'] as String? ?? 'android',
      versionLabel: json['version_label'] as String,
      versionCode: (json['version_code'] as num).toInt(),
      channel: json['channel'] as String? ?? 'production',
      releaseNotes: json['release_notes'] as String? ?? '',
      apkFilename: json['apk_filename'] as String,
      apkByteSize: sz == null ? null : (sz as num).toInt(),
      apkSha256Hex: json['apk_sha256_hex'] as String?,
      apkDownloadUrl: json['apk_download_url'] as String?,
      updateMandatory: json['update_mandatory'] == true,
      createdAt: DateTime.parse(created as String),
    );
  }
}
