import "package:shared_preferences/shared_preferences.dart";
import "planner.dart";

class SettingsStore {
  SettingsStore(this.mode, this.internalBufferGb, this.sdBufferMb);

  Mode mode;
  double internalBufferGb;
  int sdBufferMb;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString("mode") ?? "hybrid";
    final mode = Mode.values.firstWhere((item) => item.name == modeName, orElse: () => Mode.hybrid);
    return SettingsStore(mode, prefs.getDouble("internalBufferGb") ?? 5, prefs.getInt("sdBufferMb") ?? 500);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("mode", mode.name);
    await prefs.setDouble("internalBufferGb", internalBufferGb);
    await prefs.setInt("sdBufferMb", sdBufferMb);
  }
}
