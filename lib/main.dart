import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartSecurityApp());
}

/// 👉 Set this to your ESP32's IP (static) or mDNS host if you’ve set up MDNS.
/// Examples: "http://192.168.1.72:80" or "http://esp32.local"
const String ESP_BASE_URL = "http://192.168.4.1"; // TODO: change this

class SmartSecurityApp extends StatelessWidget {
  const SmartSecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart House Security',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const SecurityHome(),
    );
  }
}

class AlarmRecord {
  final String id;
  final DateTime timestamp;
  final String reason; // e.g., "Away mode armed"
  final String type;   // "away" or "security"

  AlarmRecord({
    required this.id,
    required this.timestamp,
    required this.reason,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'reason': reason,
    'type': type,
  };

  factory AlarmRecord.fromJson(Map<String, dynamic> json) => AlarmRecord(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    reason: json['reason'] as String,
    type: json['type'] as String,
  );
}

class ApiService {
  final String baseUrl;
  ApiService(this.baseUrl);

  Future<bool> setAway(bool enabled) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/away'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<bool> setSecurity(bool enabled) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/security'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<Map<String, dynamic>?> getStatus() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/status'));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}

class SecurityHome extends StatefulWidget {
  const SecurityHome({super.key});

  @override
  State<SecurityHome> createState() => _SecurityHomeState();
}

class _SecurityHomeState extends State<SecurityHome>
    with SingleTickerProviderStateMixin {
  late final ApiService _api;
  late final TabController _tab;
  final _prefsFuture = SharedPreferences.getInstance();

  // UI state
  bool isWiFiConnected = false;
  String? ssid;
  bool awayModeActive = false;
  bool securityModeActive = false;
  List<AlarmRecord> alarmHistory = [];

  // Wi-Fi watchers
  StreamSubscription<ConnectivityResult>? _connSub;
  final _info = NetworkInfo();

  @override
  void initState() {
    super.initState();
    _api = ApiService(ESP_BASE_URL);
    _tab = TabController(length: 3, vsync: this);

    _loadHistory();
    _initConnectivityWatch();
    _fetchEspStatus(); // try to sync with device on start
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await _prefsFuture;
    final raw = prefs.getStringList('alarmHistory') ?? [];
    setState(() {
      alarmHistory = raw
          .map((s) => AlarmRecord.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await _prefsFuture;
    final raw = alarmHistory.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList('alarmHistory', raw);
  }

  void addAlarmRecord(String reason, String type) {
    setState(() {
      alarmHistory.add(AlarmRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        reason: reason,
        type: type,
      ));
    });
    _saveHistory();
  }

  void clearAlarmHistory() {
    setState(() => alarmHistory.clear());
    _saveHistory();
  }

  void _initConnectivityWatch() async {
    await _updateConnectivityOnce();
    _connSub = Connectivity().onConnectivityChanged.listen((result) async {
      await _updateConnectivityOnce();
    });
  }

  Future<void> _updateConnectivityOnce() async {
    final connectivity = Connectivity();
    final result = await Connectivity().checkConnectivity();
    final connected = (result == ConnectivityResult.wifi) ||
        (result == ConnectivityResult.ethernet);
    String? currentSsid;
    if (connected) {
      try {
        currentSsid = await _info.getWifiName();
      } catch (_) {}
    }
    setState(() {
      isWiFiConnected = connected;
      ssid = currentSsid;
    });
  }

  Future<void> _fetchEspStatus() async {
    final status = await _api.getStatus();
    if (status != null && mounted) {
      setState(() {
        awayModeActive = (status['away'] == true);
        securityModeActive = (status['security'] == true);
      });
    }
  }

  Future<void> _toggleAway(bool val) async {
    if (!isWiFiConnected) {
      _toast('Not connected to Wi-Fi');
      return;
    }
    final ok = await _api.setAway(val);
    if (!ok) {
      _toast('Failed to update Away mode on device');
      return;~~~~~
    }
    setState(() => awayModeActive = val);
    addAlarmRecord(val ? "Away mode armed" : "Away mode disarmed", "away");
  }

  Future<void> _toggleSecurity(bool val) async {
    if (!isWiFiConnected) {
      _toast('Not connected to Wi-Fi');
      return;
    }
    final ok = await _api.setSecurity(val);
    if (!ok) {
      _toast('Failed to update Security mode on device');
      return;
    }
    setState(() => securityModeActive = val);
    addAlarmRecord(val ? "Security mode armed" : "Security mode disarmed", "security");
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart House Security"),
        centerTitle: true,
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.shield), text: "Away"),
            Tab(icon: Icon(Icons.warning), text: "Security"),
            Tab(icon: Icon(Icons.history), text: "History"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          AwayMode(
            isActive: awayModeActive,
            onToggle: _toggleAway,
          ),
          SecurityMode(
            isActive: securityModeActive,
            onToggle: _toggleSecurity,
          ),
          AlarmHistoryView(
            history: alarmHistory,
            onClear: clearAlarmHistory,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: const Color(0xFF1A1C20),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // improved status colors
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                StatusIndicator(label: "Wi-Fi", active: isWiFiConnected, color: Colors.green),
                StatusIndicator(label: "Away", active: awayModeActive, color: Colors.blue),
                StatusIndicator(label: "Security", active: securityModeActive, color: Colors.orange),
              ],
            ),
            const SizedBox(height: 6),
            // show SSID if available
            Text(
              isWiFiConnected
                  ? (ssid == null ? "Connected" : "Connected to $ssid")
                  : "Not connected",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class AwayMode extends StatelessWidget {
  final bool isActive;
  final Future<void> Function(bool) onToggle;

  const AwayMode({super.key, required this.isActive, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28.0, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield, size: 80, color: isActive ? Colors.redAccent : Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    isActive ? "Away Mode Active" : "Away Mode Inactive",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (val) => onToggle(val),
                    title: const Text("Enable Away Mode"),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "When enabled, motion/entry sensors trigger alarms while you’re out.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecurityMode extends StatelessWidget {
  final bool isActive;
  final Future<void> Function(bool) onToggle;

  const SecurityMode({super.key, required this.isActive, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28.0, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning, size: 80, color: isActive ? Colors.orange : Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    isActive ? "Security Mode Active" : "Security Mode Inactive",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (val) => onToggle(val),
                    title: const Text("Enable Security Mode"),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "General security arming (e.g., perimeter sensors).",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AlarmHistoryView extends StatelessWidget {
  final List<AlarmRecord> history;
  final VoidCallback onClear;

  const AlarmHistoryView({super.key, required this.history, required this.onClear});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(child: Text("No alarms recorded"));
    }
    final fmt = DateFormat("yyyy-MM-dd HH:mm:ss");
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: history.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = history[i];
              final icon = r.type == "away" ? Icons.shield : Icons.security;
              final color = r.type == "away" ? Colors.blue : Colors.orange;
              return ListTile(
                leading: Icon(icon, color: color),
                title: Text(r.reason),
                subtitle: Text(fmt.format(r.timestamp)),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline),
            label: const Text("Clear History"),
          ),
        ),
      ],
    );
  }
}

class StatusIndicator extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const StatusIndicator({
    super.key,
    required this.label,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(radius: 6, backgroundColor: active ? color : Colors.grey),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}
