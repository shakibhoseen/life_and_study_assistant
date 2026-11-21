import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GoogleSignInConfigurationException implements Exception {
  final String message;
  const GoogleSignInConfigurationException(this.message);

  @override
  String toString() => message;
}

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

  static const String prefKeyServerClientId =
      'exam_vault_google_server_client_id';

  bool _initialized = false;
  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  String? _cachedMainFolderId;
  String? _cachedDocumentsFolderId;

  Future<String?> getServerClientId() async {
    // 1. Check .env if loaded
    if (dotenv.isInitialized) {
      final envId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
      if (envId != null && envId.trim().isNotEmpty) {
        return envId.trim();
      }
    }

    // 2. Check compile-time environment variable
    const compileTimeId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    if (compileTimeId.isNotEmpty) {
      return compileTimeId;
    }

    // 3. Fallback to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefKeyServerClientId);
  }

  Future<void> setServerClientId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.trim().isEmpty) {
      await prefs.remove(prefKeyServerClientId);
    } else {
      await prefs.setString(prefKeyServerClientId, id.trim());
    }
    _initialized = false;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      final serverClientId = await getServerClientId();
      await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
      _initialized = true;
    } catch (e) {
      debugPrint('GoogleSignIn initialize error: $e');
    }
  }

  /// Attempts silent/lightweight sign in on app startup
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      final serverClientId = await getServerClientId();
      if (serverClientId == null || serverClientId.trim().isEmpty) {
        return null;
      }
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
    final serverClientId = await getServerClientId();
    if (serverClientId == null || serverClientId.trim().isEmpty) {
      throw const GoogleSignInConfigurationException(
        'Google Cloud Web Client ID সেট করা নেই।\n\n'
        'সরাসরি অ্যাপের ভেতর থেকে সাইন-ইন করতে Google Cloud OAuth Web Client ID প্রয়োজন।\n\n'
        'তবে কোনো কনফিগারেশন ছাড়াই আপনি "গুগল ড্রাইভ ১-ট্যাপ ব্যাকআপ" ব্যবহার করে এখনই সব ডেটা ও PDF ড্রাইভে সেভ করতে পারেন!',
      );
    }

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
      _cachedMainFolderId = null;
      _cachedDocumentsFolderId = null;
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

  /// Finds a file by name in the user's Google Drive.
  /// If [parentFolderId] is provided, searches inside that folder first,
  /// with a global fallback for backwards compatibility with legacy backups.
  Future<drive.File?> _findFileByName(
    drive.DriveApi api,
    String name, {
    String? parentFolderId,
  }) async {
    try {
      if (parentFolderId != null) {
        final scopedList = await api.files.list(
          q: "name = '$name' and '$parentFolderId' in parents and trashed = false",
          spaces: 'drive',
          $fields: 'files(id, name, modifiedTime, size, parents)',
        );
        if (scopedList.files != null && scopedList.files!.isNotEmpty) {
          return scopedList.files!.first;
        }
      }

      final fileList = await api.files.list(
        q: "name = '$name' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, size, parents)',
      );
      if (fileList.files != null && fileList.files!.isNotEmpty) {
        return fileList.files!.first;
      }
      return null;
    } catch (e) {
      debugPrint('Error searching file on Drive ($name): $e');
      return null;
    }
  }

  static const String mainVaultFolderName = 'ExamVault';
  static const String vaultDocumentsFolderName = 'Documents';

  Future<String?> _getOrCreateMainFolder(drive.DriveApi api) async {
    if (_cachedMainFolderId != null) return _cachedMainFolderId;
    try {
      final list = await api.files.list(
        q: "name = '$mainVaultFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      if (list.files != null && list.files!.isNotEmpty) {
        _cachedMainFolderId = list.files!.first.id;
        return _cachedMainFolderId;
      }
      final folderMetadata = drive.File()
        ..name = mainVaultFolderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..description =
            'Life & Study Assistant - Exam & Credential Vault Backup Folder';
      final folder = await api.files.create(folderMetadata);
      _cachedMainFolderId = folder.id;
      return _cachedMainFolderId;
    } catch (e) {
      debugPrint('Error creating/finding main ExamVault folder on Drive: $e');
      return null;
    }
  }

  Future<String?> _getOrCreateDocumentsFolder(drive.DriveApi api) async {
    if (_cachedDocumentsFolderId != null) return _cachedDocumentsFolderId;
    try {
      final mainId = await _getOrCreateMainFolder(api);
      String query =
          "name = '$vaultDocumentsFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      if (mainId != null) {
        query += " and '$mainId' in parents";
      }
      final list = await api.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      if (list.files != null && list.files!.isNotEmpty) {
        _cachedDocumentsFolderId = list.files!.first.id;
        return _cachedDocumentsFolderId;
      }
      final folderMetadata = drive.File()
        ..name = vaultDocumentsFolderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..description =
            'Life & Study Assistant - Exam Vault PDF Attachments';
      if (mainId != null) {
        folderMetadata.parents = [mainId];
      }
      final folder = await api.files.create(folderMetadata);
      _cachedDocumentsFolderId = folder.id;
      return _cachedDocumentsFolderId;
    } catch (e) {
      debugPrint('Error creating/finding documents folder on Drive: $e');
      return null;
    }
  }

  /// Uploads backup content to Google Drive maintaining the Rolling Dual Backup:
  /// 1. Finds or creates the dedicated 'ExamVault' folder on user's Drive.
  /// 2. If ExamVault_Latest_Backup.json already exists in Drive, renames/rotates to ExamVault_Previous_Backup.json.
  /// 3. Saves new backup as ExamVault_Latest_Backup.json inside 'ExamVault' folder.
  Future<bool> syncBackupToDrive(String jsonContent) async {
    final api = await _getDriveApi();
    if (api == null) return false;

    try {
      final bytes = utf8.encode(jsonContent);
      final mainFolderId = await _getOrCreateMainFolder(api);

      // Step 1: Check if Latest backup already exists on Drive in main folder
      final existingLatest =
          await _findFileByName(api, latestFileName, parentFolderId: mainFolderId);

      if (existingLatest != null && existingLatest.id != null) {
        // Find or delete older previous backup if any, and rotate latest -> previous
        final existingPrevious = await _findFileByName(api, previousFileName,
            parentFolderId: mainFolderId);
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

      // Step 2: Upload new backup as ExamVault_Latest_Backup.json inside ExamVault folder
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
      if (mainFolderId != null) {
        newFileMetadata.parents = [mainFolderId];
      }

      await api.files.create(
        newFileMetadata,
        uploadMedia: media,
      );

      debugPrint('Backup successfully synced to Google Drive in ExamVault folder!');
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
    final mainFolderId = await _getOrCreateMainFolder(api);
    final file =
        await _findFileByName(api, targetName, parentFolderId: mainFolderId);
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

  /// Uploads or updates a PDF file on Google Drive inside ExamVault/Documents folder.
  /// Returns the Google Drive file ID.
  Future<String?> uploadPdfFile({
    required File file,
    required String remoteFileName,
  }) async {
    final api = await _getDriveApi();
    if (api == null) return null;

    try {
      if (!await file.exists()) {
        debugPrint('Local PDF file does not exist: ${file.path}');
        return null;
      }

      final folderId = await _getOrCreateDocumentsFolder(api);
      final length = await file.length();
      final media = drive.Media(
        file.openRead(),
        length,
        contentType: 'application/pdf',
      );

      // Search if a file with this name already exists in this folder
      String query = "name = '$remoteFileName' and trashed = false";
      if (folderId != null) {
        query += " and '$folderId' in parents";
      }
      final existing = await api.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (existing.files != null && existing.files!.isNotEmpty) {
        final existingId = existing.files!.first.id!;
        final updated = await api.files.update(
          drive.File()..name = remoteFileName,
          existingId,
          uploadMedia: media,
        );
        return updated.id ?? existingId;
      } else {
        final newFile = drive.File()
          ..name = remoteFileName
          ..mimeType = 'application/pdf'
          ..description = 'Exam Vault Document';
        if (folderId != null) {
          newFile.parents = [folderId];
        }
        final created = await api.files.create(
          newFile,
          uploadMedia: media,
        );
        return created.id;
      }
    } catch (e) {
      debugPrint('Error uploading PDF to Drive ($remoteFileName): $e');
      return null;
    }
  }

  /// Downloads a PDF file from Google Drive to local storage
  Future<File?> downloadPdfFile({
    required String fileId,
    required String localDestinationPath,
  }) async {
    final api = await _getDriveApi();
    if (api == null) return null;

    try {
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );

      if (media is drive.Media) {
        final targetFile = File(localDestinationPath);
        if (!await targetFile.parent.exists()) {
          await targetFile.parent.create(recursive: true);
        }
        final sink = targetFile.openWrite();
        await media.stream.pipe(sink);
        await sink.flush();
        await sink.close();
        return targetFile;
      }
      return null;
    } catch (e) {
      debugPrint('Error downloading PDF from Drive ($fileId): $e');
      return null;
    }
  }

  /// Deletes a file from Google Drive
  Future<bool> deleteFileFromDrive(String fileId) async {
    final api = await _getDriveApi();
    if (api == null) return false;
    try {
      await api.files.delete(fileId);
      return true;
    } catch (e) {
      debugPrint('Error deleting file from Drive ($fileId): $e');
      return false;
    }
  }
}
