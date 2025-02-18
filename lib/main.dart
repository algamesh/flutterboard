import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // For web injection.
import 'dart:math' show Point;
import 'dart:math' as math; // For math calculations.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:turf/turf.dart' as turf;
import 'package:r_tree/r_tree.dart';

/// Helper: Generate a GeoJSON polygon approximating a circle.
Map<String, dynamic> createCirclePolygon(turf.Point center, double radius,
    {int steps = 64}) {
  final List<List<double>> coordinates = [];
  // Earth's radius in kilometers.
  const double earthRadius = 6371.0;
  double centerLng = (center.coordinates[0]! as num).toDouble();
  double centerLat = (center.coordinates[1]! as num).toDouble();
  for (int i = 0; i <= steps; i++) {
    double angle = 2 * math.pi * i / steps;
    // Calculate offsets in radians.
    double deltaLat = radius / earthRadius;
    double deltaLng =
        radius / (earthRadius * math.cos(centerLat * math.pi / 180));
    // Convert offsets from radians to degrees.
    double pointLat =
        centerLat + (deltaLat * math.sin(angle)) * (180 / math.pi);
    double pointLng =
        centerLng + (deltaLng * math.cos(angle)) * (180 / math.pi);
    coordinates.add([pointLng, pointLat]);
  }
  return {
    'type': 'Feature',
    'geometry': {
      'type': 'Polygon',
      'coordinates': [coordinates],
    },
    'properties': {},
  };
}

/// Shared function to load GeoJSON data.
Future<Map<String, dynamic>> loadGeoJson(String path) async {
  final str = await rootBundle.loadString(path);
  return jsonDecode(str) as Map<String, dynamic>;
}

