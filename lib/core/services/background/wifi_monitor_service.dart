import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/notification_constants.dart';
import '../notification/notification_service.dart';

enum OfficeConnectionState { connected, disconnected, unknown }

class WifiMonitorService {
  WifiMonitorService._();
  static final WifiMonitorService instance = WifiMonitorService._();

  final Connectivity _connectivity = Connectivity();
  final NetworkInfo _networkInfo = NetworkInfo();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isMonitoring = false;
  bool _wasConnectedToOffice = false;
  Timer? _disconnectionDebounceTimer;
  static const Duration disconnectionGracePeriod = Duration(seconds: 15);

  final StreamController<OfficeConnectionState> _officeStateController =
      StreamController<OfficeConnectionState>.broadcast();
  Stream<OfficeConnectionState> get officeStateStream =>
      _officeStateController.stream;

  OfficeConnectionState _currentState = OfficeConnectionState.unknown;
  OfficeConnectionState get currentState => _currentState;

  String? _currentSsid;
  String? get currentSsid => _currentSsid;

  bool _isWifiHardwareConnected = false;
  bool get isWifiHardwareConnected => _isWifiHardwareConnected;

  /// Returns true when phone is on Wi-Fi, but Android hid the SSID due to missing runtime location permission or GPS toggle.
  bool get isSsidHiddenByAndroid =>
      _isWifiHardwareConnected &&
      (_currentSsid == null ||
          _currentSsid!.isEmpty ||
          _currentSsid == '<unknown ssid>' ||
          _currentSsid == 'unknown ssid');

  /// Requests runtime Notification and Location permissions required by Android for SSID reading.
  Future<bool> requestWifiLocationPermissions() async {
    try {
      final notifStatus = await Permission.notification.request();
      debugPrint('Notification permission status: $notifStatus');

      final locStatus = await Permission.location.request();
      debugPrint('Location permission status: $locStatus');

      await checkCurrentWifiStatus();
      return locStatus.isGranted;
    } catch (e) {
      debugPrint('Error requesting Wi-Fi location permissions: $e');
      return false;
    }
  }

  Future<bool> hasLocationPermission() async {
    return await Permission.location.isGranted;
  }

  Future<bool> isLocationServiceEnabled() async {
    return await Permission.location.serviceStatus.isEnabled;
  }

  /// Start monitoring connectivity changes
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;

