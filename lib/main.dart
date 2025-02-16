import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // For web injection.
import 'dart:math' as math; // For cosine calculations & math.Rectangle.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:turf/turf.dart' as turf;
import 'package:r_tree/r_tree.dart';

/// Shared function to load GeoJSON data.
Future<Map<String, dynamic>> loadGeoJson(String path) async {
  final str = await rootBundle.loadString(path);
  return jsonDecode(str) as Map<String, dynamic>;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    await injectMapLibreScripts();
  }
  runApp(const MyApp());
}

Future<void> injectMapLibreScripts() async {
  final html.LinkElement link = html.LinkElement()
    ..href = "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl.css"
    ..rel = "stylesheet"
    ..crossOrigin = "anonymous";
  html.document.head!.append(link);

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
  List<Map<String, dynamic>> _newTazTableData = [];
  List<Map<String, dynamic>> _blocksTableData = [];
  bool _hasSearched = false;
  int? _selectedTazId;
  double _radius = 1000; // in meters

  // Cached GeoJSON data.
  Map<String, dynamic>? _cachedOldTaz;
  Map<String, dynamic>? _cachedNewTaz;
  Map<String, dynamic>? _cachedBlocks;

  // Spatial index for blocks.
  RTree<dynamic>? _blocksIndex;

  @override
  void initState() {
    super.initState();
    // Load and cache data at startup, then build spatial index.
    _loadCachedData();
  }

  Future<void> _loadCachedData() async {
    _cachedOldTaz = await loadGeoJson('assets/geojsons/old_taz.geojson');
    _cachedNewTaz = await loadGeoJson('assets/geojsons/new_taz.geojson');
    _cachedBlocks = await loadGeoJson('assets/geojsons/blocks.geojson');

    // Build spatial index for blocks.
    if (_cachedBlocks != null && _cachedBlocks!['features'] != null) {
      List<RTreeDatum<dynamic>> items = [];
      for (var feature in _cachedBlocks!['features']) {
        // Compute bounding box.
        math.Rectangle<double> bbox = _boundingBoxFromFeature(feature);
        // Create a datum from the bbox and feature.
        items.add(RTreeDatum(bbox, feature));
      }
      // Create an RTree instance with a branch factor of 16 (default).
      _blocksIndex = RTree(16);
      // Bulk add all items.
      _blocksIndex!.add(items);
    }
    setState(() {
      // Data and spatial index are now cached.
    });
  }

  // Compute bounding box for a GeoJSON feature (assumes Polygon or MultiPolygon).
  math.Rectangle<double> _boundingBoxFromFeature(dynamic feature) {
    double? minLng, minLat, maxLng, maxLat;
    final geometry = feature['geometry'];
    final type = geometry['type'];
    final coords = geometry['coordinates'];
    if (type == 'Polygon') {
      for (var ring in coords) {
        for (var point in ring) {
          double lng = (point[0] as num).toDouble();
          double lat = (point[1] as num).toDouble();
          if (minLng == null || lng < minLng) minLng = lng;
          if (maxLng == null || lng > maxLng) maxLng = lng;
          if (minLat == null || lat < minLat) minLat = lat;
          if (maxLat == null || lat > maxLat) maxLat = lat;
        }
      }
    } else if (type == 'MultiPolygon') {
      for (var polygon in coords) {
        for (var ring in polygon) {
          for (var point in ring) {
            double lng = (point[0] as num).toDouble();
            double lat = (point[1] as num).toDouble();
            if (minLng == null || lng < minLng) minLng = lng;
            if (maxLng == null || lng > maxLng) maxLng = lng;
            if (minLat == null || lat < minLat) minLat = lat;
            if (maxLat == null || lat > maxLat) maxLat = lat;
          }
        }
      }
    }
    // Provide defaults if needed.
    minLng ??= 0;
    minLat ??= 0;
    maxLng ??= 0;
    maxLat ??= 0;
    return math.Rectangle<double>(
        minLng, minLat, maxLng - minLng, maxLat - minLat);
  }

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
    final radiusInput = double.tryParse(_radiusController.text.trim());
    _radius = radiusInput ?? 1000;

    setState(() {
      _searchLabel = "Currently Searching TAZ: $tazId";
      _hasSearched = true;
      _selectedTazId = tazId;
      // Dummy table updates...
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
                      // Top row: Old TAZ and New TAZ.
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: MapView(
                                key: ValueKey<int?>(_selectedTazId),
                                title: "Old TAZ (Blue Outline)",
                                mode: MapViewMode.oldTaz,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                                radius: _radius,
                                cachedOldTaz: _cachedOldTaz,
                              ),
                            ),
                            Expanded(
                              child: MapView(
                                key:
                                    ValueKey("new_${_selectedTazId ?? 'none'}"),
                                title: "New TAZ (Red Outline)",
                                mode: MapViewMode.newTaz,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                                radius: _radius,
                                cachedOldTaz: _cachedOldTaz,
                                cachedNewTaz: _cachedNewTaz,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bottom row: Blocks and Combined.
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: MapView(
                                key: ValueKey(
                                    "blocks_${_selectedTazId ?? 'none'}"),
                                title: "Blocks",
                                mode: MapViewMode.blocks,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                                radius: _radius,
                                cachedOldTaz: _cachedOldTaz,
                                cachedNewTaz: _cachedNewTaz,
                                cachedBlocks: _cachedBlocks,
                                blocksIndex:
                                    _blocksIndex, // Pass the spatial index.
                              ),
                            ),
                            // Notice the added ValueKey for the combined view.
                            Expanded(
                              child: MapView(
                                key: ValueKey(
                                    "combined_${_selectedTazId ?? 'none'}"),
                                title: "Combined",
                                mode: MapViewMode.combined,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                                radius: _radius,
                                cachedOldTaz: _cachedOldTaz,
                                cachedNewTaz: _cachedNewTaz,
                                cachedBlocks: _cachedBlocks,
                                blocksIndex: _blocksIndex,
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
                            fontSize: 16, fontWeight: FontWeight.bold),
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
                            fontSize: 16, fontWeight: FontWeight.bold),
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

enum MapViewMode {
  oldTaz,
  newTaz,
  blocks,
  combined,
}

class MapView extends StatefulWidget {
  final String title;
  final MapViewMode mode;
  final bool drawShapes;
  final int? selectedTazId;
  final double? radius; // in meters

  // Cached GeoJSON data. If provided, these are used instead of loading from disk.
  final Map<String, dynamic>? cachedOldTaz;
  final Map<String, dynamic>? cachedNewTaz;
  final Map<String, dynamic>? cachedBlocks;

  /// Pass the spatial index for blocks if available.
  final RTree<dynamic>? blocksIndex;

  const MapView({
    Key? key,
    required this.title,
    required this.mode,
    required this.drawShapes,
    this.selectedTazId,
    this.radius,
    this.cachedOldTaz,
    this.cachedNewTaz,
    this.cachedBlocks,
    this.blocksIndex,
  }) : super(key: key);

  @override
  MapViewState createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  MaplibreMapController? controller;
  bool _hasLoadedLayers = false;

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the selected TAZ or the draw flag changes, reset the layers.
    if (oldWidget.selectedTazId != widget.selectedTazId ||
        oldWidget.drawShapes != widget.drawShapes) {
      _hasLoadedLayers = false;
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
        await _loadOldTazLine();
      } else if (widget.mode == MapViewMode.newTaz) {
        await _loadNewTazLine();
      } else if (widget.mode == MapViewMode.blocks) {
        await _loadBlocksFill();
      } else if (widget.mode == MapViewMode.combined) {
        // In combined view, add all layers: blocks (bottom), old TAZ (middle), then new TAZ (top).
        final blocksData = await _loadBlocksFill(zoom: false);
        final oldData = await _loadOldTazLine(zoom: false);
        final newData = await _loadNewTazLine(zoom: false);
        // Combine features from all layers for a unified zoom.
        List<dynamic> allFeatures = [];
        if (blocksData != null && blocksData['features'] != null) {
          allFeatures.addAll(blocksData['features']);
        }
        if (oldData != null && oldData['features'] != null) {
          allFeatures.addAll(oldData['features']);
        }
        if (newData != null && newData['features'] != null) {
          allFeatures.addAll(newData['features']);
        }
        if (allFeatures.isNotEmpty) {
          final unionData = {
            'type': 'FeatureCollection',
            'features': allFeatures
          };
          await _zoomToFeatureBounds(unionData);
        }
      }
      _hasLoadedLayers = true;
    } catch (e) {
      debugPrint("Error loading layers for ${widget.mode}: $e");
    }
  }

  Future<Map<String, dynamic>?> _loadOldTazLine({bool zoom = true}) async {
    if (controller == null) return null;
    final oldTazData = widget.cachedOldTaz ??
        await loadGeoJson('assets/geojsons/old_taz.geojson');
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
        return null;
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
      if (zoom) await _zoomToFeatureBounds(filteredData);
      return filteredData;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadNewTazLine({bool zoom = true}) async {
    if (controller == null ||
        widget.selectedTazId == null ||
        widget.radius == null) return null;
    final oldTazData = widget.cachedOldTaz ??
        await loadGeoJson('assets/geojsons/old_taz.geojson');
    final List<dynamic> oldFeatures = oldTazData['features'] as List<dynamic>;
    final oldFeature = oldFeatures.firstWhere(
      (f) =>
          (f['properties'] as Map<String, dynamic>)['taz_id']?.toString() ==
          widget.selectedTazId.toString(),
      orElse: () => null,
    );
    if (oldFeature == null) {
      debugPrint("No old TAZ found for selected ID ${widget.selectedTazId}");
      return null;
    }
    final turf.Feature oldTazFeature = turf.Feature.fromJson(oldFeature);
    final oldCentroidFeature = turf.centroid(oldTazFeature);
    final turf.Point oldCentroid = oldCentroidFeature.geometry as turf.Point;
    double radiusKm = widget.radius! / 1000;
    final newTazData = widget.cachedNewTaz ??
        await loadGeoJson('assets/geojsons/new_taz.geojson');
    final List<dynamic> newFeatures = newTazData['features'] as List<dynamic>;
    final filteredNewFeatures = newFeatures.where((feature) {
      final turf.Feature newTazFeature = turf.Feature.fromJson(feature);
      final newCentroidFeature = turf.centroid(newTazFeature);
      final turf.Point newCentroid = newCentroidFeature.geometry as turf.Point;
      double distance =
          (turf.distance(oldCentroid, newCentroid, turf.Unit.kilometers) as num)
              .toDouble();
      return distance <= radiusKm;
    }).toList();
    debugPrint(
        "New TAZ: All features: ${newFeatures.length}, Filtered: ${filteredNewFeatures.length}");
    if (filteredNewFeatures.isEmpty) {
      debugPrint("No new TAZ features within the radius.");
      return null;
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
    if (zoom) await _zoomToFeatureBounds(filteredNewData);
    return filteredNewData;
  }

  Future<Map<String, dynamic>?> _loadBlocksFill({bool zoom = true}) async {
    if (controller == null ||
        widget.selectedTazId == null ||
        widget.radius == null) return null;
    final oldTazData = widget.cachedOldTaz ??
        await loadGeoJson('assets/geojsons/old_taz.geojson');
    final List<dynamic> oldFeatures = oldTazData['features'] as List<dynamic>;
    final oldFeature = oldFeatures.firstWhere(
      (f) =>
          (f['properties'] as Map<String, dynamic>)['taz_id']?.toString() ==
          widget.selectedTazId.toString(),
      orElse: () => null,
    );
    if (oldFeature == null) {
      debugPrint("No old TAZ found for selected ID ${widget.selectedTazId}");
      return null;
    }
    final turf.Feature oldTazFeature = turf.Feature.fromJson(oldFeature);
    final oldCentroidFeature = turf.centroid(oldTazFeature);
    final turf.Point oldCentroid = oldCentroidFeature.geometry as turf.Point;
    double radiusKm = widget.radius! / 1000;

    // Compute bounding box for the search circle.
    final double centerLat = (oldCentroid.coordinates[1]!).toDouble();
    final double centerLng = (oldCentroid.coordinates[0]!).toDouble();
    final double deltaLat = radiusKm / 110.574; // degrees per km latitude.
    final double deltaLng =
        radiusKm / (111.320 * math.cos(centerLat * math.pi / 180));
    final math.Rectangle<double> circleBBox = math.Rectangle(
        centerLng - deltaLng, centerLat - deltaLat, 2 * deltaLng, 2 * deltaLat);

    // Use the spatial index to quickly retrieve candidate blocks.
    List<dynamic> candidateBlocks = [];
    if (widget.blocksIndex != null) {
      math.Rectangle<num> searchRect = math.Rectangle<num>(
          circleBBox.left, circleBBox.top, circleBBox.width, circleBBox.height);
      candidateBlocks = widget.blocksIndex!
          .search(searchRect)
          .map((datum) => datum.value)
          .toList();
    } else {
      candidateBlocks =
          (widget.cachedBlocks?['features'] as List<dynamic>) ?? [];
    }

    final filteredBlocks = candidateBlocks.where((block) {
      final turf.Feature blockFeature = turf.Feature.fromJson(block);
      final blockCentroidFeature = turf.centroid(blockFeature);
      final turf.Point blockCentroid =
          blockCentroidFeature.geometry as turf.Point;
      final double blockLng = (blockCentroid.coordinates[0]!).toDouble();
      final double blockLat = (blockCentroid.coordinates[1]!).toDouble();
      if (blockLng < circleBBox.left ||
          blockLng > circleBBox.left + circleBBox.width ||
          blockLat < circleBBox.top ||
          blockLat > circleBBox.top + circleBBox.height) {
        return false;
      }
      double distance = (turf.distance(
              oldCentroid, blockCentroid, turf.Unit.kilometers) as num)
          .toDouble();
      return distance <= radiusKm;
    }).toList();

    debugPrint(
        "Blocks: Candidate features: ${candidateBlocks.length}, Filtered: ${filteredBlocks.length}");
    if (filteredBlocks.isEmpty) {
      debugPrint("No blocks within the radius.");
      return null;
    }
    final filteredBlocksData = {
      'type': 'FeatureCollection',
      'features': filteredBlocks,
    };
    await controller!.addSource(
      "blocks_source",
      GeojsonSourceProperties(data: filteredBlocksData),
    );
    await controller!.addFillLayer(
      "blocks_source",
      "blocks_fill",
      FillLayerProperties(
        fillColor: "#FFFF00", // Yellow fill.
        fillOpacity: 0.4,
      ),
    );
    if (zoom) await _zoomToFeatureBounds(filteredBlocksData);
    return filteredBlocksData;
  }

  Future<void> _addGeoJsonSourceAndLineLayer({
    required String sourceId,
    required String layerId,
    required Map<String, dynamic> geojsonData,
    required String lineColor,
    double lineWidth = 2.0,
  }) async {
    await controller!
        .addSource(sourceId, GeojsonSourceProperties(data: geojsonData));
    await controller!.addLineLayer(
      sourceId,
      layerId,
      LineLayerProperties(lineColor: lineColor, lineWidth: lineWidth),
    );
  }

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
            final double lng = (point[0] as num).toDouble();
            final double lat = (point[1] as num).toDouble();
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
              final double lng = (point[0] as num).toDouble();
              final double lat = (point[1] as num).toDouble();
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
      // Instead of animating, move the camera immediately.
      controller!.moveCamera(
        CameraUpdate.newLatLngBounds(bounds,
            left: 50, right: 50, top: 50, bottom: 50),
      );
    }
  }
}
