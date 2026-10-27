import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/notification_constants.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/notification/notification_service.dart';

class SettingsState {
  final String officeWifiSsid;
  final int dinnerHour;
  final int dinnerMinute;
  final String geminiApiKey;
  final String geminiModel;
  final String lastCheckInStatus;
  final String lastMealResponse;
  final bool isWifiMonitoringActive;
  final bool isWeaknessHealingEnabled;
  final List<int>
  offDays; // Weekday integers: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun

  SettingsState({
    required this.officeWifiSsid,
    required this.dinnerHour,
    required this.dinnerMinute,
    required this.geminiApiKey,
    this.geminiModel = 'gemini-flash-lite-latest',
    required this.lastCheckInStatus,
    required this.lastMealResponse,
    required this.isWifiMonitoringActive,
    this.isWeaknessHealingEnabled = true,
    this.offDays = const [DateTime.thursday, DateTime.friday],
  });

  bool get isTodayOffDay => offDays.contains(DateTime.now().weekday);

  List<String> get officeWifiSsids {
    if (officeWifiSsid.trim().isEmpty) {
      return ['ZaviSoft', 'Secreat Star', 'SecretStar'];
    }
    return officeWifiSsid
        .split(',')
        .map((s) => s.replaceAll('"', '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  SettingsState copyWith({
    String? officeWifiSsid,
    int? dinnerHour,
    int dinnerMinute = 0,
    String? geminiApiKey,
    String? geminiModel,
    String? lastCheckInStatus,
    String? lastMealResponse,
    bool? isWifiMonitoringActive,
    bool? isWeaknessHealingEnabled,
    List<int>? offDays,
  }) {
    return SettingsState(
      officeWifiSsid: officeWifiSsid ?? this.officeWifiSsid,
      dinnerHour: dinnerHour ?? this.dinnerHour,
      dinnerMinute: dinnerMinute,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      geminiModel: geminiModel ?? this.geminiModel,
      lastCheckInStatus: lastCheckInStatus ?? this.lastCheckInStatus,
      lastMealResponse: lastMealResponse ?? this.lastMealResponse,
      isWifiMonitoringActive:
          isWifiMonitoringActive ?? this.isWifiMonitoringActive,
      isWeaknessHealingEnabled:
          isWeaknessHealingEnabled ?? this.isWeaknessHealingEnabled,
      offDays: offDays ?? this.offDays,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  @override
  Future<SettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final mealDate = prefs.getString(
      NotificationConstants.prefLastMealResponseDate,
    );
    final checkinDate = prefs.getString(
      NotificationConstants.prefLastCheckInDate,
    );

    final mealResponse = (mealDate == today)
        ? (prefs.getString(NotificationConstants.prefLastMealResponse) ??
              'Pending')
        : 'Pending';

    final checkInStatus = (checkinDate == today)
        ? (prefs.getString(NotificationConstants.prefLastCheckInStatus) ??
              'Pending')
        : 'Pending';

    final offDaysStr = prefs.getString(NotificationConstants.prefOffDays);
    final offDays = (offDaysStr == null || offDaysStr.isEmpty)
        ? [DateTime.thursday, DateTime.friday]
        : offDaysStr
              .split(',')
              .map((s) => int.tryParse(s.trim()))
              .whereType<int>()
              .toList();

    var savedModel =
        prefs.getString(NotificationConstants.prefGeminiModel) ??
        'gemini-flash-lite-latest';
    if (![
      'gemini-flash-lite-latest',
      'gemini-flash-latest',
      'gemini-pro-latest',
    ].contains(savedModel)) {
      savedModel = 'gemini-flash-lite-latest';
      await prefs.setString(NotificationConstants.prefGeminiModel, savedModel);
    }

    return SettingsState(
      officeWifiSsid:
          prefs.getString(NotificationConstants.prefOfficeWifiSsid) ??
          'ZaviSoft, Secreat Star, SecretStar',
      dinnerHour: prefs.getInt(NotificationConstants.prefDinnerHour) ?? 16,
      dinnerMinute: prefs.getInt(NotificationConstants.prefDinnerMinute) ?? 0,
      geminiApiKey:
          prefs.getString(NotificationConstants.prefGeminiApiKey) ?? '',
      geminiModel: savedModel,
      lastCheckInStatus: checkInStatus,
      lastMealResponse: mealResponse,
      isWifiMonitoringActive: true,
      isWeaknessHealingEnabled:
          prefs.getBool(NotificationConstants.prefWeaknessHealingEnabled) ??
          true,
      offDays: offDays,
    );
  }

  Future<void> setWeaknessHealingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      NotificationConstants.prefWeaknessHealingEnabled,
      enabled,
    );
    state = AsyncValue.data(
      state.value!.copyWith(isWeaknessHealingEnabled: enabled),
    );
  }

