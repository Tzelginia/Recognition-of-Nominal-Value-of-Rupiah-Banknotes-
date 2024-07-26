import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class ImageAnalysisResult {
  final Uint8List image; // inisialisasi variabel image
  final String labelString; // inisialisasi nominal uang
  final List<String> label; // inisialisasi array label kelas

  ImageAnalysisResult(
      {required this.image, required this.labelString, required this.label});
}

class ObjectDetection {
  static const String _modelPath = 'assets/detectv2.tflite'; // model
  static const String _labelPath = 'assets/labelmapv2.txt'; // labelmap

  Interpreter? _interpreter; //inisialisasi interpreter
  List<String>? _labels; // inisia;isasi label

//fungsi load model
  Future<void> _loadModel() async {
    log('Loading interpreter options...');
    final interpreterOptions = InterpreterOptions();

    if (Platform.isAndroid) {
      interpreterOptions.addDelegate(XNNPackDelegate());
    }

    log('Loading interpreter...');
    _interpreter =
        await Interpreter.fromAsset(_modelPath, options: interpreterOptions);
  }

  Future<void> _loadLabels() async {
    log('Loading labels...');
    final labelsRaw = await rootBundle.loadString(_labelPath);
    _labels = labelsRaw.split('\n');
  }

  ObjectDetection() {
    _loadModel();
    _loadLabels();
    log('Done.');
  }

  List<List<Object>> _runInference(
    List<List<List<num>>> imageMatrix,
  ) {
    log('Running inference...');

    // log("image sebelum normalisasi : ");
    // log(imageMatrix.toString());

    num inputMean = 127.5;
    num inputStd = 127.5;

    // Convert imageMatrix to Float32List
    final floatImageMatrix = imageMatrix
        .map((plane) => plane
            .map((row) =>
                Float32List.fromList(row.map((e) => e.toDouble()).toList()))
            .toList())
        .toList();

    // Normalize the input data
    final normalizedImageMatrix = floatImageMatrix
        .map((plane) => plane
            .map((row) =>
                row.map((pixel) => (pixel - inputMean) / inputStd).toList())
            .toList())
        .toList();

    final input = [normalizedImageMatrix];

    final output = {
      0: [List<num>.filled(10, 0)],
      1: [List<List<num>>.filled(10, List<num>.filled(4, 0))],
      2: [0.0],
      3: [List<num>.filled(10, 0)],
    };

    _interpreter!.runForMultipleInputs([input], output); //proses prediksi
    return output.values.toList();
  }

  List<Map<String, dynamic>> nonMaximumSuppression(
    //fungsi agar tidak menumpuk
    List<Map<String, dynamic>> detections, {
    required double threshold,
  }) {
    detections.sort(
        (a, b) => b['score'].compareTo(a['score'])); // sort by confidence score

    final List<Map<String, dynamic>> finalDetections = [];

    while (detections.isNotEmpty) {
      final detection = detections.removeAt(0);
      finalDetections.add(detection);

      for (int i = detections.length - 1; i >= 0; i--) {
        final otherDetection = detections[i];
        if (overlap(detection, otherDetection) > threshold) {
          detections.removeAt(i);
        }
      }
    }

    return finalDetections;
  }

// fungsi overlap
  double overlap(Map<String, dynamic> a, Map<String, dynamic> b) {
    final x1 =
        math.max(num.parse(a['x1'].toString()), num.parse(b['x1'].toString()));
    final y1 =
        math.max(num.parse(a['y1'].toString()), num.parse(b['y1'].toString()));
    final x2 =
        math.min(num.parse(a['x2'].toString()), num.parse(b['x2'].toString()));
    final y2 =
        math.min(num.parse(a['y2'].toString()), num.parse(b['y2'].toString()));

    final intersectionArea = math.max(0, x2 - x1) * math.max(0, y2 - y1);

    final boxAArea = (a['x2'] - a['x1']) * (a['y2'] - a['y1']);
    final boxBArea = (b['x2'] - b['x1']) * (b['y2'] - b['y1']);

    return intersectionArea / (boxAArea + boxBArea - intersectionArea);
  }

