import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

class GoogleDriveVaultService {
  GoogleDriveVaultService._();
  static final GoogleDriveVaultService instance = GoogleDriveVaultService._();

  static const String latestFileName = 'ExamVault_Latest_Backup.json';
  static const String previousFileName = 'ExamVault_Previous_Backup.json';

  bool _initialized = false;
  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await GoogleSignIn.instance.initialize();
      _initialized = true;
    } catch (e) {
      debugPrint('GoogleSignIn initialize error: $e');
    }
  }

  /// Attempts silent/lightweight sign in on app startup
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      await _ensureInitialized();
      _currentUser =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      return _currentUser;
    } catch (e) {
      debugPrint('Silent Google sign-in skipped: $e');
      return null;
    }
  }

  /// Interactive sign in
  Future<GoogleSignInAccount?> signIn() async {
    try {
      await _ensureInitialized();
      _currentUser = await GoogleSignIn.instance.authenticate(
        scopeHint: [drive.DriveApi.driveFileScope],
      );
      return _currentUser;
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
      _currentUser = null;
    } catch (e) {
      debugPrint('Google sign-out error: $e');
    }
  }

  Future<drive.DriveApi?> _getDriveApi() async {
    await _ensureInitialized();
    final account = _currentUser ?? await signIn();
    if (account == null) return null;

    final authHeaders = await account.authorizationClient.authorizationHeaders(
      [drive.DriveApi.driveFileScope],
      promptIfNecessary: true,
    );
    if (authHeaders == null) {
      throw Exception('Google Drive authorization was denied or unavailable');
    }
    final client = GoogleAuthClient(authHeaders);
    return drive.DriveApi(client);
  }

  /// Finds a file by name in the user's Google Drive
  Future<drive.File?> _findFileByName(drive.DriveApi api, String name) async {
    try {
      final fileList = await api.files.list(
        q: "name = '$name' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, size)',
      );
      if (fileList.files != null && fileList.files!.isNotEmpty) {
        return fileList.files!.first;
      }
      return null;
    } catch (e) {
      debugPrint('Error searching file on Drive: $e');
      return null;
    }
  }

  /// Uploads backup content to Google Drive maintaining the Rolling Dual Backup:
  /// 1. If ExamVault_Latest_Backup.json already exists in Drive, renames/copies to ExamVault_Previous_Backup.json
  /// 2. Saves new backup as ExamVault_Latest_Backup.json
  Future<bool> syncBackupToDrive(String jsonContent) async {
    final api = await _getDriveApi();
    if (api == null) return false;

    try {
      final bytes = utf8.encode(jsonContent);

      // Step 1: Check if Latest backup already exists on Drive
      final existingLatest = await _findFileByName(api, latestFileName);

      if (existingLatest != null && existingLatest.id != null) {
        // Find or delete older previous backup if any, and rotate latest -> previous
        final existingPrevious = await _findFileByName(api, previousFileName);
        if (existingPrevious != null && existingPrevious.id != null) {
          try {
            await api.files.delete(existingPrevious.id!);
          } catch (_) {}
        }

        // Rename the existing latest to previous
        try {
          await api.files.update(
            drive.File()..name = previousFileName,
            existingLatest.id!,
          );
        } catch (e) {
          debugPrint('Error rotating previous drive backup: $e');
        }
      }

      // Step 2: Upload new backup as ExamVault_Latest_Backup.json
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );

      final newFileMetadata = drive.File()
        ..name = latestFileName
        ..description =
            'Life & Study Assistant - Exam & Credential Vault Backup'
        ..mimeType = 'application/json';

      await api.files.create(
        newFileMetadata,
        uploadMedia: media,
      );

      debugPrint('Backup successfully synced to Google Drive!');
      return true;
    } catch (e) {
      debugPrint('Error syncing backup to Google Drive: $e');
      rethrow;
    }
  }

  /// Downloads the Latest (or optionally Previous) backup from Google Drive
  Future<String?> downloadBackupFromDrive({bool usePrevious = false}) async {
    final api = await _getDriveApi();
    if (api == null) return null;

    final targetName = usePrevious ? previousFileName : latestFileName;
    final file = await _findFileByName(api, targetName);
    if (file == null || file.id == null) {
      return null;
    }

    final media = await api.files.get(
      file.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    if (media is drive.Media) {
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    }
    return null;
  }
}