  Future<void> updateOffDays(List<int> days) async {
    final prefs = await SharedPreferences.getInstance();
    final joined = days.join(',');
    await prefs.setString(NotificationConstants.prefOffDays, joined);
    state = AsyncValue.data(state.value!.copyWith(offDays: days));
  }

  Future<void> updateGeminiModel(String modelName) async {
    await GeminiAiService.instance.setModel(modelName);
    state = AsyncValue.data(state.value!.copyWith(geminiModel: modelName));
  }

  Future<void> updateOfficeWifiSsid(String ssid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      NotificationConstants.prefOfficeWifiSsid,
      ssid.trim(),
    );
    state = AsyncValue.data(state.value!.copyWith(officeWifiSsid: ssid.trim()));
  }

  Future<void> addOfficeWifiSsid(String newSsid) async {
    final clean = newSsid.replaceAll('"', '').trim();
    if (clean.isEmpty) return;

    final currentList = state.value?.officeWifiSsids.toList() ?? [];
    if (!currentList.any((s) => s.toLowerCase() == clean.toLowerCase())) {
      currentList.add(clean);
      final combined = currentList.join(', ');
      await updateOfficeWifiSsid(combined);
    }
  }

  Future<void> removeOfficeWifiSsid(String targetSsid) async {
    final currentList = state.value?.officeWifiSsids.toList() ?? [];
    currentList.removeWhere(
      (s) => s.toLowerCase() == targetSsid.toLowerCase().trim(),
    );
    final combined = currentList.isEmpty ? 'Zavisoft' : currentList.join(', ');
    await updateOfficeWifiSsid(combined);
  }

  Future<void> updateDinnerTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NotificationConstants.prefDinnerHour, hour);
    await prefs.setInt(NotificationConstants.prefDinnerMinute, minute);

    // Reschedule daily notification
    await NotificationService.instance.scheduleDailyDinnerReminder(
      hour: hour,
      minute: minute,
    );

    state = AsyncValue.data(
      state.value!.copyWith(dinnerHour: hour, dinnerMinute: minute),
    );
  }

  Future<void> updateGeminiApiKey(String key) async {
    await GeminiAiService.instance.saveApiKey(key);
    state = AsyncValue.data(state.value!.copyWith(geminiApiKey: key.trim()));
  }

  Future<void> updateCheckInStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (status == 'Pending') {
      await prefs.remove(NotificationConstants.prefLastCheckInStatus);
      await prefs.remove(NotificationConstants.prefLastCheckInDate);
    } else {
      await prefs.setString(
        NotificationConstants.prefLastCheckInStatus,
        status,
      );
      await prefs.setString(NotificationConstants.prefLastCheckInDate, today);
    }
    state = AsyncValue.data(state.value!.copyWith(lastCheckInStatus: status));
  }

  Future<void> updateMealResponse(String response) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (response == 'Pending') {
      await prefs.remove(NotificationConstants.prefLastMealResponse);
      await prefs.remove(NotificationConstants.prefLastMealResponseDate);
    } else {
      await prefs.setString(
        NotificationConstants.prefLastMealResponse,
        response,
      );
      await prefs.setString(
        NotificationConstants.prefLastMealResponseDate,
        today,
      );
    }
    state = AsyncValue.data(state.value!.copyWith(lastMealResponse: response));
  }

  Future<void> reloadStatus() async {
    ref.invalidateSelf();
  }
}

final settingsNotifierProvider =
    AsyncNotifierProvider<SettingsNotifier, SettingsState>(() {
      return SettingsNotifier();
    });
