// lib/pages/sensors_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';

class SensorsPage extends StatefulWidget {
  static const route = '/sensors';
  const SensorsPage({super.key});

  @override
  State<SensorsPage> createState() => _SensorsPageState();
}

class _SensorsPageState extends State<SensorsPage> {
  // UI values
  String _accel = '';
  String _gyro = '';
  String _status = 'Monitoring…';

  // Control flags
  bool _alerting = false;
  Timer? _confirmTimer;

  // Streams
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _ensurePermissions(); // ask for SMS + location on Android
    _startSensors(); // begin listening
  }

  Future<void> _ensurePermissions() async {
    // Location permission
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(
        () => _status = 'Enable Location Services to send location in alerts.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      setState(
        () => _status =
            'Location permission denied forever. Open Settings to enable.',
      );
    }

    // SMS permission (Android only)
    if (_isAndroid) {
      final telephony = Telephony.instance;
      // This is a *getter* in the telephony package
      final granted = await telephony.requestSmsPermissions;
      if (granted != true) {
        setState(() => _status = 'SMS permission not granted.');
      }
    }
  }

  void _startSensors() {
    _accelSub = accelerometerEventStream().listen((e) {
      setState(() {
        _accel =
            'X:${e.x.toStringAsFixed(2)}  Y:${e.y.toStringAsFixed(2)}  Z:${e.z.toStringAsFixed(2)}';
      });

      // Simple impact heuristic
      if (!_alerting && (e.x.abs() > 30 || e.y.abs() > 30 || e.z.abs() > 30)) {
        _onPossibleAccident('Accelerometer spike');
      }
    });

    _gyroSub = gyroscopeEventStream().listen((g) {
      setState(() {
        _gyro =
            'X:${g.x.toStringAsFixed(2)}  Y:${g.y.toStringAsFixed(2)}  Z:${g.z.toStringAsFixed(2)}';
      });

      if (!_alerting && (g.x.abs() > 15 || g.y.abs() > 15 || g.z.abs() > 15)) {
        _onPossibleAccident('Gyroscope spike');
      }
    });
  }

  void _onPossibleAccident(String reason) {
    _alerting = true;
    setState(() => _status = '⚠️ $reason\nAsking if you are safe…');

    // 5s confirmation window
    _confirmTimer?.cancel();
    _confirmTimer = Timer(const Duration(seconds: 5), () {
      // If still alerting after 5s (user didn’t cancel), send alert
      if (_alerting) _triggerAlert(reason);
    });

    // Show a snack so the user can cancel fast
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Possible accident detected. Sending alert in 5s…',
          ),
          action: SnackBarAction(label: 'I\'m OK', onPressed: _cancelAlert),
        ),
      );
    }
  }

  void _cancelAlert() {
    _confirmTimer?.cancel();
    _alerting = false;
    setState(() => _status = '✅ Alert cancelled. Monitoring…');
  }

  Future<void> _triggerAlert(String reason) async {
    // Don’t try to send SMS when not on Android
    if (!_isAndroid) {
      setState(() {
        _status = '🚨 (Simulated) Would send SMS (Android only).';
        _alerting = false;
      });
      debugPrint('[ALERT] Simulated on non-Android | Reason: $reason');
      return;
    }

    final telephony = Telephony.instance;

    try {
      // Current position (no deprecated args)
      final position = await Geolocator.getCurrentPosition();
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';

      // TODO: replace with your real number(s)
      const emergencyNumber = '+918618338400';

      final message =
          '🚨 Accident Detected!\nReason: $reason\nLocation: $mapsUrl\nPlease send help immediately.';

      await telephony.sendSms(to: emergencyNumber, message: message);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ SMS alert sent to emergency contact.'),
          ),
        );
      }
      debugPrint('✅ SMS sent with location: $mapsUrl');
      setState(() => _status = '🚨 Alert sent');
    } catch (e) {
      debugPrint('❌ Failed to send SMS: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ SMS sending failed: $e')));
      }
      setState(() => _status = '❌ Failed to send alert');
    } finally {
      _alerting = false;
    }
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final danger =
        _status.contains('⚠️') ||
        _status.contains('🚨') ||
        _status.contains('❌');
    return Scaffold(
      appBar: AppBar(title: const Text('Sensors Data')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Accelerometer:', style: TextStyle(fontSize: 18)),
              Text(_accel, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              const Text('Gyroscope:', style: TextStyle(fontSize: 18)),
              Text(_gyro, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: danger ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              if (_alerting)
                FilledButton(
                  onPressed: _cancelAlert,
                  child: const Text('I\'m OK — Cancel Alert'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
