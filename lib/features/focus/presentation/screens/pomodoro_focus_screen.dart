import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/database/tables/daily_energy_logs_table.dart';
import '../../../quiz/presentation/widgets/study_sheet_camera_modal.dart';
import '../../../spaced_repetition/presentation/screens/spaced_repetition_screen.dart';

enum FocusMode {
  micro15(15, 'Micro Focus (Tired Day)', 'Quick 15-min sprint after work'),
  standard25(25, 'Standard Pomodoro', 'Classic 25-min focused study block'),
  deep45(45, 'Deep Study Session', 'Intensive 45-min distraction-free block'),
  break5(5, 'Short Refresh Break', '5-min rest for your eyes');

  final int minutes;
  final String title;
  final String description;
  const FocusMode(this.minutes, this.title, this.description);
}

enum AmbientSound {
  off('Mute / Silent', 'No ambient noise', null, Icons.volume_off),
  rain(
    'Gentle Rain',
    'Soft rainfall for coding and reading',
    'https://assets.mixkit.co/active_storage/sfx/1258/1258-preview.mp3',
    Icons.grain,
  ),
  brownNoise(
    'Brown Noise',
    'Deep low-frequency hum for mental focus',
    'https://assets.mixkit.co/active_storage/sfx/2432/2432-preview.mp3',
    Icons.headphones,
  ),
  stream(
    'Forest Stream',
    'Flowing water in nature for peace',
    'https://assets.mixkit.co/active_storage/sfx/1260/1260-preview.mp3',
    Icons.water,
  );

  final String title;
  final String subtitle;
  final String? audioUrl;
  final IconData icon;
  const AmbientSound(this.title, this.subtitle, this.audioUrl, this.icon);
}

class PomodoroFocusScreen extends ConsumerStatefulWidget {
  const PomodoroFocusScreen({super.key});

  @override
  ConsumerState<PomodoroFocusScreen> createState() =>
      _PomodoroFocusScreenState();
}

