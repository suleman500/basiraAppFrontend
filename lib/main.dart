
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:projctlitudei/features/detection/presentation/basira_home_screen.dart';

import 'features/detection/presentation/detection_screen.dart';

late List<CameraDescription>? cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: BasiraHomeScreen(),
      //DetectionScreen(cameras: cameras!),
    );
  }
}
