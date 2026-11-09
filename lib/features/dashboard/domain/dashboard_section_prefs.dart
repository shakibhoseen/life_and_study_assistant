import 'package:shared_preferences/shared_preferences.dart';

/// Whether the dashboard's backward-looking sections are opened up.
///
/// The heatmap is the tallest thing on the dashboard and it answers a question
/// about the last fourteen weeks — useful once a week, in the way of everything
/// else every day. The streak it badges is already shown at the top of the
/// screen, so folded away it loses nothing you cannot get back with one tap.
///
/// Kept here rather than in the widget's own state because a section that
/// springs back open on every rebuild is not folded, it is annoyed.
class DashboardSectionPrefs {
  const DashboardSectionPrefs._();

  static const heatmapExpandedKey = 'dashboard_heatmap_expanded';

  /// Folded by default: it is history, and the day's work is the point of the
  /// screen. Somebody who wants it open says so once.
  static const heatmapExpandedByDefault = false;

  static Future<bool> heatmapExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(heatmapExpandedKey) ?? heatmapExpandedByDefault;
  }

  static Future<void> setHeatmapExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(heatmapExpandedKey, value);
  }
}