    // Check initial state
    await checkCurrentWifiStatus();

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      await _handleConnectivityChange(results);
    });
  }

  /// Stop monitoring
  void stopMonitoring() {
    _disconnectionDebounceTimer?.cancel();
    _disconnectionDebounceTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isMonitoring = false;
  }

  /// Checks current network and matches against configured office SSID
  Future<void> checkCurrentWifiStatus() async {
    try {
      final results = await _connectivity.checkConnectivity();
      await _handleConnectivityChange(results);
    } catch (e) {
      debugPrint('Error checking Wi-Fi status: $e');
    }
  }

  Future<void> _handleConnectivityChange(
    List<ConnectivityResult> results,
  ) async {
    final isWifi = results.contains(ConnectivityResult.wifi);
    _isWifiHardwareConnected = isWifi;

    final prefs = await SharedPreferences.getInstance();
    final configuredSsid =
        prefs.getString(NotificationConstants.prefOfficeWifiSsid) ??
        'ZaviSoft, Secreat Star, SecretStar';

    if (isWifi) {
      String? ssid;
      try {
        ssid = await _networkInfo.getWifiName();
      } catch (e) {
        debugPrint('Could not obtain SSID: $e');
      }

      // Android getWifiName often returns quoted strings: "MyOfficeWiFi" or "<unknown ssid>"
      if (ssid != null) {
        ssid = ssid.replaceAll('"', '').trim();
        if (ssid == '<unknown ssid>' ||
            ssid == 'unknown ssid' ||
            ssid.isEmpty) {
          ssid = null;
        }
      }
      _currentSsid = ssid;

      final isMatch = _matchesOfficeSsid(ssid, configuredSsid);

      if (isMatch) {
        // Cancel any pending disconnection debounce grace timer immediately
        if (_disconnectionDebounceTimer != null &&
            _disconnectionDebounceTimer!.isActive) {
          debugPrint(
            'Reconnected to office Wi-Fi ($ssid) during grace period. Cancelling checkout timer.',
          );
          _disconnectionDebounceTimer!.cancel();
          _disconnectionDebounceTimer = null;
        }

        _currentState = OfficeConnectionState.connected;
        _officeStateController.add(OfficeConnectionState.connected);

        if (!_wasConnectedToOffice) {
          _wasConnectedToOffice = true;
          await _onOfficeWifiConnected(ssid ?? configuredSsid);
        }
      } else {
        _handleOfficeDisconnection();
      }
    } else {
      _currentSsid = null;
      _handleOfficeDisconnection();
    }
  }

  void _handleOfficeDisconnection() {
    if (_wasConnectedToOffice) {
      // If we are already running a grace period debounce timer, let it run
      if (_disconnectionDebounceTimer != null &&
          _disconnectionDebounceTimer!.isActive) {
        return;
      }

      debugPrint(
        'Office Wi-Fi disconnected or switching network. Starting grace period (15s)...',
      );
      _disconnectionDebounceTimer = Timer(disconnectionGracePeriod, () {
        debugPrint(
          'Office Wi-Fi grace period expired. Confirmed office disconnection.',
        );
        _wasConnectedToOffice = false;
        _currentState = OfficeConnectionState.disconnected;
        _officeStateController.add(OfficeConnectionState.disconnected);
        _onOfficeWifiDisconnected();
        _disconnectionDebounceTimer = null;
      });
    } else {
      _currentState = OfficeConnectionState.disconnected;
      _officeStateController.add(OfficeConnectionState.disconnected);
    }
  }

  /// Parses configured SSIDs separated by comma
  static List<String> parseConfiguredSsids(String? configuredSsid) {
    if (configuredSsid == null || configuredSsid.trim().isEmpty) {
      return ['ZaviSoft', 'Secreat Star', 'SecretStar'];
    }
    return configuredSsid
        .split(',')
        .map((s) => s.replaceAll('"', '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Checks if current SSID matches any configured office network
  static bool isOfficeNetwork(String? currentSsid, String? configuredSsid) {
    if (currentSsid == null || currentSsid.isEmpty) return false;
    final cleanCurrent = currentSsid.replaceAll('"', '').trim().toLowerCase();
    if (cleanCurrent == '<unknown ssid>' || cleanCurrent == 'unknown ssid') {
      return false;
    }
    final allowedList = parseConfiguredSsids(configuredSsid);
    return allowedList.any((allowed) {
      final cleanAllowed = allowed.toLowerCase().trim();
      // 1. Direct case-insensitive match
      if (cleanAllowed == cleanCurrent) return true;
      // 2. Space-insensitive match (e.g. "Secret Star" vs "SecretStar", "Secreat Star" vs "SecreatStar")
      if (cleanAllowed.replaceAll(' ', '') ==
          cleanCurrent.replaceAll(' ', '')) {
        return true;
      }
      return false;
    });
  }

  bool _matchesOfficeSsid(String? currentSsid, String configuredSsid) {
    return isOfficeNetwork(currentSsid, configuredSsid);
  }

  static List<int> parseOffDays(String? offDaysStr) {
    if (offDaysStr == null || offDaysStr.isEmpty) {
      // Default Thursday (4) and Friday (5)
      return [DateTime.thursday, DateTime.friday];
    }
    return offDaysStr
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
  }

  static bool isOffDay(DateTime date, [String? offDaysStr]) {
    final list = parseOffDays(offDaysStr);
    return list.contains(date.weekday);
  }

  Future<void> _onOfficeWifiConnected(String ssid) async {
    final prefs = await SharedPreferences.getInstance();
    final offDaysStr = prefs.getString(NotificationConstants.prefOffDays);

    // Suppress office check-in reminder on off-days (Thursday & Friday)
    if (isOffDay(DateTime.now(), offDaysStr)) {
      debugPrint(
        'Today is an off-day (${DateTime.now().weekday}). Suppressing office check-in alert.',
      );
      return;
    }

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastCheckinDate = prefs.getString(
      NotificationConstants.prefLastCheckInDate,
    );
    final lastCheckinStatus = prefs.getString(
      NotificationConstants.prefLastCheckInStatus,
    );

    // Debounce: fire check-in notification if not already punched in today
    final isAlreadyPunched =
        lastCheckinDate == today &&
        (lastCheckinStatus == 'Punched' || lastCheckinStatus == 'Punched In');

    if (!isAlreadyPunched) {
      debugPrint(
        'Office Wi-Fi connected ($ssid). Triggering check-in reminder.',
      );
      await NotificationService.instance.showOfficeCheckInReminder(
        officeSsid: ssid,
      );
    }
  }

  Future<void> _onOfficeWifiDisconnected() async {
    final prefs = await SharedPreferences.getInstance();
    final offDaysStr = prefs.getString(NotificationConstants.prefOffDays);

    // Suppress office check-out reminder on off-days
    if (isOffDay(DateTime.now(), offDaysStr)) {
      debugPrint('Today is an off-day. Suppressing office check-out alert.');
      return;
    }

    debugPrint(
      'Disconnected from Office Wi-Fi. Triggering check-out reminder.',
    );
    await NotificationService.instance.showOfficeCheckOutReminder();
  }

  /// Simulation helper for manual testing on emulator or at home
  Future<void> simulateOfficeWifiConnection({String? testSsid}) async {
    _disconnectionDebounceTimer?.cancel();
    _disconnectionDebounceTimer = null;
    final prefs = await SharedPreferences.getInstance();
    final configured =
        prefs.getString(NotificationConstants.prefOfficeWifiSsid) ??
        'ZaviSoft, Secreat Star, SecretStar';
    final ssid = testSsid ?? parseConfiguredSsids(configured).first;
    _isWifiHardwareConnected = true;
    _currentSsid = ssid;
    _wasConnectedToOffice = true;
    _currentState = OfficeConnectionState.connected;
    _officeStateController.add(OfficeConnectionState.connected);

    await NotificationService.instance.showOfficeCheckInReminder(
      officeSsid: ssid,
      ignoreOffDay: true,
    );
  }

  /// Simulation helper for manual testing checkout
  Future<void> simulateOfficeWifiDisconnection() async {
    _disconnectionDebounceTimer?.cancel();
    _disconnectionDebounceTimer = null;
    _wasConnectedToOffice = false;
    _isWifiHardwareConnected = false;
    _currentSsid = null;
    _currentState = OfficeConnectionState.disconnected;
    _officeStateController.add(OfficeConnectionState.disconnected);

    await NotificationService.instance.showOfficeCheckOutReminder(
      ignoreOffDay: true,
    );
  }
}