  ImageAnalysisResult analyseImage(String imagePath) {
    log('Analysing image...');
    //mengambil byte gambar
    final imageData = File(imagePath).readAsBytesSync();

    // ubah gambar menjadi angka
    final image = img.decodeImage(imageData);

    // Resizing image for model, [320, 320]
    final imageInput = img.copyResize(
      image!,
      width: 320,
      height: 320,
    );

    // membuat matrix gambar
    final imageMatrix = List.generate(
      imageInput.height,
      (y) => List.generate(
        imageInput.width,
        (x) {
          final pixel = imageInput.getPixel(x, y);
          return [pixel.r, pixel.g, pixel.b];
        },
      ),
    );

    final output = _runInference(imageMatrix);

    // Process Tensors from the output
    final scoresTensor = output[0].first as List<double>;
    final boxesTensor = output[1].first as List<List<double>>;
    final numberOfDetections = output[2].first as double;
    final classesTensor = output[3].first as List<double>;

    log('score: $scoresTensor');
    log('box: $boxesTensor');
    log('class: $classesTensor');

    log('Processing outputs...');

    // Process bounding boxes
    final List<List<int>> locations = boxesTensor
        .map((box) => box.map((value) => ((value * 320).toInt())).toList())
        .toList();

    final classes = classesTensor.map((value) => value.toInt()).toList();

    // Get classifcation with label
    final List<String> classification = [];
    for (int i = 0; i < numberOfDetections; i++) {
      classification.add(_labels![classes[i]]); //label
    }
    log(_labels.toString());
    log('Outlining objects...');
    final iW = image.width;
    final iH = image.height;

    final fractionWidth = iW / 320;
    final fractionHeight = iH / 320;

    final List<Map<String, dynamic>> classifiedLocations = []; //lokasi label
    List<String> sortedLabel = [];
    List<String> newLabel = [];

    for (var i = 0; i < numberOfDetections; i++) {
      if (scoresTensor[i] > 0.5) {
        //skor lebihdari 0.5 atau 50%
        // bounding box
        img.drawRect(
          image,
          x1: (locations[i][1] * fractionWidth).toInt(),
          y1: (locations[i][0] * fractionHeight).toInt(),
          x2: (locations[i][3] * fractionWidth).toInt(),
          y2: (locations[i][2] * fractionHeight).toInt(),
          color: img.ColorRgb8(0, 255, 0),
          thickness: 3,
        );

        // gambar label
        img.drawString(
          image,
          '${classification[i]} ${(scoresTensor[i] * 100).toStringAsFixed(0)}%',
          font: img.arial14,
          x: (locations[i][1] * fractionWidth).toInt() + 7,
          y: (locations[i][0] * fractionHeight).toInt() - 20,
          color: img.ColorRgb8(0, 255, 0),
        );
        // membuat array baru
        classifiedLocations.add({
          'label': _labels![classes[i]],
          'x1': (locations[i][1] * fractionWidth).toInt(),
          'y1': (locations[i][0] * fractionHeight).toInt(),
          'x2': (locations[i][3] * fractionWidth).toInt(),
          'y2': (locations[i][2] * fractionHeight).toInt(),
          'score': scoresTensor[i],
        });
      }
    }
    // Urutkan list berdasarkan dari kiri ke kanan (ketumpuk)
    classifiedLocations.sort((a, b) {
      final aX1 = a['x1']!;
      final aY1 = a['y1']!;
      final bX1 = b['x1']!;
      final bY1 = b['y1']!;

      return aX1.compareTo(bX1) == 0 ? aY1.compareTo(bY1) : aX1.compareTo(bX1);
    });

    log('sorted detection : $classifiedLocations');

    final finalDetections = nonMaximumSuppression(classifiedLocations,
        threshold: 0.5); //mwnghindari deteksi obek saling bertumpuk

    // (ga ketumpuk)
    finalDetections.sort((a, b) {
      // Urutkan list berdasarkan kordinat
      final aX1 = a['x1']!;
      final aY1 = a['y1']!;
      final bX1 = b['x1']!;
      final bY1 = b['y1']!;

      return aX1.compareTo(bX1) == 0 ? aY1.compareTo(bY1) : aX1.compareTo(bX1);
    });

    log('final detection :');
    log(finalDetections.toString());

    for (var classifiedLocation in finalDetections) {
      // log('added');
      sortedLabel.add(classifiedLocation['label']);
    }
    log('sorted class : $sortedLabel');

    if (sortedLabel.isEmpty) {
      //jika tidak ada nominal yang tedetksi
      newLabel = [''];
    } else {
      if (sortedLabel[0] == '0') {
        // jika index pertama 0
        if (sortedLabel.last == '0') {
          // jika index terakhir nol
          newLabel = [''];
        } else {
          // jika index terakhir bukan nol maka akan direverse
          sortedLabel = sortedLabel.reversed.toList();

          // jika ada 2 nominal, ambil 1 nominal pertama
          for (int i = 0; i < sortedLabel.length; i++) {
            if (i == 0) {
              newLabel.add(sortedLabel[i]);
            } else if (i < sortedLabel.length - 1 &&
                sortedLabel[i + 1] != '0') {
              newLabel.add(sortedLabel[i]);
              break;
            } else {
              newLabel.add(sortedLabel[i]);
            }
          }
        }
      } else {
        // jika index pertama bukan 0 tanpa reverse
        for (int i = 0; i < sortedLabel.length; i++) {
          if (i == 0) {
            newLabel.add(sortedLabel[i]);
          } else if (i < sortedLabel.length - 1 && sortedLabel[i + 1] != '0') {
            newLabel.add(sortedLabel[i]);
            break;
          } else {
            newLabel.add(sortedLabel[i]);
          }
        }
      }
    }

    final List<String> listUang = [
      '1000',
      '2000',
      '5000',
      '10000',
      '20000',
      '50000',
      '75000',
      '100000'
    ];

    String labelString = newLabel.join('');

    if (labelString == '75') {
      labelString = '75000';
    }

    if (!listUang.contains(labelString)) {
      labelString = '';
    }

    log('new label class : $newLabel');
    log('final class : $labelString');
    log('Done.');

    final Uint8List imageResult = img.encodeJpg(image);
    return ImageAnalysisResult(
        image: imageResult, labelString: labelString, label: sortedLabel);
  }
}
