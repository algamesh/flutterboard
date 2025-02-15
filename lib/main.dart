import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // For web-only script injection
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // If running on the web, inject the MapLibre JS/CSS dynamically.
  if (kIsWeb) {
    await injectMapLibreScripts();
  }

  runApp(const MyApp());
}

/// Injects MapLibre JS & CSS and ensures they are loaded before Flutter tries to use them.
Future<void> injectMapLibreScripts() async {
  // Inject MapLibre CSS
  final html.LinkElement link = html.LinkElement()
    ..href = "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl.css"
    ..rel = "stylesheet"
    ..crossOrigin = "anonymous";
  html.document.head!.append(link);

  // Inject MapLibre JS and wait for it to load.
  final completer = Completer<void>();
  final html.ScriptElement script = html.ScriptElement()
    ..src = "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl.js"
    ..defer = true
    ..crossOrigin = "anonymous"
    ..onLoad.listen((_) {
      debugPrint("✅ MapLibre GL JS loaded successfully.");
      completer.complete();
    })
    ..onError.listen((_) {
      debugPrint("❌ Failed to load MapLibre GL JS.");
      completer.completeError("Failed to load MapLibre GL JS.");
    });
  html.document.head!.append(script);

  return completer.future;
}

/// OSM style URL from MapLibre demo tiles.
const String osmStyle = "https://demotiles.maplibre.org/style.json";

/// Satellite style defined using Esri World Imagery.
const String satelliteStyle = '''{
  "version": 8,
  "sources": {
    "raster-tiles": {
      "type": "raster",
      "tiles": [
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
      ],
      "tileSize": 256,
      "attribution": "Tiles © Esri"
    }
  },
  "layers": [
    {
      "id": "simple-tiles",
      "type": "raster",
      "source": "raster-tiles",
      "minzoom": 0,
      "maxzoom": 22
    }
  ]
}''';

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Delaware Blocks',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MaplibreMapController? _mapController;
  // Start with the OSM style.
  String _currentStyle = osmStyle;
  // Flag to indicate whether the GeoJSON has been added to the style.
  bool _geoJsonAdded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Delaware Blocks"),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: DropdownButton<String>(
              value: _currentStyle == osmStyle ? "Map" : "Satellite",
              items: const [
                DropdownMenuItem(value: "Map", child: Text("Map")),
                DropdownMenuItem(value: "Satellite", child: Text("Satellite")),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    // Change the style and force a rebuild.
                    _currentStyle = value == "Map" ? osmStyle : satelliteStyle;
                    _geoJsonAdded = false; // Reset flag to re-add the GeoJSON.
                  });
                }
              },
            ),
          ),
        ],
      ),
      // Use a ValueKey so that a style change rebuilds the MaplibreMap.
      body: MaplibreMap(
        key: ValueKey<String>(_currentStyle),
        styleString: _currentStyle,
        initialCameraPosition: const CameraPosition(
          // Center over Delaware; adjust as needed.
          target: LatLng(39.0, -75.5),
          zoom: 7,
        ),
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
      ),
    );
  }

  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
  }

  /// When a new style is loaded, add the GeoJSON layer.
  Future<void> _onStyleLoaded() async {
    if (!_geoJsonAdded) {
      try {
        // Load the GeoJSON from assets.
        final String geoJsonStr = await rootBundle
            .loadString('assets/geojsons/delaware_blocks.geojson');
        final Map<String, dynamic> geoJsonData = jsonDecode(geoJsonStr);

        // Add the GeoJSON source.
        await _mapController!.addSource(
          "delaware_source",
          GeojsonSourceProperties(data: geoJsonData),
        );

        // Add a fill layer to render the polygons.
        await _mapController!.addFillLayer(
          "delaware_source",
          "delaware_layer",
          FillLayerProperties(
            fillColor: "#FF0000", // Red fill.
            fillOpacity: 0.5,
          ),
        );
        _geoJsonAdded = true;
      } catch (e) {
        debugPrint("Error adding GeoJSON: $e");
      }
    }
  }
}