/// Helper to standardize property (column) names across different GeoJSON files.
Map<String, dynamic> standardizeGeoJsonProperties(
    Map<String, dynamic> geojson, String featureType) {
  if (geojson['features'] is List) {
    for (var feature in geojson['features']) {
      Map<String, dynamic> props =
          feature['properties'] as Map<String, dynamic>;
      // Convert all keys to lowercase.
      Map<String, dynamic> newProps = {};
      props.forEach((key, value) {
        newProps[key.toLowerCase()] = value;
      });

      // Apply type-specific renaming.
      if (featureType == 'new_taz') {
        if (newProps.containsKey('taz_new1')) {
          newProps['taz_id'] = newProps['taz_new1'];
          newProps.remove('taz_new1');
        }
      } else if (featureType == 'blocks') {
        if (newProps.containsKey('blockce20')) {
          newProps['block_id'] = newProps['blockce20'];
          newProps.remove('blockce20');
        }
        if (newProps.containsKey('taz_id0')) {
          newProps['taz_id'] = newProps['taz_id0'];
          newProps.remove('taz_id0');
        } else if (newProps.containsKey('taz_new1')) {
          newProps['taz_id'] = newProps['taz_new1'];
          newProps.remove('taz_new1');
        }
      } else if (featureType == 'old_taz') {
        if (newProps.containsKey('objectid')) {
          newProps['object_id'] = newProps['objectid'];
          newProps.remove('objectid');
        }
      }
      feature['properties'] = newProps;
    }
  }
  return geojson;
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

  // Keep track of selected new TAZ IDs for highlighting.
  final Set<int> _selectedNewTazIds = {};

  @override
  void initState() {
    super.initState();
    _loadCachedData();
  }

  Future<void> _loadCachedData() async {
    _cachedOldTaz = await loadGeoJson('assets/geojsons/old_taz.geojson');
    _cachedNewTaz = await loadGeoJson('assets/geojsons/new_taz.geojson');
    _cachedBlocks = await loadGeoJson('assets/geojsons/blocks.geojson');

    // Standardize property names.
    if (_cachedOldTaz != null) {
      _cachedOldTaz = standardizeGeoJsonProperties(_cachedOldTaz!, "old_taz");
    }
    if (_cachedNewTaz != null) {
      _cachedNewTaz = standardizeGeoJsonProperties(_cachedNewTaz!, "new_taz");
    }
    if (_cachedBlocks != null) {
      _cachedBlocks = standardizeGeoJsonProperties(_cachedBlocks!, "blocks");
    }

    // Build spatial index for blocks.
    if (_cachedBlocks != null && _cachedBlocks!['features'] != null) {
      List<RTreeDatum<dynamic>> items = [];
      for (var feature in _cachedBlocks!['features']) {
        math.Rectangle<double> bbox = _boundingBoxFromFeature(feature);
        items.add(RTreeDatum(bbox, feature));
      }
      _blocksIndex = RTree(16);
      _blocksIndex!.add(items);
    }
    setState(() {});
  }

  // Compute bounding box for a GeoJSON feature.
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
      // Optionally clear table data on new search:
      _newTazTableData = [];
      _blocksTableData = [];
      _selectedNewTazIds.clear();
    });
  }

  /// Toggles a new row for the New TAZ table.
  /// If the tapped TAZ is already in the table, remove it and remove the highlight;
  /// otherwise, add it.
  void _toggleNewTazRow(int tappedId) {
    bool exists = _newTazTableData.any((row) => row['id'] == tappedId);
    if (exists) {
      setState(() {
        _newTazTableData.removeWhere((row) => row['id'] == tappedId);
        _selectedNewTazIds.remove(tappedId);
      });
    } else {
      Map<String, dynamic> newRow = {
        'id': tappedId,
        'hh19': 0,
        'persns19': 0,
        'workrs19': 0,
        'emp19': 0,
        'hh49': 0,
        'persns49': 0,
        'workrs49': 0,
        'emp49': 0,
      };

      // If the new TAZ data is available, try to find the matching feature.
      if (_cachedNewTaz != null && _cachedNewTaz!['features'] != null) {
        List<dynamic> features = _cachedNewTaz!['features'];
        var matchingFeature = features.firstWhere(
          (f) => f['properties']?['taz_id'].toString() == tappedId.toString(),
          orElse: () => null,
        );
        if (matchingFeature != null) {
          final props = matchingFeature['properties'] as Map<String, dynamic>;
          newRow = {
            'id': tappedId,
            'hh19': props['hh19'] ?? 0,
            'persns19': props['persns19'] ?? 0,
            'workrs19': props['workrs19'] ?? 0,
            'emp19': props['emp19'] ?? 0,
            'hh49': props['hh49'] ?? 0,
            'persns49': props['persns49'] ?? 0,
            'workrs49': props['workrs49'] ?? 0,
            'emp49': props['emp49'] ?? 0,
          };
        }
      }

      setState(() {
        _newTazTableData.add(newRow);
        _selectedNewTazIds.add(tappedId);
      });
    }
  }

  /// Adds a new row for the Blocks table when a block is tapped.
  void _addBlockRow(int tappedId) {
    if (!_blocksTableData.any((row) => row['id'] == tappedId)) {
      Map<String, dynamic> newRow = {
        'id': tappedId,
        'hh19': 0,
        'persns19': 0,
        'workrs19': 0,
        'emp19': 0,
        'hh49': 0,
        'persns49': 0,
        'workrs49': 0,
        'emp49': 0,
      };

      if (_cachedBlocks != null && _cachedBlocks!['features'] != null) {
        List<dynamic> features = _cachedBlocks!['features'];
        var matchingFeature = features.firstWhere(
          (f) => f['properties']?['block_id'].toString() == tappedId.toString(),
          orElse: () => null,
        );
        if (matchingFeature != null) {
          final props = matchingFeature['properties'] as Map<String, dynamic>;
          newRow = {
            'id': tappedId,
            'hh19': props['hh19'] ?? 0,
            'persns19': props['persns19'] ?? 0,
            'workrs19': props['workrs19'] ?? 0,
            'emp19': props['emp19'] ?? 0,
            'hh49': props['hh49'] ?? 0,
            'persns49': props['persns49'] ?? 0,
            'workrs49': props['workrs49'] ?? 0,
            'emp49': props['emp49'] ?? 0,
          };
        }
      }
      setState(() {
        _blocksTableData.add(newRow);
      });
    }
  }

  /// An editable slider + number field widget for radius.
  Widget _buildRadiusControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          const Text("Radius (m):"),
          const SizedBox(width: 8),
          Expanded(
            child: Slider(
              min: 500,
              max: 5000,
              divisions: 45,
              label: "${_radius.round()}",
              value: _radius,
              onChanged: (value) {
                setState(() {
                  _radius = value;
                  _radiusController.text = value.round().toString();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _radiusController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              onEditingComplete: () {
                double? newVal = double.tryParse(_radiusController.text);
                if (newVal == null) {
                  newVal = 500;
                }
                if (newVal < 500) {
                  newVal = 500;
                } else if (newVal > 5000) {
                  newVal = 5000;
                }
                setState(() {
                  _radius = newVal!;
                  _radiusController.text = newVal.round().toString();
                });
              },
            ),
          ),
          const SizedBox(width: 4),
          const Text("m"),
        ],
      ),
    );
  }

  Future<void> _matchZoom() async {
    // Optional: implement zoom matching.
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
          // Editable radius slider.
          _buildRadiusControl(),
          // Main content.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: Grid of maps.
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      // Top row: Old TAZ and New TAZ maps.
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: MapView(
                                key: ValueKey(
                                    "old_${_selectedTazId ?? 'none'}_${_radius.round()}"),
                                title:
                                    "Old TAZ (Blue target, Purple others)\n(Tap to select)",
                                mode: MapViewMode.oldTaz,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                                radius: _radius,
                                cachedOldTaz: _cachedOldTaz,
                                onTazSelected: (int tappedId) {
                                  setState(() {
                                    _selectedTazId = tappedId;
                                    _searchController.text =
                                        tappedId.toString();
                                    _searchLabel =
                                        "Currently Searching TAZ: $tappedId";
                                  });
                                },
                              ),
                            ),
                            Expanded(
                              child: MapView(
                                key: ValueKey(
                                    "new_${_selectedTazId ?? 'none'}_${_radius.round()}"),
                                title:
                                    "New TAZ (Red Outline)\n(Tap to toggle selection)",
                                mode: MapViewMode.newTaz,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                                radius: _radius,
                                cachedOldTaz: _cachedOldTaz,
                                cachedNewTaz: _cachedNewTaz,
                                // Pass the selected new TAZ IDs for highlighting.
                                selectedIds: _selectedNewTazIds,
                                onTazSelected: (int tappedId) {
                                  _toggleNewTazRow(tappedId);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bottom row: Blocks and Combined maps.
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: MapView(
                                key: ValueKey(
                                    "blocks_${_selectedTazId ?? 'none'}_${_radius.round()}"),
                                title: "Blocks\n(Tap to select)",
                                mode: MapViewMode.blocks,
                                drawShapes: _hasSearched,
                                selectedTazId: _selectedTazId,
                                radius: _radius,
                                cachedOldTaz: _cachedOldTaz,
                                cachedNewTaz: _cachedNewTaz,
                                cachedBlocks: _cachedBlocks,
                                blocksIndex: _blocksIndex,
                                onTazSelected: (int tappedId) {
                                  _addBlockRow(tappedId);
                                },
                              ),
                            ),
                            Expanded(
                              child: MapView(
                                key: ValueKey(
                                    "combined_${_selectedTazId ?? 'none'}_${_radius.round()}"),
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
                                        DataCell(Text("${row['hh19']}")),
                                        DataCell(Text("${row['persns19']}")),
                                        DataCell(Text("${row['workrs19']}")),
                                        DataCell(Text("${row['emp19']}")),
                                        DataCell(Text("${row['hh49']}")),
                                        DataCell(Text("${row['persns49']}")),
                                        DataCell(Text("${row['workrs49']}")),
                                        DataCell(Text("${row['emp49']}")),
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
                                        DataCell(Text("${row['hh19']}")),
                                        DataCell(Text("${row['persns19']}")),
                                        DataCell(Text("${row['workrs19']}")),
                                        DataCell(Text("${row['emp19']}")),
                                        DataCell(Text("${row['hh49']}")),
                                        DataCell(Text("${row['persns49']}")),
                                        DataCell(Text("${row['workrs49']}")),
                                        DataCell(Text("${row['emp49']}")),
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

enum MapViewMode { oldTaz, newTaz, blocks, combined }

class MapView extends StatefulWidget {
  final String title;
  final MapViewMode mode;
  final bool drawShapes;
  final int? selectedTazId;
  final double? radius; // in meters

  // Cached GeoJSON data.
  final Map<String, dynamic>? cachedOldTaz;
  final Map<String, dynamic>? cachedNewTaz;
  final Map<String, dynamic>? cachedBlocks;

  /// Pass the spatial index for blocks if available.
  final RTree<dynamic>? blocksIndex;

  /// Callback for when a geometry is tapped.
  final ValueChanged<int>? onTazSelected;

  /// New optional parameter for selected IDs (for new TAZ mode)
  final Set<int>? selectedIds;

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
    this.onTazSelected,
    this.selectedIds,
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
    // If the selection has changed in new TAZ mode, update the filter.
    if (widget.mode == MapViewMode.newTaz && controller != null) {
      final newFilter =
          (widget.selectedIds != null && widget.selectedIds!.isNotEmpty)
              ? ["in", "taz_id", ...widget.selectedIds!.toList()]
              : ["==", "taz_id", ""];
      controller!.setFilter("selected_new_taz_fill", newFilter);
    }
    if (oldWidget.selectedTazId != widget.selectedTazId ||
        oldWidget.drawShapes != widget.drawShapes ||
        oldWidget.radius != widget.radius) {
      _hasLoadedLayers = false;
      _loadLayers();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wrap the map in a GestureDetector to capture tap events.
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (TapDownDetails details) async {
            debugPrint("GestureDetector onTapDown: ${details.globalPosition}");
            // Convert the tap position to a Point<double>.
            final tapPoint = Point<double>(
                details.localPosition.dx, details.localPosition.dy);
            _handleMapClick(tapPoint);
          },
          child: MaplibreMap(
            styleString: 'https://demotiles.maplibre.org/style.json',
            onMapCreated: _onMapCreated,
            initialCameraPosition: const CameraPosition(
              target: LatLng(39.0, -75.0),
              zoom: 7,
            ),
            onStyleLoadedCallback: _onStyleLoaded,
          ),
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
        await _loadOldTazLayers();
        await _loadRadiusCircle();
      } else if (widget.mode == MapViewMode.newTaz) {
        await _loadNewTazLayers();
        // Add an overlay layer for highlighting selected new TAZ features.
        await controller!.addFillLayer(
          "new_taz_source",
          "selected_new_taz_fill",
          FillLayerProperties(
            fillColor: "#FFFF00", // Yellow highlight.
            fillOpacity: 0.5,
          ),
          filter: (widget.selectedIds != null && widget.selectedIds!.isNotEmpty)
              ? ["in", "taz_id", ...widget.selectedIds!.toList()]
              : ["==", "taz_id", ""],
        );
      } else if (widget.mode == MapViewMode.blocks) {
        await _loadBlocksFill();
      } else if (widget.mode == MapViewMode.combined) {
        final blocksData = await _loadBlocksFill(zoom: false);
        final oldData = await _loadOldTazLayers(zoom: false);
        final newData = await _loadNewTazLayers(zoom: false);
        await _loadRadiusCircle();
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

  /// Loads old TAZ features, splits them into target (blue) and others (purple).
  Future<Map<String, dynamic>?> _loadOldTazLayers({bool zoom = true}) async {
    if (controller == null ||
        widget.selectedTazId == null ||
        widget.radius == null) return null;
    final oldTazData = widget.cachedOldTaz ??
        await loadGeoJson('assets/geojsons/old_taz.geojson');
    final List<dynamic> allFeatures = oldTazData['features'] as List<dynamic>;

    // Identify the target feature.
    final targetFeature = allFeatures.firstWhere(
      (f) =>
          (f['properties'] as Map<String, dynamic>)['taz_id']?.toString() ==
          widget.selectedTazId.toString(),
      orElse: () => null,
    );
    if (targetFeature == null) {
      debugPrint("No old TAZ found for ID ${widget.selectedTazId}");
      return null;
    }
    final turf.Feature targetTazFeature = turf.Feature.fromJson(targetFeature);
    final targetCentroidFeature = turf.centroid(targetTazFeature);
    final turf.Point targetCentroid =
        targetCentroidFeature.geometry as turf.Point;
    double radiusKm = widget.radius! / 1000;

    // Filter features by distance from the target centroid.
    List<dynamic> withinFeatures = [];
    for (var feature in allFeatures) {
      final turf.Feature f = turf.Feature.fromJson(feature);
      final centroidFeature = turf.centroid(f);
      final turf.Point centroid = centroidFeature.geometry as turf.Point;
      double distance =
          (turf.distance(targetCentroid, centroid, turf.Unit.kilometers) as num)
              .toDouble();
      if (distance <= radiusKm) {
        withinFeatures.add(feature);
      }
    }

    // Split into target and other features.
    List<dynamic> targetFeatures = withinFeatures.where((f) {
      final props = f['properties'] as Map<String, dynamic>;
      return props['taz_id']?.toString() == widget.selectedTazId.toString();
    }).toList();
    List<dynamic> otherFeatures = withinFeatures.where((f) {
      final props = f['properties'] as Map<String, dynamic>;
      return props['taz_id']?.toString() != widget.selectedTazId.toString();
    }).toList();

    final combinedData = {
      'type': 'FeatureCollection',
      'features': withinFeatures,
    };

    // Add blue target layers.
    await _addGeoJsonSourceAndLineLayer(
      sourceId: "old_taz_target_source",
      layerId: "old_taz_target_line",
      geojsonData: {'type': 'FeatureCollection', 'features': targetFeatures},
      lineColor: "#0000FF",
      lineWidth: 2.0,
    );
    await _addGeoJsonSourceAndFillLayer(
      sourceId: "old_taz_target_fill_source",
      layerId: "old_taz_target_fill",
      geojsonData: {'type': 'FeatureCollection', 'features': targetFeatures},
      fillColor: "#0000FF",
      fillOpacity: 0.18,
    );
    // Add purple layers for other features.
    await _addGeoJsonSourceAndLineLayer(
      sourceId: "old_taz_others_source",
      layerId: "old_taz_others_line",
      geojsonData: {'type': 'FeatureCollection', 'features': otherFeatures},
      lineColor: "#800080",
      lineWidth: 2.0,
    );
    await _addGeoJsonSourceAndFillLayer(
      sourceId: "old_taz_others_fill_source",
      layerId: "old_taz_others_fill",
      geojsonData: {'type': 'FeatureCollection', 'features': otherFeatures},
      fillColor: "#800080",
      fillOpacity: 0.18,
    );

    if (zoom) await _zoomToFeatureBounds(combinedData);
    return combinedData;
  }

  /// Loads new TAZ features and applies a red outline and fill.
  Future<Map<String, dynamic>?> _loadNewTazLayers({bool zoom = true}) async {
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
      debugPrint("No old TAZ found for ID ${widget.selectedTazId}");
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
    if (filteredNewFeatures.isEmpty) {
      debugPrint("No new TAZ features within the radius.");
      return null;
    }
    final filteredNewData = {
      'type': 'FeatureCollection',
      'features': filteredNewFeatures
    };
    await _addGeoJsonSourceAndLineLayer(
      sourceId: "new_taz_source",
      layerId: "new_taz_line",
      geojsonData: filteredNewData,
      lineColor: "#FF0000",
      lineWidth: 2.0,
    );
    await _addGeoJsonSourceAndFillLayer(
      sourceId: "new_taz_fill_source",
      layerId: "new_taz_fill",
      geojsonData: filteredNewData,
      fillColor: "#FF0000",
      fillOpacity: 0.18,
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
      debugPrint("No old TAZ found for ID ${widget.selectedTazId}");
      return null;
    }
    final turf.Feature oldTazFeature = turf.Feature.fromJson(oldFeature);
    final oldCentroidFeature = turf.centroid(oldTazFeature);
    final turf.Point oldCentroid = oldCentroidFeature.geometry as turf.Point;
    double radiusKm = widget.radius! / 1000;

    final double centerLat = (oldCentroid.coordinates[1]!).toDouble();
    final double centerLng = (oldCentroid.coordinates[0]!).toDouble();
    final double deltaLat = radiusKm / 110.574;
    final double deltaLng =
        radiusKm / (111.320 * math.cos(centerLat * math.pi / 180));
    final math.Rectangle<double> circleBBox = math.Rectangle(
        centerLng - deltaLng, centerLat - deltaLat, 2 * deltaLng, 2 * deltaLat);

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

    if (filteredBlocks.isEmpty) {
      debugPrint("No blocks within the radius.");
      return null;
    }
    final filteredBlocksData = {
      'type': 'FeatureCollection',
      'features': filteredBlocks
    };
    await controller!.addSource(
        "blocks_source", GeojsonSourceProperties(data: filteredBlocksData));
    await controller!.addFillLayer("blocks_source", "blocks_fill",
        FillLayerProperties(fillColor: "#FFFF00", fillOpacity: 0.4));
    if (zoom) await _zoomToFeatureBounds(filteredBlocksData);
    return filteredBlocksData;
  }

  /// Draws a circle representing the search radius.
  Future<void> _loadRadiusCircle() async {
    if (controller == null ||
        widget.selectedTazId == null ||
        widget.radius == null ||
        widget.cachedOldTaz == null) return;
    final List<dynamic> oldFeatures =
        widget.cachedOldTaz!['features'] as List<dynamic>;
    final targetFeature = oldFeatures.firstWhere(
      (f) =>
          (f['properties'] as Map<String, dynamic>)['taz_id']?.toString() ==
          widget.selectedTazId.toString(),
      orElse: () => null,
    );
    if (targetFeature == null) return;
    final turf.Feature targetTazFeature = turf.Feature.fromJson(targetFeature);
    final targetCentroidFeature = turf.centroid(targetTazFeature);
    final turf.Point targetCentroid =
        targetCentroidFeature.geometry as turf.Point;
    double radiusKm = widget.radius! / 1000;
    final circleFeature =
        createCirclePolygon(targetCentroid, radiusKm, steps: 64);
    await controller!.addSource(
        "radius_circle_source", GeojsonSourceProperties(data: circleFeature));
    await controller!.addFillLayer("radius_circle_source", "radius_circle_fill",
        FillLayerProperties(fillColor: "#0000FF", fillOpacity: 0.1));
    await controller!.addLineLayer("radius_circle_source", "radius_circle_line",
        LineLayerProperties(lineColor: "#0000FF", lineWidth: 2.0));
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
    await controller!.addLineLayer(sourceId, layerId,
        LineLayerProperties(lineColor: lineColor, lineWidth: lineWidth));
  }

  Future<void> _addGeoJsonSourceAndFillLayer({
    required String sourceId,
    required String layerId,
    required Map<String, dynamic> geojsonData,
    required String fillColor,
    double fillOpacity = 0.18,
  }) async {
    await controller!
        .addSource(sourceId, GeojsonSourceProperties(data: geojsonData));
    await controller!.addFillLayer(sourceId, layerId,
        FillLayerProperties(fillColor: fillColor, fillOpacity: fillOpacity));
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
      controller!.moveCamera(CameraUpdate.newLatLngBounds(bounds,
          left: 50, right: 50, top: 50, bottom: 50));
    }
  }

  /// Handles a tap on the map.
  Future<void> _handleMapClick(Point<double> tapPoint) async {
    if (controller == null) return;
    // Determine which layers to query based on mode.
    List<String> layersToQuery = [];
    if (widget.mode == MapViewMode.oldTaz) {
      layersToQuery = ["old_taz_target_fill", "old_taz_others_fill"];
    } else if (widget.mode == MapViewMode.newTaz) {
      layersToQuery = ["new_taz_fill"];
    } else if (widget.mode == MapViewMode.blocks) {
      layersToQuery = ["blocks_fill"];
    } else {
      return;
    }

    final features = await controller!.queryRenderedFeatures(
      tapPoint,
      layersToQuery,
      [],
    );

    if (features != null && features.isNotEmpty) {
      final feature = features.first;
      if (widget.mode == MapViewMode.blocks) {
        final dynamic blockId = feature["properties"]?["block_id"];
        if (blockId != null) {
          final int parsedId = int.tryParse(blockId.toString()) ?? 0;
          debugPrint("Tapped Block id: $parsedId");
          if (widget.onTazSelected != null) {
            widget.onTazSelected!(parsedId);
          }
        }
      } else {
        final dynamic tazId = feature["properties"]?["taz_id"];
        if (tazId != null) {
          final int parsedId = int.tryParse(tazId.toString()) ?? 0;
          debugPrint("Tapped TAZ id: $parsedId");
          if (widget.onTazSelected != null) {
            widget.onTazSelected!(parsedId);
          }
        }
      }
    }
  }
}
