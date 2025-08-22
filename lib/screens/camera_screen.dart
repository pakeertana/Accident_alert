import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/detection_service.dart';

class CameraScreen extends StatefulWidget {
  final String serverUrl;
  const CameraScreen({super.key, required this.serverUrl});
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late DetectionService _detService;
  Timer? _timer;
  bool _busy = false; // avoid concurrent takes

  @override
  void initState() {
    super.initState();
    _detService = DetectionService(widget.serverUrl);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final cam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
    _controller = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
    await _controller.initialize();
    setState(() {});
    _startPeriodicCapture();
  }

  void _startPeriodicCapture() {
    _timer = Timer.periodic(Duration(milliseconds: 1000), (t) async {
      if (!_controller.value.isInitialized || _controller.value.isTakingPicture || _busy) return;
      _busy = true;
      try {
        XFile xfile = await _controller.takePicture();
        final detections = await _detService.sendImage(File(xfile.path));
        // check for accident label (adjust label check to your model)
        bool accident = detections.any((d) {
          final lbl = d['label']?.toString().toLowerCase() ?? '';
          final conf = (d['conf'] is num) ? d['conf'] as num : double.tryParse(d['conf'].toString()) ?? 0;
          return lbl.contains('accident') && conf > 0.5;
        });
        if (accident) {
          _onAccidentDetected(detections);
        }
      } catch (e) {
        print('Error during capture/detect: $e');
      } finally {
        _busy = false;
      }
    });
  }

  void _onAccidentDetected(List<Map<String, dynamic>> detections) {
    // TODO: trigger Step 2 - voice prompt logic
    print('ACCIDENT DETECTED! -> $detections');
    // call your app flow to show prompt / start TTS / etc.
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) return Center(child: CircularProgressIndicator());
    return Scaffold(
      appBar: AppBar(title: Text('Camera')),
      body: CameraPreview(_controller),
    );
  }
}
