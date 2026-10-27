import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../database/app_database.dart';
import '../ai/models/parsed_routine_item.dart';
import '../ai/routine_parser_service.dart';

enum SharingImportStatus { idle, analyzing, success, error }

class SharingImportState {
  final SharingImportStatus status;
  final String? message;
  final List<ParsedRoutineItem> parsedItems;

  SharingImportState({
    required this.status,
    this.message,
    this.parsedItems = const [],
  });

  factory SharingImportState.idle() =>
      SharingImportState(status: SharingImportStatus.idle);

  factory SharingImportState.analyzing(String message) => SharingImportState(
    status: SharingImportStatus.analyzing,
    message: message,
  );

  factory SharingImportState.success(List<ParsedRoutineItem> items) =>
      SharingImportState(
        status: SharingImportStatus.success,
        parsedItems: items,
      );

  factory SharingImportState.error(String error) =>
      SharingImportState(status: SharingImportStatus.error, message: error);
}

class SharingIntentService {
  SharingIntentService._();
  static final SharingIntentService instance = SharingIntentService._();

  StreamSubscription<List<SharedMediaFile>>? _intentSubscription;
  final StreamController<SharingImportState> _stateController =
      StreamController<SharingImportState>.broadcast();
  Stream<SharingImportState> get stateStream => _stateController.stream;

  AppDatabase? _db;
  bool _isListening = false;

  void init(AppDatabase database) {
    _db = database;
    if (_isListening) return;
    _isListening = true;

    // 1. Listen to shared media in background-to-foreground stream
    _intentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _processSharedMedia(files);
        }
      },
      onError: (err) {
        debugPrint('ReceiveSharingIntent stream error: $err');
      },
    );

    // 2. Handle cold start initial media
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> files) {
          if (files.isNotEmpty) {
            _processSharedMedia(files);
          }
        })
        .catchError((err) {
          debugPrint('ReceiveSharingIntent initialMedia error: $err');
        });
  }

  Future<void> _processSharedMedia(List<SharedMediaFile> files) async {
    final firstFile = files.first;
    debugPrint(
      'Processing shared media: type=${firstFile.type}, path=${firstFile.path}',
    );

    final isPdf =
        firstFile.path.toLowerCase().endsWith('.pdf') ||
        firstFile.mimeType == 'application/pdf';

    _stateController.add(
      SharingImportState.analyzing(
        isPdf
            ? 'Analyzing LiveMCQ routine PDF with Gemini Vision...'
            : (firstFile.type == SharedMediaType.image
                  ? 'Analyzing routine image with Gemini Vision...'
                  : 'Parsing routine text with Gemini...'),
      ),
    );

    try {
      List<ParsedRoutineItem> parsedItems = [];

      if (isPdf) {
        final pdfFile = File(firstFile.path);
        if (await pdfFile.exists()) {
          parsedItems = await RoutineParserService.instance.parseRoutineFromPdf(
            pdfFile,
          );
        } else {
          throw Exception('Shared PDF file not found on disk.');
        }
      } else if (firstFile.type == SharedMediaType.image ||
          _isImagePath(firstFile.path)) {
        final imageFile = File(firstFile.path);
        if (await imageFile.exists()) {
          parsedItems = await RoutineParserService.instance
              .parseRoutineFromImage(imageFile);
        } else {
          throw Exception('Shared image file not found on disk.');
        }
      } else {
        // Text / URL / Plain String
        final textContent = firstFile.path;
        parsedItems = await RoutineParserService.instance.parseRoutineFromText(
          textContent,
        );
      }

      if (parsedItems.isNotEmpty && _db != null) {
        await RoutineParserService.instance.saveParsedRoutinesToDatabase(
          _db!,
          parsedItems,
        );
        _stateController.add(SharingImportState.success(parsedItems));
        debugPrint(
          'Successfully imported ${parsedItems.length} exam routines into local database',
        );
      } else {
        _stateController.add(
          SharingImportState.error(
            'Could not extract any valid exam schedules.',
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing shared routine: $e');
      _stateController.add(
        SharingImportState.error('Failed to parse routine: $e'),
      );
    } finally {
      // Reset intent so it does not re-trigger on subsequent resume
      await ReceiveSharingIntent.instance.reset();
    }
  }

  bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  void dispose() {
    _intentSubscription?.cancel();
    _intentSubscription = null;
    _isListening = false;
  }
}