class _PomodoroFocusScreenState extends ConsumerState<PomodoroFocusScreen> {
  FocusMode _selectedMode = FocusMode.micro15;
  AmbientSound _selectedSound = AmbientSound.off;
  late int _remainingSeconds;
  Timer? _timer;
  bool _isRunning = false;
  AudioPlayer? _audioPlayer;
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = _selectedMode.minutes * 60;
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _audioPlayer?.setReleaseMode(ReleaseMode.loop);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    super.dispose();
  }

  void _setMode(FocusMode mode) {
    if (_isRunning) return;
    setState(() {
      _selectedMode = mode;
      _remainingSeconds = mode.minutes * 60;
    });
  }

  Future<void> _changeAmbientSound(AmbientSound sound) async {
    setState(() {
      _selectedSound = sound;
    });

    if (!_isRunning) return;

    if (sound == AmbientSound.off || sound.audioUrl == null) {
      await _audioPlayer?.stop();
      setState(() => _isPlayingAudio = false);
    } else {
      try {
        await _audioPlayer?.stop();
        await _audioPlayer?.play(UrlSource(sound.audioUrl!));
        setState(() => _isPlayingAudio = true);
      } catch (e) {
        debugPrint('Audio playback error (offline or unreachable): $e');
        setState(() => _isPlayingAudio = false);
      }
    }
  }

  void _startTimer() {
    setState(() {
      _isRunning = true;
    });

    if (_selectedSound != AmbientSound.off && _selectedSound.audioUrl != null) {
      _audioPlayer?.play(UrlSource(_selectedSound.audioUrl!)).catchError((e) {
        debugPrint('Ambient audio error: $e');
      });
      setState(() => _isPlayingAudio = true);
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
        _onSessionComplete();
      }
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    _audioPlayer?.pause();
    setState(() {
      _isRunning = false;
      _isPlayingAudio = false;
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    _audioPlayer?.stop();
    setState(() {
      _isRunning = false;
      _isPlayingAudio = false;
      _remainingSeconds = _selectedMode.minutes * 60;
    });
  }

  Future<void> _onSessionComplete() async {
    _audioPlayer?.stop();
    setState(() {
      _isRunning = false;
      _isPlayingAudio = false;
    });

    // Log completed session to database
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final existingLog = await db.getTodayLog(today);
    final completedMinutes = _selectedMode.minutes;
    final taskDescription =
        'Pomodoro: Completed $completedMinutes min (${_selectedMode.title})';

    List<String> tasks = [];
    if (existingLog != null) {
      try {
        final decoded = List<String>.from(
          (existingLog.completedTasks as dynamic),
        );
        tasks = decoded;
      } catch (_) {
        tasks = [];
      }
    }
    tasks.add(taskDescription);

    await db.insertOrUpdateDailyLog(
      DailyEnergyLogsCompanion(
        date: Value(today),
        energyLevel: Value(existingLog?.energyLevel ?? EnergyLevel.medium),
        officeFatigueScore: Value(existingLog?.officeFatigueScore ?? 5),
        completedTasks: Value(tasks.toString()),
        notes: Value(existingLog?.notes),
      ),
    );

    if (mounted) {
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium, color: Color(0xFFF59E0B), size: 28),
            SizedBox(width: 10),
            Text('Session Finished! 🎯'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Awesome work! You completed ${_selectedMode.minutes} minutes of distraction-free study.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '+${_selectedMode.minutes * 2} XP logged to your Daily Heatmap Streak!',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetTimer();
            },
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              StudySheetCameraModal.show(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('Snap Book Page to Drill'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalModeSeconds = _selectedMode.minutes * 60;
    final progress = totalModeSeconds > 0
        ? (totalModeSeconds - _remainingSeconds) / totalModeSeconds
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomodoro Focus & Study Timer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bolt_outlined),
            tooltip: 'Office Flashcards',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SpacedRepetitionScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Mode Selector Segmented Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: FocusMode.values.map((mode) {
                  final isSelected = _selectedMode == mode;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        '${mode.minutes}m - ${mode.name.toUpperCase()}',
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFF1E3A8A),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.grey.shade300 : Colors.black87),
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: _isRunning ? null : (_) => _setMode(mode),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _selectedMode.description,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),

            // Circular Countdown Dial
            Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        backgroundColor: isDark
                            ? const Color(0xFF1F2937)
                            : Colors.grey.shade200,
                        color: _selectedMode == FocusMode.break5
                            ? const Color(0xFF10B981)
                            : const Color(0xFF6366F1),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(_remainingSeconds),
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isRunning
                                    ? const Color(0xFF10B981)
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isRunning ? 'FOCUSING' : 'PAUSED',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 36),

            // Main Controls: Play, Pause, Reset
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: _resetTimer,
                  icon: const Icon(Icons.refresh, size: 24),
                  tooltip: 'Reset',
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: FloatingActionButton(
                    heroTag: 'pomodoro_play_pause',
                    onPressed: _isRunning ? _pauseTimer : _startTimer,
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    elevation: 4,
                    child: Icon(
                      _isRunning ? Icons.pause : Icons.play_arrow,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                IconButton.filledTonal(
                  onPressed: () => _changeAmbientSound(
                    _selectedSound == AmbientSound.off
                        ? AmbientSound.rain
                        : AmbientSound.off,
                  ),
                  icon: Icon(
                    _isPlayingAudio ? Icons.volume_up : Icons.volume_off,
                    size: 24,
                    color: _isPlayingAudio ? const Color(0xFF6366F1) : null,
                  ),
                  tooltip: 'Toggle Ambient Audio',
                ),
              ],
            ),
            const SizedBox(height: 36),

            // Ambient Sound Selection Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1F2937)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF374151)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.headphones,
                        size: 20,
                        color: Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Ambient Focus Sound',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_isPlayingAudio)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.graphic_eq,
                                size: 14,
                                color: Color(0xFF10B981),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Playing',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...AmbientSound.values.map((sound) {
                    final isSelected = _selectedSound == sound;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        sound.icon,
                        color: isSelected
                            ? const Color(0xFF6366F1)
                            : Colors.grey,
                        size: 22,
                      ),
                      title: Text(
                        sound.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? const Color(0xFF6366F1) : null,
                        ),
                      ),
                      subtitle: Text(
                        sound.subtitle,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFF6366F1),
                              size: 18,
                            )
                          : null,
                      onTap: () => _changeAmbientSound(sound),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
