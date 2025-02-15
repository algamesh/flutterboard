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

  // Called when the user presses "Search TAZ"
  void _runSearch() {
    final tazIdStr = _searchController.text.trim();
    if (tazIdStr.isEmpty) {
      setState(() {
        _searchLabel = "Currently Searching TAZ: (none)";
      });
      return;
    }

    final tazId = int.tryParse(tazIdStr);
    if (tazId == null) {
      setState(() {
        _searchLabel = "Currently Searching TAZ: (invalid ID)";
      });
      return;
    }

    final radius = double.tryParse(_radiusController.text.trim()) ?? 1000;

    setState(() {
      _searchLabel = "Currently Searching TAZ: $tazId";

      // TODO: Real logic to buffer & filter polygons
      // For now, just updating dummy table data.
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
                            // OLD TAZ (blue line)
                            Expanded(
                              child: MapView(
                                title: "Old TAZ (Blue Outline)",
                                mode: MapViewMode.oldTaz,
                              ),
                            ),
                            // NEW TAZ (red line)
                            Expanded(
                              child: MapView(
                                title: "New TAZ (Red Outline)",
                                mode: MapViewMode.newTaz,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bottom row
                      Expanded(
                        child: Row(
                          children: [
                            // BLOCKS
                            Expanded(
                              child: MapView(
                                title: "Blocks",
                                mode: MapViewMode.blocks,
                              ),
                            ),
                            // COMBINED
                            Expanded(
                              child: MapView(
                                title: "Combined",
                                mode: MapViewMode.combined,
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

/// Minimal MapView widget with MapLibre GL
class MapView extends StatefulWidget {
  final String title;
  final MapViewMode mode;
  const MapView({Key? key, required this.title, required this.mode})
      : super(key: key);

  @override
  MapViewState createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  MaplibreMapController? controller;
  bool _hasLoadedLayers = false; // So we don't re‐add on style changes

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

  /// Once the style is loaded, add the relevant layers for this MapView's mode.
  Future<void> _onStyleLoaded() async {
    if (controller == null || _hasLoadedLayers) return;
    _hasLoadedLayers = true;

    try {
      // Always load the Delaware blocks (for test reference).
      // We'll put it first so everything else draws on top of it.
      await _loadDelaware();

      // Then load the layers for each MapView mode.
      switch (widget.mode) {
        case MapViewMode.oldTaz:
          await _loadOldTazLine();
          break;

        case MapViewMode.newTaz:
          await _loadNewTazLine();
          break;

        case MapViewMode.blocks:
          // You can choose any fill color you like for blocks alone
          await _loadBlocksFill(fillColor: "#00FF00", fillOpacity: 0.4);
          break;

        case MapViewMode.combined:
          // Overlapping: Old TAZ (blue line), New TAZ (red line), Blocks (yellow fill)
          await _loadBlocksFill(fillColor: "#FFFF00", fillOpacity: 0.23);
          await _loadOldTazLine();
          await _loadNewTazLine();
          break;
      }
    } catch (e) {
      debugPrint("Error adding layers in ${widget.mode}: $e");
    }
  }

  /// Always load Delaware blocks as a reference (fill).
  /// If you prefer an outline only, you could use a line layer instead.
  Future<void> _loadDelaware() async {
    if (controller == null) return;
    final data = await _loadGeoJson('assets/geojsons/delaware_blocks.geojson');
    const sourceId = "delaware_blocks_src";
    const layerId = "delaware_blocks_fill";
    await controller!.addSource(
      sourceId,
      GeojsonSourceProperties(data: data),
    );
    await controller!.addFillLayer(
      sourceId,
      layerId,
      const FillLayerProperties(
        fillColor: "#888888",
        fillOpacity: 0.2,
      ),
    );
  }

  /// Add a line layer for Old TAZ (blue)
  Future<void> _loadOldTazLine() async {
    if (controller == null) return;
    final oldTazData = await _loadGeoJson('assets/geojsons/old_taz.geojson');
    await _addGeoJsonSourceAndLineLayer(
      sourceId: "old_taz_source",
      layerId: "old_taz_line",
      geojsonData: oldTazData,
      lineColor: "#0000FF", // blue
      lineWidth: 2.0,
    );
  }

  /// Add a line layer for New TAZ (red)
  Future<void> _loadNewTazLine() async {
    if (controller == null) return;
    final newTazData = await _loadGeoJson('assets/geojsons/new_taz.geojson');
    await _addGeoJsonSourceAndLineLayer(
      sourceId: "new_taz_source",
      layerId: "new_taz_line",
      geojsonData: newTazData,
      lineColor: "#FF0000", // red
      lineWidth: 2.0,
    );
  }

  /// Add a fill layer for Blocks
  Future<void> _loadBlocksFill({
    required String fillColor,
    required double fillOpacity,
  }) async {
    if (controller == null) return;
    final blocksData = await _loadGeoJson('assets/geojsons/blocks.geojson');
    await _addGeoJsonSourceAndFillLayer(
      sourceId: "blocks_source",
      layerId: "blocks_fill",
      geojsonData: blocksData,
      fillColor: fillColor,
      fillOpacity: fillOpacity,
    );
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

  /// Utility to add a fill layer
  Future<void> _addGeoJsonSourceAndFillLayer({
    required String sourceId,
    required String layerId,
    required Map<String, dynamic> geojsonData,
    required String fillColor,
    double fillOpacity = 0.5,
  }) async {
    await controller!.addSource(
      sourceId,
      GeojsonSourceProperties(data: geojsonData),
    );
    await controller!.addFillLayer(
      sourceId,
      layerId,
      FillLayerProperties(
        fillColor: fillColor,
        fillOpacity: fillOpacity,
      ),
    );
  }
}
