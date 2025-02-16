import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // For web injection
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';
// Make sure to add turf_dart to your pubspec.yaml.
import 'package:turf/turf.dart' as turf;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // If running on the web, inject MapLibre JS/CSS dynamically.
  if (kIsWeb) {
    await injectMapLibreScripts();
  }

  runApp(const MyApp());
}

/// Injects MapLibre CSS & JS.
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

/// The Dashboard Page – multi‐panel layout.
class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Controllers for user input.
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _radiusController =
      TextEditingController(text: "1000");
  String _searchLabel = "Currently Searching TAZ: (none)";

  // Dummy table data.
  List<Map<String, dynamic>> _newTazTableData = [];
  List<Map<String, dynamic>> _blocksTableData = [];

  // Indicates whether a valid search has been conducted.
  bool _hasSearched = false;

  // The TAZ ID selected (for the old TAZ).
  int? _selectedTazId;

  // Called when the user presses "Search TAZ".
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

      // Dummy table updates.
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

  Future<void> _matchZoom() async {
    // Optional: implement syncing zoom.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("VizTAZ Dashboard"),
      ),
      body: Column(
        children: [
          // Top Control Bar.
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
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
          // Main Content.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: 2×2 grid of maps.
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      // Top row.
                      Expanded(
                        child: Row(
                          children: [
                            // OLD TAZ (Blue Outline) – top left.
                            // A unique key forces a rebuild when _selectedTazId changes.
                            Expanded(
                              child: MapView(
                                key: ValueKey<int?>(_selectedTazId),
                                title: "Old TAZ (Blue Outline)",
                                mode: MapViewMode.oldTaz,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                              ),
                            ),
                            // NEW TAZ (Red Outline) – top right.
                            // Also receives the selectedTazId so it can filter by intersection.
                            Expanded(
                              child: MapView(
                                key:
                                    ValueKey("new_${_selectedTazId ?? 'none'}"),
                                title: "New TAZ (Red Outline)",
                                mode: MapViewMode.newTaz,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bottom row.
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
                // Right side: Data Tables.
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

/// Enum to define which dataset(s) each MapView should display.
enum MapViewMode {
  oldTaz,
  newTaz,
  blocks,
  combined,
}

/// Minimal MapView widget with MapLibre GL.
/// The [drawShapes] flag controls whether the map should load its GeoJSON layers.
/// [selectedTazId] is used by both oldTaz and newTaz modes.
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
  bool _hasLoadedLayers = false; // Prevent re‐adding layers unnecessarily.

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When drawShapes becomes true and layers haven't been loaded, load them.
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
            target: LatLng(39.0, -75.0),
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

  Future<void> _onStyleLoaded() async {
    if (widget.drawShapes && !_hasLoadedLayers) {
      await _loadLayers();
    }
  }

  Future<void> _loadLayers() async {
    if (controller == null) return;

    try {
      if (widget.mode == MapViewMode.oldTaz) {
        // For oldTaz mode, load only the selected old TAZ.
        await _loadOldTazLine();
      } else if (widget.mode == MapViewMode.newTaz) {
        // For newTaz mode, load new TAZ features that intersect the selected old TAZ.
        await _loadNewTazLine();
      }
      _hasLoadedLayers = true;
    } catch (e) {
      debugPrint("Error loading layers for ${widget.mode}: $e");
    }
  }

  /// Loads a line layer for the selected Old TAZ.
  Future<void> _loadOldTazLine() async {
    if (controller == null) return;
    final oldTazData = await _loadGeoJson('assets/geojsons/old_taz.geojson');
    if (widget.selectedTazId != null) {
      final List<dynamic> allFeatures = oldTazData['features'] as List<dynamic>;
      final filteredFeatures = allFeatures.where((feature) {
        final props = feature['properties'] as Map<String, dynamic>;
        final propValue = props['taz_id']?.toString() ?? '';
        return propValue == widget.selectedTazId.toString();
      }).toList();
      debugPrint(
          "Old TAZ: All features: ${allFeatures.length}, Filtered: ${filteredFeatures.length}");
      if (filteredFeatures.isEmpty) {
        debugPrint("No old TAZ found matching ID ${widget.selectedTazId}.");
        return;
      }
      final filteredData = {
        'type': 'FeatureCollection',
        'features': filteredFeatures,
      };
      await _addGeoJsonSourceAndLineLayer(
        sourceId: "old_taz_source",
        layerId: "old_taz_line",
        geojsonData: filteredData,
        lineColor: "#0000FF",
        lineWidth: 2.0,
      );
      await _zoomToFeatureBounds(filteredData);
    }
  }

  /// Loads a line layer for new TAZ features that intersect the selected old TAZ.
  Future<void> _loadNewTazLine() async {
    if (controller == null || widget.selectedTazId == null) return;

    // 1. Load the old TAZ GeoJSON and filter for the selected TAZ.
    final oldTazData = await _loadGeoJson('assets/geojsons/old_taz.geojson');
    final List<dynamic> oldFeatures = oldTazData['features'] as List<dynamic>;
    final oldFeature = oldFeatures.firstWhere(
      (f) =>
          (f['properties'] as Map<String, dynamic>)['taz_id']?.toString() ==
          widget.selectedTazId.toString(),
      orElse: () => null,
    );
    if (oldFeature == null) {
      debugPrint("No old TAZ found for selected ID ${widget.selectedTazId}");
      return;
    }
    // Convert the old feature to a Turf feature (without generic type).
    final turf.Feature turfOld = turf.Feature.fromJson(oldFeature);

    // 2. Load the new TAZ GeoJSON.
    final newTazData = await _loadGeoJson('assets/geojsons/new_taz.geojson');
    final List<dynamic> newFeatures = newTazData['features'] as List<dynamic>;

    // 3. Filter new TAZ features by intersection.
    final filteredNewFeatures = newFeatures.where((feature) {
      final turf.Feature turfNew = turf.Feature.fromJson(feature);
      // Use Turf's booleanIntersects function.
      return turf.booleanIntersects(turfOld, turfNew);
    }).toList();

    debugPrint(
        "New TAZ: All features: ${newFeatures.length}, Filtered: ${filteredNewFeatures.length}");

    if (filteredNewFeatures.isEmpty) {
      debugPrint("No new TAZ features intersect the selected old TAZ.");
      return;
    }

    final filteredNewData = {
      'type': 'FeatureCollection',
      'features': filteredNewFeatures,
    };

    await _addGeoJsonSourceAndLineLayer(
      sourceId: "new_taz_source",
      layerId: "new_taz_line",
      geojsonData: filteredNewData,
      lineColor: "#FF0000",
      lineWidth: 2.0,
    );
    await _zoomToFeatureBounds(filteredNewData);
  }

  /// Reads GeoJSON from assets.
  Future<Map<String, dynamic>> _loadGeoJson(String path) async {
    final str = await rootBundle.loadString(path);
    return jsonDecode(str) as Map<String, dynamic>;
  }

  /// Utility to add a line layer.
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

  /// Zooms to the bounds of the provided feature collection.
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
