import 'dart:developer';
import 'dart:io';
// import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';

import 'object_detection.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aplikasi Pengenalan Uang Kertas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pinkAccent),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  ObjectDetection? objectDetection;
  FlutterTts flutterTts = FlutterTts();
  late CameraController _controller;
  XFile? _imageFile;
  Uint8List? analyzedImage;
  String? labelString;
  List<String>? label;
  bool _showAnalyzedImage = false;
  bool _cameraInitialized = false;

  @override
  void initState() {
    super.initState();
    objectDetection = ObjectDetection();
    _initCamera();
    _speak('selamat datang di aplikasi pengenalan uang kertas rupiah');
  }

  _initCamera() async {
    if (await Permission.camera.request().isGranted) {
      final cameras = await availableCameras();
      _controller = CameraController(cameras[0], ResolutionPreset.medium);
      await _controller.initialize();
      setState(() {
        _cameraInitialized = true;
      });
    } else {
      log("Permission denied");
    }
  }

  Future<void> _speak(String text) async {
    await flutterTts.setLanguage("id-ID");
    await flutterTts.speak(text);
  }

  Future<void> _takePicture() async {
    //ambil gambar
    final XFile image = await _controller.takePicture();
    setState(() {
      _imageFile = image;
    });
  }

  Future<void> _detectCurrency() async {
    if (_imageFile == null) return;

    final imageMap = File(_imageFile!.path);

    final analystResult = objectDetection!.analyseImage(imageMap.path);

    setState(() {
      labelString = analystResult.labelString; //hasil nominal
      analyzedImage = analystResult.image;
      label = analystResult.label;
      _showAnalyzedImage = true;
    });

    if (labelString == '') {
      _speak('nominal uang tidak dikenali silakan coba lagi');
    } else {
      _speak('$labelString rupiah');
    }

    Future.delayed(const Duration(seconds: 5), () {
      setState(() {
        _showAnalyzedImage = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await _takePicture();
        await _detectCurrency();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Aplikasi Pengenalan Uang Kertas"),
          backgroundColor: const Color.fromARGB(255, 228, 142, 178),
        ),
        body: _cameraInitialized
            ? Column(
                children: [
                  Expanded(
                    child: _showAnalyzedImage
                        ? Image.memory(analyzedImage!)
                        : _controller.value.isInitialized
                            ? CameraPreview(_controller)
                            : const Center(child: CircularProgressIndicator()),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (labelString != null)
                          Container(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              labelString == ''
                                  ? 'tidak dikenali'
                                  : '$labelString rupiah',
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (label != null)
                          Container(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              label.toString(),
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
