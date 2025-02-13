import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    await injectMapLibreScripts(); // Ensure scripts are fully loaded before running app
  }

  runApp(const MyApp());
}

/// Injects MapLibre JS & CSS and ensures it is fully loaded before Flutter tries to use it
Future<void> injectMapLibreScripts() async {
  // Inject CSS
  final html.LinkElement link = html.LinkElement()
    ..href = "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl.css"
    ..rel = "stylesheet"
    ..crossOrigin = "anonymous";
  html.document.head!.append(link);

  // Inject JS and wait for it to load before proceeding
  final completer = Completer<void>();
  final html.ScriptElement script = html.ScriptElement()
    ..src = "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl.js"
    ..defer = true
    ..crossOrigin = "anonymous"
    ..onLoad.listen((_) {
      print("✅ MapLibre GL JS loaded successfully.");
      completer.complete();
    })
    ..onError.listen((_) {
      print("❌ Failed to load MapLibre GL JS.");
      completer.completeError("Failed to load MapLibre GL JS.");
    });

  html.document.head!.append(script);

  return completer.future; // Wait for the script to load
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Four Panel Map Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const FourPanelMapPage(),
    );
  }
}

/// A page with a 2×2 grid of MapLibre maps
class FourPanelMapPage extends StatelessWidget {
  const FourPanelMapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Four Panel Map'),
      ),
      body: kIsWeb
          ? FutureBuilder(
              future: Future.delayed(const Duration(
                  milliseconds: 500)), // Delay map rendering slightly
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildMapGrid();
              },
            )
          : _buildMapGrid(),
    );
  }

  /// 2x2 Map Grid
  Widget _buildMapGrid() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildMap()),
              Expanded(child: _buildMap()),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildMap()),
              Expanded(child: _buildMap()),
            ],
          ),
        ),
      ],
    );
  }

  /// Single Map Component
  Widget _buildMap() {
    return MaplibreMap(
      styleString: 'https://demotiles.maplibre.org/style.json',
      initialCameraPosition: const CameraPosition(
        target: LatLng(39.0, -95.0), // center on the US
        zoom: 4,
      ),
    );
  }
}
