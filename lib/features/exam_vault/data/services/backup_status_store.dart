import 'package:shared_preferences/shared_preferences.dart';

/// What the backup screen shows about the last successful Drive backup.
///
/// WhatsApp shows "Last backup: today, 2:14 AM &middot; 1.2 GB". This is the
/// same idea: without it the user taps backup and has no way to tell whether
/// anything actually happened.
class VaultBackupStatus {
  /// When the last successful Drive backup finished. Null means never.
  final DateTime? at;

  /// How many exam applications were in that backup.
  final int applications;

  /// How many PDF documents were uploaded alongside it.
  final int pdfs;

  /// Size of the backup JSON in bytes (PDFs are not counted).
  final int bytes;

  const VaultBackupStatus({
    this.at,
    this.applications = 0,
    this.pdfs = 0,
    this.bytes = 0,
  });

  static const VaultBackupStatus never = VaultBackupStatus();

  bool get hasBackup => at != null;
}

class BackupStatusStore {
  BackupStatusStore._();
  static final BackupStatusStore instance = BackupStatusStore._();

  static const String _keyAt = 'exam_vault_last_backup_at';
  static const String _keyApplications = 'exam_vault_last_backup_applications';
  static const String _keyPdfs = 'exam_vault_last_backup_pdfs';
  static const String _keyBytes = 'exam_vault_last_backup_bytes';

  Future<VaultBackupStatus> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAt);
    if (raw == null) return VaultBackupStatus.never;

    final at = DateTime.tryParse(raw);
    if (at == null) return VaultBackupStatus.never;

    return VaultBackupStatus(
      at: at,
      applications: prefs.getInt(_keyApplications) ?? 0,
      pdfs: prefs.getInt(_keyPdfs) ?? 0,
      bytes: prefs.getInt(_keyBytes) ?? 0,
    );
  }

  Future<VaultBackupStatus> record({
    required int applications,
    required int pdfs,
    required int bytes,
  }) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAt, now.toIso8601String());
    await prefs.setInt(_keyApplications, applications);
    await prefs.setInt(_keyPdfs, pdfs);
    await prefs.setInt(_keyBytes, bytes);

    return VaultBackupStatus(
      at: now,
      applications: applications,
      pdfs: pdfs,
      bytes: bytes,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAt);
    await prefs.remove(_keyApplications);
    await prefs.remove(_keyPdfs);
    await prefs.remove(_keyBytes);
  }
}
