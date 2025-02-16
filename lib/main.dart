import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // For web injection
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // If running on the web, inject MapLibre JS/CSS dynamically.
  if (kIsWeb) {
    await injectMapLibreScripts();
  }

  runApp(const MyApp());
}

/// Injects MapLibre CSS & JS
Future<void> injectMapLibreScripts() async {
  // CSS
  final html.LinkElement link = html.LinkElement()
    ..href = "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl.css"
    ..rel = "stylesheet"
    ..crossOrigin = "anonymous";
  html.document.head!.append(link);

  // JS
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VizTAZ Dashboard',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DashboardPage(),
    );
  }
}

/// The Dashboard Page – multi‐panel layout
class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Controllers for user input
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _radiusController =
      TextEditingController(text: "1000");
  String _searchLabel = "Currently Searching TAZ: (none)";

  // Example data for the "New TAZ" table
  List<Map<String, dynamic>> _newTazTableData = [];
  // Example data for the "Blocks" table
  List<Map<String, dynamic>> _blocksTableData = [];

  // Flag indicating a valid TAZ search has been conducted.
  bool _hasSearched = false;

  // Store the TAZ ID we want to display
  int? _selectedTazId;

  // Called when the user presses "Search TAZ"
  void _runSearch() {
    final tazIdStr = _searchController.text.trim();
    if (tazIdStr.isEmpty) {
      setState(() {
        _searchLabel = "Currently Searching TAZ: (none)";
        _hasSearched = false;
        _selectedTazId = null;
      });
      return;
    }

    final tazId = int.tryParse(tazIdStr);
    if (tazId == null) {
      setState(() {
        _searchLabel = "Currently Searching TAZ: (invalid ID)";
        _hasSearched = false;
        _selectedTazId = null;
      });
      return;
    }

    setState(() {
      _searchLabel = "Currently Searching TAZ: $tazId";
      _hasSearched = true;
      _selectedTazId = tazId;

      // Dummy data update for tables:
      _newTazTableData = [
        {
          "id": tazId,
          "HH19": 123,
          "PERSNS19": 456,
          "WORKRS19": 78,
          "EMP19": 999,
          "HH49": 140,
          "PERSNS49": 490,
          "WORKRS49": 90,
          "EMP49": 1200
        },
        {
          "id": 999,
          "HH19": 321,
          "PERSNS19": 654,
          "WORKRS19": 87,
          "EMP19": 555,
          "HH49": 130,
          "PERSNS49": 410,
          "WORKRS49": 100,
          "EMP49": 1100
        },
      ];
      _blocksTableData = [
        {
          "id": "BlockA",
          "HH19": 50,
          "PERSNS19": 120,
          "WORKRS19": 30,
          "EMP19": 220,
          "HH49": 80,
          "PERSNS49": 200,
          "WORKRS49": 35,
          "EMP49": 300
        },
        {
          "id": "BlockB",
          "HH19": 70,
          "PERSNS19": 180,
          "WORKRS19": 40,
          "EMP19": 300,
          "HH49": 90,
          "PERSNS49": 240,
          "WORKRS49": 42,
          "EMP49": 360
        },
      ];
    });
  }

  // Example function to sync zoom across maps (optional)
  Future<void> _matchZoom() async {
    // ...
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("VizTAZ Dashboard"),
      ),
      body: Column(
        children: [
          // Top Control Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // TAZ ID input
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: "Old TAZ ID",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                // Radius input
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _radiusController,
                    decoration: const InputDecoration(
                      labelText: "Radius (m)",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _runSearch,
                  child: const Text("Search TAZ"),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _matchZoom,
                  child: const Text("Match Zoom"),
                ),
                const SizedBox(width: 16),
                Text(
                  _searchLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // Main content
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: 2×2 grid of maps
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      // Top row
                      Expanded(
                        child: Row(
                          children: [
                            // OLD TAZ (blue line) – only panel that draws shapes.
                            // A unique key is provided so that when _selectedTazId changes,
                            // this widget is rebuilt and loads new layers.
                            Expanded(
                              child: MapView(
                                key: ValueKey<int?>(_selectedTazId),
                                title: "Old TAZ (Blue Outline)",
                                mode: MapViewMode.oldTaz,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                              ),
                            ),
                            // NEW TAZ (red line) – not drawn.
                            Expanded(
                              child: MapView(
                                title: "New TAZ (Red Outline)",
                                mode: MapViewMode.newTaz,
                                drawShapes: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bottom row
                      Expanded(
                        child: Row(
                          children: [
                            // BLOCKS – not drawn.
                            Expanded(
                              child: MapView(
                                title: "Blocks",
                                mode: MapViewMode.blocks,
                                drawShapes: false,
                              ),
                            ),
                            // COMBINED – not drawn.
                            Expanded(
                              child: MapView(
                                title: "Combined",
                                mode: MapViewMode.combined,
                                drawShapes: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Right side: Data Tables
                Container(
                  width: 400,
                  padding: const EdgeInsets.all(8.0),
                  color: Colors.grey[200],
                  child: Column(
                    children: [
                      const Text(
                        "New TAZ Table",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text("ID")),
                                DataColumn(label: Text("HH19")),
                                DataColumn(label: Text("PERSNS19")),
                                DataColumn(label: Text("WORKRS19")),
                                DataColumn(label: Text("EMP19")),
                                DataColumn(label: Text("HH49")),
                                DataColumn(label: Text("PERSNS49")),
                                DataColumn(label: Text("WORKRS49")),
                                DataColumn(label: Text("EMP49")),
                              ],
                              rows: _newTazTableData.isNotEmpty
                                  ? _newTazTableData.map((row) {
                                      return DataRow(cells: [
                                        DataCell(Text("${row['id']}")),
                                        DataCell(Text("${row['HH19']}")),
                                        DataCell(Text("${row['PERSNS19']}")),
                                        DataCell(Text("${row['WORKRS19']}")),
                                        DataCell(Text("${row['EMP19']}")),
                                        DataCell(Text("${row['HH49']}")),
                                        DataCell(Text("${row['PERSNS49']}")),
                                        DataCell(Text("${row['WORKRS49']}")),
                                        DataCell(Text("${row['EMP49']}")),
                                      ]);
                                    }).toList()
                                  : [
                                      const DataRow(cells: [
                                        DataCell(Text("No data")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                      ])
                                    ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Blocks Table",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text("ID")),
                                DataColumn(label: Text("HH19")),
                                DataColumn(label: Text("PERSNS19")),
                                DataColumn(label: Text("WORKRS19")),
                                DataColumn(label: Text("EMP19")),
                                DataColumn(label: Text("HH49")),
                                DataColumn(label: Text("PERSNS49")),
                                DataColumn(label: Text("WORKRS49")),
                                DataColumn(label: Text("EMP49")),
                              ],
                              rows: _blocksTableData.isNotEmpty
                                  ? _blocksTableData.map((row) {
                                      return DataRow(cells: [
                                        DataCell(Text("${row['id']}")),
                                        DataCell(Text("${row['HH19']}")),
                                        DataCell(Text("${row['PERSNS19']}")),
                                        DataCell(Text("${row['WORKRS19']}")),
                                        DataCell(Text("${row['EMP19']}")),
                                        DataCell(Text("${row['HH49']}")),
                                        DataCell(Text("${row['PERSNS49']}")),
                                        DataCell(Text("${row['WORKRS49']}")),
                                        DataCell(Text("${row['EMP49']}")),
                                      ]);
                                    }).toList()
                                  : [
                                      const DataRow(cells: [
                                        DataCell(Text("No data")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                        DataCell(Text("")),
                                      ])
                                    ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Identifies which dataset(s) each MapView should display.
enum MapViewMode {
  oldTaz,
  newTaz,
  blocks,
  combined,
}

/// Minimal MapView widget with MapLibre GL.
/// The [drawShapes] flag controls whether the map should load its GeoJSON layers,
/// and [selectedTazId] is used to filter the old_taz layer.
class MapView extends StatefulWidget {
  final String title;
  final MapViewMode mode;
  final bool drawShapes;
  final int? selectedTazId;

  const MapView({
    Key? key,
    required this.title,
    required this.mode,
    required this.drawShapes,
    this.selectedTazId,
  }) : super(key: key);

  @override
  MapViewState createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  MaplibreMapController? controller;
  bool _hasLoadedLayers = false; // So we don't re‐add layers unnecessarily

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If drawShapes becomes true and layers haven't been loaded, then load them.
    if (widget.drawShapes && !_hasLoadedLayers && controller != null) {
      _loadLayers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MaplibreMap(
          styleString: 'https://demotiles.maplibre.org/style.json',
          onMapCreated: _onMapCreated,
          initialCameraPosition: const CameraPosition(
            target: LatLng(39.0, -75.0), // near Delaware
            zoom: 7,
          ),
          onStyleLoadedCallback: _onStyleLoaded,
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            color: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  void _onMapCreated(MaplibreMapController ctrl) {
    controller = ctrl;
  }

  /// Called when the style is loaded.
  Future<void> _onStyleLoaded() async {
    if (widget.drawShapes && !_hasLoadedLayers) {
      await _loadLayers();
    }
  }

  Future<void> _loadLayers() async {
    if (controller == null) return;

    // We only load layers for the Old TAZ (top‐left) map.
    if (widget.mode == MapViewMode.oldTaz) {
      try {
        // Load only the TAZ that matches the user's input.
        await _loadOldTazLine();
        _hasLoadedLayers = true;
      } catch (e) {
        debugPrint("Error loading layers for ${widget.mode}: $e");
      }
    }
  }

  /// Add a line layer for the *single* Old TAZ the user searched for
  Future<void> _loadOldTazLine() async {
    if (controller == null) return;

    // 1. Load the entire old_taz.geojson
    final oldTazData = await _loadGeoJson('assets/geojsons/old_taz.geojson');

    // 2. Filter out all but the selected TAZ.
    // Note: Using 'taz_id' (all lowercase) to match the GeoJSON data.
    if (widget.selectedTazId != null) {
      final List<dynamic> allFeatures = oldTazData['features'] as List<dynamic>;

      final filteredFeatures = allFeatures.where((feature) {
        final props = feature['properties'] as Map<String, dynamic>;
        final propValue = props['taz_id']?.toString() ?? '';
        return propValue == widget.selectedTazId.toString();
      }).toList();

      debugPrint("All features: ${allFeatures.length}");
      debugPrint("Filtered features: ${filteredFeatures.length}");

      if (filteredFeatures.isEmpty) {
        debugPrint("No TAZ found matching ID ${widget.selectedTazId}.");
        return;
      }

      final filteredData = <String, dynamic>{
        'type': 'FeatureCollection',
        'features': filteredFeatures,
      };

      await _addGeoJsonSourceAndLineLayer(
        sourceId: "old_taz_source",
        layerId: "old_taz_line",
        geojsonData: filteredData,
        lineColor: "#0000FF", // blue
        lineWidth: 2.0,
      );

      // Optionally, zoom to the feature bounds.
      await _zoomToFeatureBounds(filteredData);
    }
  }

  /// Reads GeoJSON from assets
  Future<Map<String, dynamic>> _loadGeoJson(String path) async {
    final str = await rootBundle.loadString(path);
    return jsonDecode(str) as Map<String, dynamic>;
  }

  /// Utility to add a line layer
  Future<void> _addGeoJsonSourceAndLineLayer({
    required String sourceId,
    required String layerId,
    required Map<String, dynamic> geojsonData,
    required String lineColor,
    double lineWidth = 2.0,
  }) async {
    await controller!.addSource(
      sourceId,
      GeojsonSourceProperties(data: geojsonData),
    );
    await controller!.addLineLayer(
      sourceId,
      layerId,
      LineLayerProperties(
        lineColor: lineColor,
        lineWidth: lineWidth,
      ),
    );
  }

  /// Zoom to the bounds of the provided feature collection.
  Future<void> _zoomToFeatureBounds(
      Map<String, dynamic> featureCollection) async {
    if (controller == null) return;

    double? minLat, maxLat, minLng, maxLng;
    final features = featureCollection['features'] as List<dynamic>;
    for (final f in features) {
      final geometry = f['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'];
      final geomType = geometry['type'];

      if (geomType == 'Polygon') {
        for (final ring in coords) {
          for (final point in ring) {
            final lng = point[0] as double;
            final lat = point[1] as double;
            minLat = (minLat == null) ? lat : (lat < minLat ? lat : minLat);
            maxLat = (maxLat == null) ? lat : (lat > maxLat ? lat : maxLat);
            minLng = (minLng == null) ? lng : (lng < minLng ? lng : minLng);
            maxLng = (maxLng == null) ? lng : (lng > maxLng ? lng : maxLng);
          }
        }
      } else if (geomType == 'MultiPolygon') {
        for (final polygon in coords) {
          for (final ring in polygon) {
            for (final point in ring) {
              final lng = point[0] as double;
              final lat = point[1] as double;
              minLat = (minLat == null) ? lat : (lat < minLat ? lat : minLat);
              maxLat = (maxLat == null) ? lat : (lat > maxLat ? lat : maxLat);
              minLng = (minLng == null) ? lng : (lng < minLng ? lng : minLng);
              maxLng = (maxLng == null) ? lng : (lng > maxLng ? lng : maxLng);
            }
          }
        }
      }
    }

    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      final sw = LatLng(minLat, minLng);
      final ne = LatLng(maxLat, maxLng);
      final bounds = LatLngBounds(southwest: sw, northeast: ne);

      await controller!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds,
            left: 50, right: 50, top: 50, bottom: 50),
      );
    }
  }
}
