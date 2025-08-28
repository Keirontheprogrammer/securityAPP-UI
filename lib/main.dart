import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartSecurityApp());
}

const String ESP_IP = "10.160.145.186";
const int ESP_PORT = 80;

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
  final String reason;
  final String type;

  AlarmRecord({
    required this.id,
    required this.timestamp,
    required this.reason,
    required this.type,
  });
}

class SecurityHome extends StatefulWidget {
  const SecurityHome({super.key});

  @override
  State<SecurityHome> createState() => _SecurityHomeState();
}

class _SecurityHomeState extends State<SecurityHome>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<AlarmRecord> alarmHistory = [];

  bool awayModeActive = false;
  bool securityModeActive = false;
  String lastMessage = "System Ready";

  Socket? _socket;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _connectToEsp();
  }

  @override
  void dispose() {
    _tab.dispose();
    _socket?.destroy();
    super.dispose();
  }

  Future<void> _connectToEsp() async {
    try {
      _socket = await Socket.connect(ESP_IP, ESP_PORT);
      _socket!.listen((data) {
        final msg = utf8.decode(data).trim();
        setState(() => lastMessage = msg);
        _addAlertToHistory(msg);
      }, onDone: () {
        print("Disconnected from ESP");
      }, onError: (e) {
        print("Socket error: $e");
      });
    } catch (e) {
      print("Failed to connect: $e");
    }
  }

  void _sendCommand(String cmd) {
    _socket?.write(cmd + '\n');
  }

  void _addAlertToHistory(String msg) {
    setState(() {
      alarmHistory.add(AlarmRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        reason: msg,
        type: msg.contains("Away") ? "away" : "security",
      ));
    });
  }

  void clearAlarmHistory() {
    setState(() => alarmHistory.clear());
  }

  Future<void> _toggleAway(bool val) async {
    _sendCommand(val ? "CMD:AWAY_ON" : "CMD:AWAY_OFF");
    setState(() => awayModeActive = val);
    _addAlertToHistory(val ? "Away mode armed" : "Away mode disarmed");
  }

  Future<void> _toggleSecurity(bool val) async {
    _sendCommand(val ? "CMD:SEC_ON" : "CMD:SEC_OFF");
    setState(() => securityModeActive = val);
    _addAlertToHistory(val ? "Security mode armed" : "Security mode disarmed");
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
          ModeCard(
            icon: Icons.shield,
            title: "Away Mode",
            description: "We are Home safe baby.",
            isActive: awayModeActive,
            onToggle: _toggleAway,
          ),
          ModeCard(
            icon: Icons.warning,
            title: "Security Mode",
            description: "Za okuba zija.",
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                StatusIndicator(label: "Away", active: awayModeActive, color: Colors.blue),
                StatusIndicator(label: "Security", active: securityModeActive, color: Colors.orange),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              lastMessage,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isActive;
  final Future<void> Function(bool) onToggle;

  const ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.isActive,
    required this.onToggle,
  });

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
                  Icon(icon, size: 80, color: isActive ? Colors.redAccent : Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    isActive ? "$title Active" : "$title Inactive",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (val) => onToggle(val),
                    title: Text("Enable $title"),
                  ),
                  const SizedBox(height: 8),
                  Text(description, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
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
    if (history.isEmpty) return const Center(child: Text("No alarms recorded"));
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
