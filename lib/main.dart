import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // For web injection and file upload.
import 'dart:math' show Point;
import 'dart:math' as math; // For math calculations.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:turf/turf.dart' as turf;
import 'package:r_tree/r_tree.dart';
import 'package:alga_configui/src/config_page.dart';

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
    double deltaLat = radius / earthRadius;
    double deltaLng =
        radius / (earthRadius * math.cos(centerLat * math.pi / 180));
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

/// Standardizes property names for each GeoJSON type.
Map<String, dynamic> standardizeGeoJsonProperties(
    Map<String, dynamic> geojson, String featureType) {
  if (geojson['features'] is List) {
    for (var feature in geojson['features']) {
      Map<String, dynamic> props =
          feature['properties'] as Map<String, dynamic>;
      Map<String, dynamic> newProps = {};
      props.forEach((key, value) {
        newProps[key.toLowerCase()] = value;
      });
      if (featureType == 'new_taz') {
        if (newProps.containsKey('taz_new1')) {
          newProps['taz_id'] = newProps['taz_new1'];
          newProps.remove('taz_new1');
        }
      } else if (featureType == 'blocks') {
        if (newProps.containsKey('geoid20')) {
          newProps['geoid20'] = int.tryParse(newProps['geoid20'].toString()) ??
              newProps['geoid20'];
          final String geoidStr = newProps['geoid20'].toString();
          newProps['block_label'] = geoidStr.length > 4
              ? geoidStr.substring(geoidStr.length - 4)
              : geoidStr;
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

/// Injects the MapLibre script/css when running on web.
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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color.fromARGB(255, 249, 253, 255),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 184, 233, 254),
            foregroundColor: Colors.black,
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF4169E1),
          inactiveTrackColor: Colors.blue.shade100,
          thumbColor: const Color(0xFF4169E1),
        ),
      ),
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
  bool _isLoading = true;

  // Input controllers.
  final TextEditingController _searchController = TextEditingController();
  // Updated radius controller starts with "1.0" (representing 1.0 mile or km)
  final TextEditingController _radiusController =
      TextEditingController(text: "1.0");
  String _searchLabel = "Currently Searching TAZ: (none)";
  List<Map<String, dynamic>> _newTazTableData = [];
  List<Map<String, dynamic>> _blocksTableData = [];
  bool _hasSearched = false;
  int? _selectedTazId;
  // Internal radius stored in meters.
  double _radius = 1609.34; // 1 mile in meters
  // The slider’s value (in miles or km as per toggle).
  double _radiusValue = 1.0;
  // Toggle between using kilometers and miles.
  bool _useKilometers = false;
  // New toggle for showing ID labels.
  bool _showIdLabels = false;

  // Cached GeoJSON.
  Map<String, dynamic>? _cachedOldTaz;
  Map<String, dynamic>? _cachedNewTaz;
  Map<String, dynamic>? _cachedBlocks;

  // Spatial index for blocks.
  RTree<dynamic>? _blocksIndex;

  // Sets for selected IDs in new TAZ and blocks.
  final Set<int> _selectedNewTazIds = {};
  Set<int> _selectedBlockIds = {};

  // Background style selection for maps.
  String _selectedMapStyleName = 'Positron';
  // 1) Make them both top-level (or static) so you can safely reference one in the other:
  static const satelliteStyleJson = """
{
  "version": 8,
  "name": "ArcGIS Satellite",
  "sources": {
    "satellite-source": {
      "type": "raster",
      "tiles": [
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
      ],
      "tileSize": 256
    }
  },
  "layers": [
    {
      "id": "satellite-layer",
      "type": "raster",
      "source": "satellite-source"
    }
  ]
}
""";
  final Map<String, String> _mapStyles = {
    'Positron': 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
    'Dark Matter':
        'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
    // You could also embed a Satellite style JSON if preferred.
    'Satellite': 'data:application/json,$satelliteStyleJson',
  };

  // Global shared camera position for synchronization.
  CameraPosition? _syncedCameraPosition;
  // Toggle for enabling/disabling sync.
  bool _isSyncEnabled = false;

  // Global keys to access each MapView's state.
  final GlobalKey<MapViewState> _oldMapKey = GlobalKey<MapViewState>();
  final GlobalKey<MapViewState> _newMapKey = GlobalKey<MapViewState>();
  final GlobalKey<MapViewState> _combinedMapKey = GlobalKey<MapViewState>();
  final GlobalKey<MapViewState> _blocksMapKey = GlobalKey<MapViewState>();

  // Scroll controllers for horizontal scrolling in tables.
  final ScrollController _newTableHorizontalScrollController = ScrollController();
  final ScrollController _blocksTableHorizontalScrollController = ScrollController();

  // New booleans to track whether each file has been uploaded.
  bool _uploadedOldTaz = false;
  bool _uploadedNewTaz = false;
  bool _uploadedBlocks = false;

  // New flags to indicate overall file readiness and if a file is currently processing.
  bool _filesReady = false;
  bool _isProcessingUpload = false;

  @override
  void initState() {
    super.initState();
    // Check if all three files already exist in local storage.
    bool allUploaded = html.window.localStorage.containsKey('old_taz_geojson') &&
        html.window.localStorage.containsKey('new_taz_geojson') &&
        html.window.localStorage.containsKey('blocks_geojson');
    if (allUploaded) {
      _filesReady = true;
      _loadCachedData().then((_) {
        setState(() {
          _isLoading = false;
        });
      });
    } else {
      // Do not load main dashboard until all files are uploaded.
      _isLoading = false;
    }
  }
  
  @override
  void dispose() {
    _newTableHorizontalScrollController.dispose();
    _blocksTableHorizontalScrollController.dispose();
    super.dispose();
  }

  /// Load and preprocess all GeoJSON, plus build spatial index for blocks.
  Future<void> _loadCachedData() async {
    // Load from local storage if available.
    if (html.window.localStorage.containsKey('old_taz_geojson')) {
      _cachedOldTaz = jsonDecode(html.window.localStorage['old_taz_geojson']!);
      _uploadedOldTaz = true;
    } else {
      _cachedOldTaz = await loadGeoJson('assets/geojsons/old_taz.geojson');
    }
    if (html.window.localStorage.containsKey('new_taz_geojson')) {
      _cachedNewTaz = jsonDecode(html.window.localStorage['new_taz_geojson']!);
      _uploadedNewTaz = true;
    } else {
      _cachedNewTaz = await loadGeoJson('assets/geojsons/new_taz.geojson');
    }
    if (html.window.localStorage.containsKey('blocks_geojson')) {
      _cachedBlocks = jsonDecode(html.window.localStorage['blocks_geojson']!);
      _uploadedBlocks = true;
    } else {
      _cachedBlocks = await loadGeoJson('assets/geojsons/blocks.geojson');
    }

    if (_cachedOldTaz != null) {
      _cachedOldTaz = standardizeGeoJsonProperties(_cachedOldTaz!, "old_taz");
    }
    if (_cachedNewTaz != null) {
      _cachedNewTaz = standardizeGeoJsonProperties(_cachedNewTaz!, "new_taz");
    }
    if (_cachedBlocks != null) {
      _cachedBlocks = standardizeGeoJsonProperties(_cachedBlocks!, "blocks");
    }

    // Build an R-Tree index for blocks.
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

  /// Creates a bounding box from a single Polygon/MultiPolygon feature.
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
      minLng,
      minLat,
      maxLng - minLng,
      maxLat - minLat,
    );
  }

  /// Runs a search for the Old TAZ ID typed in, setting up the flags and clearing tables.
  /// Note: Even if the TAZ id is the same, pressing "Search TAZ" will re-run the search.
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
      // Clear the data tables:
      _newTazTableData.clear();
      _blocksTableData.clear();
      // Clear the selected highlights:
      _selectedNewTazIds.clear();
      _selectedBlockIds.clear();
    });
  }

  /// Clears the New TAZ table and its selections.
  void _clearNewTazTable() {
    setState(() {
      _newTazTableData.clear();
      _selectedNewTazIds.clear();
    });
  }

  /// Clears the Blocks table and its selections.
  void _clearBlocksTable() {
    setState(() {
      _blocksTableData.clear();
      _selectedBlockIds.clear();
    });
  }

  /// Toggles a New TAZ row (and highlight on the map) for the data table on the right.
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
        'hh49': 0,
        'emp19': 0,
        'emp49': 0,
        'persns19': 0,
        'persns49': 0,
        'workrs19': 0,
        'workrs49': 0,
      };
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
            'hh49': props['hh49'] ?? 0,
            'emp19': props['emp19'] ?? 0,
            'emp49': props['emp49'] ?? 0,
            'persns19': props['persns19'] ?? 0,
            'persns49': props['persns49'] ?? 0,
            'workrs19': props['workrs19'] ?? 0,
            'workrs49': props['workrs49'] ?? 0,
          };
        }
      }
      setState(() {
        _newTazTableData.add(newRow);
        _selectedNewTazIds.add(tappedId);
      });
    }
  }

  /// Toggles a Block row (and highlight on the map) for the data table on the right.
  void _toggleBlockRow(int tappedId) {
    bool exists = _blocksTableData.any((row) => row['id'] == tappedId);
    setState(() {
      if (exists) {
        _blocksTableData.removeWhere((row) => row['id'] == tappedId);
        _selectedBlockIds = {..._selectedBlockIds}..remove(tappedId);
      } else {
        Map<String, dynamic> newRow = {
          'id': tappedId,
          'hh19': 0,
          'hh49': 0,
          'emp19': 0,
          'emp49': 0,
          'persns19': 0,
          'persns49': 0,
          'workrs19': 0,
          'workrs49': 0,
        };
        if (_cachedBlocks != null && _cachedBlocks!['features'] != null) {
          List<dynamic> features = _cachedBlocks!['features'];
          var matchingFeature = features.firstWhere(
            (f) =>
                f['properties']?['geoid20'].toString() == tappedId.toString(),
            orElse: () => null,
          );
          if (matchingFeature != null) {
            final props = matchingFeature['properties'] as Map<String, dynamic>;
            newRow = {
              'id': tappedId,
              'hh19': props['hh19'] ?? 0,
              'hh49': props['hh49'] ?? 0,
              'emp19': props['emp19'] ?? 0,
              'emp49': props['emp49'] ?? 0,
              'persns19': props['persns19'] ?? 0,
              'persns49': props['persns49'] ?? 0,
              'workrs19': props['workrs19'] ?? 0,
              'workrs49': props['workrs49'] ?? 0,
            };
          }
        }
        _blocksTableData.add(newRow);
        _selectedBlockIds = {..._selectedBlockIds}..add(tappedId);
      }
    });
  }

  /// Builds the slider + text input used to set the search radius.
  Widget _buildRadiusControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          Text("Radius (${_useKilometers ? 'km' : 'miles'}):"),
          const SizedBox(width: 5),
          SizedBox(
            width: 200, // fixed width slider so it isn’t too wide
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF4169E1),
                thumbColor: const Color(0xFF4169E1),
                trackHeight: 4,
              ),
              child: Slider(
                min: 0.5,
                max: 3.0,
                divisions: 5,
                label: _radiusValue.toStringAsFixed(1),
                value: _radiusValue,
                onChanged: (value) {
                  setState(() {
                    _radiusValue = value;
                    _radius = value * (_useKilometers ? 1000 : 1609.34);
                    _radiusController.text = _radiusValue.toStringAsFixed(1);
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _radiusController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
              onEditingComplete: () {
                double? newVal = double.tryParse(_radiusController.text);
                if (newVal == null) newVal = 0.5;
                if (newVal < 0.5) newVal = 0.5;
                if (newVal > 3.0) newVal = 3.0;
                setState(() {
                  _radiusValue = newVal!;
                  _radius = _radiusValue * (_useKilometers ? 1000 : 1609.34);
                  _radiusController.text = _radiusValue.toStringAsFixed(1);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Opens Google Maps centered on the current synced camera target.
  void _openInGoogleMaps() {
    double lat, lng;
    if (_selectedTazId != null && _cachedOldTaz != null) {
      final features = _cachedOldTaz!['features'] as List<dynamic>;
      final targetFeature = features.firstWhere(
        (f) =>
            (f['properties'] as Map<String, dynamic>)['taz_id'].toString() ==
            _selectedTazId.toString(),
        orElse: () => null,
      );
      if (targetFeature != null) {
        final turf.Feature targetTazFeature =
            turf.Feature.fromJson(targetFeature);
        final centroidFeature = turf.centroid(targetTazFeature);
        final turf.Point targetCentroid =
            centroidFeature.geometry as turf.Point;
        lat = (targetCentroid.coordinates[1] as num).toDouble();
        lng = (targetCentroid.coordinates[0] as num).toDouble();
      } else {
        lat = 42.3601;
        lng = -71.0589;
      }
    } else {
      lat = 42.3601;
      lng = -71.0589;
    }
    final url = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    html.window.open(url, '_blank');
  }

  /// Navigates to the configuration page.
  void _goToConfigPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfigPage()),
    );
  }

  /// Opens a file picker for the given shapefile type and processes the file.
  void _uploadShapefile(String type) {
    final input = html.FileUploadInputElement()..accept = '.shp';
    input.click();
    input.onChange.listen((event) async {
      if (input.files!.isNotEmpty) {
        setState(() {
          _isProcessingUpload = true;
        });
        final file = input.files!.first;
        // Process file: convert shp to geojson.
        Map<String, dynamic> geojsonData = await _processShapefile(file, type);
        // Save to local storage and update cached data.
        if (type == "old_taz") {
          html.window.localStorage['old_taz_geojson'] = jsonEncode(geojsonData);
          _uploadedOldTaz = true;
          _cachedOldTaz = geojsonData;
        } else if (type == "new_taz") {
          html.window.localStorage['new_taz_geojson'] = jsonEncode(geojsonData);
          _uploadedNewTaz = true;
          _cachedNewTaz = geojsonData;
        } else if (type == "blocks") {
          html.window.localStorage['blocks_geojson'] = jsonEncode(geojsonData);
          _uploadedBlocks = true;
          _cachedBlocks = geojsonData;
        }
        setState(() {
          _isProcessingUpload = false;
        });
        // If all three files have been uploaded, mark files as ready.
        if (_uploadedOldTaz && _uploadedNewTaz && _uploadedBlocks) {
          setState(() {
            _filesReady = true;
            _isLoading = true;
          });
          await _loadCachedData();
          setState(() {
            _isLoading = false;
          });
        }
      }
    });
  }

  /// Placeholder function to process a shapefile and convert it to GeoJSON.
  /// In a real implementation, this would contain logic (or a web service call)
  /// that processes the .shp file and returns the converted GeoJSON data.
  Future<Map<String, dynamic>> _processShapefile(html.File file, String type) async {
    // Simulate a delay for processing.
    await Future.delayed(const Duration(seconds: 1));
    // For demonstration, we return an empty FeatureCollection.
    // Replace this with your actual conversion logic.
    return {
      "type": "FeatureCollection",
      "features": []
    };
  }

  @override
  Widget build(BuildContext context) {
    // While a file is being processed, show a loading screen.
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("VizTAZ Dashboard"),
          leadingWidth: 150,
          leading: _buildUploadButtons(),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // If files are not yet ready (i.e. not all uploaded), show a waiting screen.
    if (!_filesReady) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Upload Required"),
          leadingWidth: 150,
          leading: _buildUploadButtons(),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Please upload all three shapefiles to continue."),
              if (_isProcessingUpload)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                )
            ],
          ),
        ),
      );
    }

    // Main dashboard once files are ready.
    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF013220), // Very dark green for the AppBar.
        elevation: 2,
        leadingWidth: 150,
        leading: _buildUploadButtons(),
        title: Text(
          _searchLabel,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Conversion toggle with styled container.
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFF3E2723), width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Miles", style: TextStyle(color: const Color(0xFF3E2723))),
                Switch(
                  value: _useKilometers,
                  onChanged: (value) {
                    setState(() {
                      _useKilometers = value;
                      _radius =
                          _radiusValue * (_useKilometers ? 1000 : 1609.34);
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: const Color(0xFF3E2723),
                  inactiveThumbColor: const Color(0xFF3E2723),
                  inactiveTrackColor: const Color(0xFF3E2723).withOpacity(0.3),
                ),
                Text("KM", style: TextStyle(color: const Color(0xFF3E2723))),
              ],
            ),
          ),
          // ID Labels toggle.
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFF3E2723), width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("ID Labels",
                    style: TextStyle(color: const Color(0xFF3E2723))),
                Switch(
                  value: _showIdLabels,
                  onChanged: (value) {
                    setState(() {
                      _showIdLabels = value;
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: const Color(0xFF3E2723),
                  inactiveThumbColor: const Color(0xFF3E2723),
                  inactiveTrackColor: const Color(0xFF3E2723).withOpacity(0.3),
                ),
              ],
            ),
          ),
          // Map style drop-down.
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFF3E2723), width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 80),
              child: DropdownButton<String>(
                isDense: true,
                value: _selectedMapStyleName,
                icon: const Icon(Icons.keyboard_arrow_down,
                    color: Color(0xFF3E2723)),
                dropdownColor: Colors.white,
                style: const TextStyle(
                    color: Color(0xFF3E2723), fontWeight: FontWeight.bold),
                underline: const SizedBox(),
                onChanged: (newValue) {
                  setState(() {
                    _selectedMapStyleName = newValue!;
                  });
                },
                items: _mapStyles.keys.map((styleName) {
                  return DropdownMenuItem<String>(
                    value: styleName,
                    child: Text(styleName),
                  );
                }).toList(),
              ),
            ),
          ),
          // Settings button.
          Container(
            margin: const EdgeInsets.only(right: 16.0),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: IconButton(
              icon: const Icon(Icons.settings, color: Colors.blue),
              onPressed: () => _goToConfigPage(context),
            ),
          ),
        ],
      ),
      // Main layout: Grid with two rows and three equally wide panels.
      body: Column(
        children: [
          // Top control bar.
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Old TAZ ID text field.
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: "Old TAZ ID",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                // Search TAZ button.
                ElevatedButton(
                  onPressed: _runSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[900],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Search TAZ"),
                ),
                const SizedBox(width: 8),
                // Vertical divider.
                Container(
                  height: 40,
                  width: 1,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                // View Sync toggle button.
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isSyncEnabled = !_isSyncEnabled;
                      if (!_isSyncEnabled) {
                        // If turning sync OFF, clear the synced position.
                        _syncedCameraPosition = null;
                      }
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSyncEnabled
                        ? const Color(0xFF8B0000)
                        : const Color(0xFF006400),
                  ),
                  child: Text(
                    _isSyncEnabled ? "View Sync ON" : "View Sync OFF",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                // Open in Google Maps button.
                ElevatedButton(
                  onPressed: _openInGoogleMaps,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Open in Google Maps"),
                ),
                const SizedBox(width: 8),
                // Vertical divider.
                Container(
                  height: 40,
                  width: 1,
                  color: Colors.grey,
                ),
                const SizedBox(width: 12),
                // Radius slider & text input.
                _buildRadiusControl(),
              ],
            ),
          ),
          // Grid: Two rows of three panels each.
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Panel 1: Old TAZ Map.
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.grey.shade400),
                          ),
                          child: MapView(
                            key: ValueKey("old_${_selectedTazId ?? 'none'}_${_radius.round()}_${_selectedMapStyleName}"),
                            title: "Old TAZ (Blue target, Blue others)",
                            mode: MapViewMode.oldTaz,
                            drawShapes: _hasSearched,
                            selectedTazId: _selectedTazId,
                            radius: _radius,
                            cachedOldTaz: _cachedOldTaz,
                            cachedBlocks: _cachedBlocks,
                            blocksIndex: _blocksIndex,
                            showIdLabels: _showIdLabels,
                            // Disable automatic search/reload on tap for Old TAZ.
                            onTazSelected: (int tappedId) {
                              // The following code is commented out to prevent automatic re-search/reload when tapping an Old TAZ.
                              /*
                              setState(() {
                                _selectedTazId = tappedId;
                                _searchController.text = tappedId.toString();
                                _searchLabel = "Currently Searching TAZ: $tappedId";
                              });
                              */
                              debugPrint("Old TAZ tapped: $tappedId (automatic search disabled)");
                            },
                            mapStyle: _mapStyles[_selectedMapStyleName],
                            syncedCameraPosition: _isSyncEnabled
                                ? _syncedCameraPosition
                                : null,
                            onCameraIdleSync: _isSyncEnabled
                                ? (CameraPosition pos) {
                                    setState(() {
                                      _syncedCameraPosition = pos;
                                    });
                                  }
                                : null,
                          ),
                        ),
                      ),
                      // Panel 2: New TAZ Map.
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.grey.shade400),
                          ),
                          child: MapView(
                            key: ValueKey("new_${_selectedTazId ?? 'none'}_${_radius.round()}_${_selectedMapStyleName}"),
                            title: "New TAZ (Red Outline)",
                            mode: MapViewMode.newTaz,
                            drawShapes: _hasSearched,
                            selectedTazId: _selectedTazId,
                            radius: _radius,
                            cachedOldTaz: _cachedOldTaz,
                            cachedNewTaz: _cachedNewTaz,
                            cachedBlocks: _cachedBlocks,
                            blocksIndex: _blocksIndex,
                            selectedIds: _selectedNewTazIds,
                            showIdLabels: _showIdLabels,
                            onTazSelected: (int tappedId) {
                              _toggleNewTazRow(tappedId);
                            },
                            mapStyle: _mapStyles[_selectedMapStyleName],
                            syncedCameraPosition: _isSyncEnabled
                                ? _syncedCameraPosition
                                : null,
                            onCameraIdleSync: _isSyncEnabled
                                ? (CameraPosition pos) {
                                    setState(() {
                                      _syncedCameraPosition = pos;
                                    });
                                  }
                                : null,
                          ),
                        ),
                      ),
                      // Panel 3: New TAZ Table.
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.blueAccent),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            children: [
                              // Table header with clear button.
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "New TAZ Table",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _clearNewTazTable,
                                    child: const Text(
                                      "Clear",
                                      style: TextStyle(
                                          color: Color.fromARGB(
                                              255, 255, 0, 0)),
                                    ),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Colors.blueAccent),
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: Scrollbar(
                                      controller: _newTableHorizontalScrollController,
                                      thumbVisibility: true,
                                      interactive: true,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        controller: _newTableHorizontalScrollController,
                                        child: DataTable(
                                          headingRowColor:
                                              MaterialStateProperty.all(
                                                  Colors.blue[50]),
                                          columns: const [
                                            DataColumn(label: Text("ID")),
                                            DataColumn(label: Text("HH19")),
                                            DataColumn(label: Text("HH49")),
                                            DataColumn(label: Text("EMP19")),
                                            DataColumn(label: Text("EMP49")),
                                            DataColumn(label: Text("PERSNS19")),
                                            DataColumn(label: Text("PERSNS49")),
                                            DataColumn(label: Text("WORKRS19")),
                                            DataColumn(label: Text("WORKRS49")),
                                          ],
                                          rows: () {
                                            List<DataRow> rows = [];
                                            if (_newTazTableData.isNotEmpty) {
                                              rows.addAll(_newTazTableData.map((row) {
                                                return DataRow(cells: [
                                                  DataCell(Text("${row['id']}")),
                                                  DataCell(Text("${row['hh19']}")),
                                                  DataCell(Text("${row['hh49']}")),
                                                  DataCell(Text("${row['emp19']}")),
                                                  DataCell(Text("${row['emp49']}")),
                                                  DataCell(Text("${row['persns19']}")),
                                                  DataCell(Text("${row['persns49']}")),
                                                  DataCell(Text("${row['workrs19']}")),
                                                  DataCell(Text("${row['workrs49']}")),
                                                ]);
                                              }).toList());
                                            } else {
                                              rows.add(const DataRow(cells: [
                                                DataCell(Text("No data")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                              ]));
                                            }
                                            // Compute column totals.
                                            num sumHH19 = _newTazTableData.fold(
                                                0,
                                                (prev, row) =>
                                                    prev + (row['hh19'] as num));
                                            num sumPERSNS19 = _newTazTableData.fold(
                                                0,
                                                (prev, row) =>
                                                    prev + (row['persns19'] as num));
                                            num sumWORKRS19 = _newTazTableData.fold(
                                                0,
                                                (prev, row) =>
                                                    prev + (row['workrs19'] as num));
                                            num sumEMP19 = _newTazTableData.fold(
                                                0,
                                                (prev, row) =>
                                                    prev + (row['emp19'] as num));
                                            num sumHH49 = _newTazTableData.fold(
                                                0,
                                                (prev, row) =>
                                                    prev + (row['hh49'] as num));
                                            num sumPERSNS49 = _newTazTableData.fold(
                                                0,
                                                (prev, row) =>
                                                    prev + (row['persns49'] as num));
                                            num sumWORKRS49 = _newTazTableData.fold(
                                                0,
                                                (prev, row) =>
                                                    prev + (row['workrs49'] as num));
                                            num sumEMP49 = _newTazTableData.fold(
                                                0,
                                                (prev, row) =>
                                                    prev + (row['emp49'] as num));

                                            rows.add(DataRow(
                                              color: MaterialStateProperty.all(
                                                  Colors.grey[300]),
                                              cells: [
                                                const DataCell(Text(
                                                  "Total",
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  "$sumHH19",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  "$sumPERSNS19",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  "$sumWORKRS19",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  "$sumEMP19",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  "$sumHH49",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  "$sumPERSNS49",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  "$sumWORKRS49",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  "$sumEMP49",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                              ],
                                            ));
                                            return rows;
                                          }(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Second row of panels.
                Expanded(
                  child: Row(
                    children: [
                      // Panel 4: Combined Map.
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.grey.shade400),
                          ),
                          child: MapView(
                            key: ValueKey("combined_${_selectedTazId ?? 'none'}_${_radius.round()}_${_selectedMapStyleName}"),
                            title: "Combined View",
                            mode: MapViewMode.combined,
                            drawShapes: _hasSearched,
                            selectedTazId: _selectedTazId,
                            radius: _radius,
                            cachedOldTaz: _cachedOldTaz,
                            cachedNewTaz: _cachedNewTaz,
                            cachedBlocks: _cachedBlocks,
                            blocksIndex: _blocksIndex,
                            mapStyle: _mapStyles[_selectedMapStyleName],
                            syncedCameraPosition: _isSyncEnabled
                                ? _syncedCameraPosition
                                : null,
                            onCameraIdleSync: _isSyncEnabled
                                ? (CameraPosition pos) {
                                    setState(() {
                                      _syncedCameraPosition = pos;
                                    });
                                  }
                                : null,
                          ),
                        ),
                      ),
                      // Panel 5: Blocks Map.
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.grey.shade400),
                          ),
                          child: MapView(
                            key: ValueKey("blocks_${_selectedTazId ?? 'none'}_${_radius.round()}_${_selectedMapStyleName}"),
                            title: "Blocks",
                            mode: MapViewMode.blocks,
                            drawShapes: _hasSearched,
                            selectedTazId: _selectedTazId,
                            radius: _radius,
                            cachedOldTaz: _cachedOldTaz,
                            cachedNewTaz: _cachedNewTaz,
                            cachedBlocks: _cachedBlocks,
                            blocksIndex: _blocksIndex,
                            selectedIds: _selectedBlockIds,
                            onTazSelected: (int tappedId) {
                              _toggleBlockRow(tappedId);
                            },
                            mapStyle: _mapStyles[_selectedMapStyleName],
                            syncedCameraPosition: _isSyncEnabled
                                ? _syncedCameraPosition
                                : null,
                            onCameraIdleSync: _isSyncEnabled
                                ? (CameraPosition pos) {
                                    setState(() {
                                      _syncedCameraPosition = pos;
                                    });
                                  }
                                : null,
                            showIdLabels: _showIdLabels,
                          ),
                        ),
                      ),
                      // Panel 6: Blocks Table.
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.orangeAccent),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            children: [
                              // Table header with clear button.
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Blocks Table",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _clearBlocksTable,
                                    child: const Text(
                                      "Clear",
                                      style: TextStyle(
                                          color: Color.fromARGB(
                                              255, 255, 0, 0)),
                                    ),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Colors.orangeAccent),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: Scrollbar(
                                      controller: _blocksTableHorizontalScrollController,
                                      thumbVisibility: true,
                                      interactive: true,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        controller: _blocksTableHorizontalScrollController,
                                        child: DataTable(
                                          headingRowColor:
                                              MaterialStateProperty.all(
                                                  Colors.orange[50]),
                                          columns: const [
                                            DataColumn(label: Text("ID")),
                                            DataColumn(label: Text("HH19")),
                                            DataColumn(label: Text("HH49")),
                                            DataColumn(label: Text("EMP19")),
                                            DataColumn(label: Text("EMP49")),
                                            DataColumn(label: Text("PERSNS19")),
                                            DataColumn(label: Text("PERSNS49")),
                                            DataColumn(label: Text("WORKRS19")),
                                            DataColumn(label: Text("WORKRS49")),
                                          ],
                                          rows: () {
                                            List<DataRow> rows = [];
                                            if (_blocksTableData.isNotEmpty) {
                                              rows.addAll(_blocksTableData.map((row) {
                                                return DataRow(cells: [
                                                  DataCell(Text("${row['id']}")),
                                                  DataCell(Text("${row['hh19']}")),
                                                  DataCell(Text("${row['hh49']}")),
                                                  DataCell(Text("${row['emp19']}")),
                                                  DataCell(Text("${row['emp49']}")),
                                                  DataCell(Text("${row['persns19']}")),
                                                  DataCell(Text("${row['persns49']}")),
                                                  DataCell(Text("${row['workrs19']}")),
                                                  DataCell(Text("${row['workrs49']}")),
                                                ]);
                                              }).toList());
                                            } else {
                                              rows.add(const DataRow(cells: [
                                                DataCell(Text("No data")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                                DataCell(Text("")),
                                              ]));
                                            }
                                            // Compute totals for each column.
                                            double sumHH19 = _blocksTableData.fold(
                                                0.0,
                                                (prev, row) =>
                                                    prev +
                                                    (row['hh19'] as num).toDouble());
                                            double sumPERSNS19 = _blocksTableData.fold(
                                                0.0,
                                                (prev, row) =>
                                                    prev +
                                                    (row['persns19'] as num).toDouble());
                                            double sumWORKRS19 = _blocksTableData.fold(
                                                0.0,
                                                (prev, row) =>
                                                    prev +
                                                    (row['workrs19'] as num).toDouble());
                                            double sumEMP19 = _blocksTableData.fold(
                                                0.0,
                                                (prev, row) =>
                                                    prev +
                                                    (row['emp19'] as num).toDouble());
                                            double sumHH49 = _blocksTableData.fold(
                                                0.0,
                                                (prev, row) =>
                                                    prev +
                                                    (row['hh49'] as num).toDouble());
                                            double sumPERSNS49 = _blocksTableData.fold(
                                                0.0,
                                                (prev, row) =>
                                                    prev +
                                                    (row['persns49'] as num).toDouble());
                                            double sumWORKRS49 = _blocksTableData.fold(
                                                0.0,
                                                (prev, row) =>
                                                    prev +
                                                    (row['workrs49'] as num).toDouble());
                                            double sumEMP49 = _blocksTableData.fold(
                                                0.0,
                                                (prev, row) =>
                                                    prev +
                                                    (row['emp49'] as num).toDouble());

                                            rows.add(DataRow(
                                              color: MaterialStateProperty.all(
                                                  Colors.grey[300]),
                                              cells: [
                                                const DataCell(Text(
                                                  "Total",
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  sumHH19.toString(),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  sumPERSNS19.toString(),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  sumWORKRS19.toString(),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  sumEMP19.toString(),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  sumHH49.toString(),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  sumPERSNS49.toString(),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  sumWORKRS49.toString(),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                                DataCell(Text(
                                                  sumEMP49.toString(),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                )),
                                              ],
                                            ));
                                            return rows;
                                          }(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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

  /// Builds the three upload buttons as a Row.
  Widget _buildUploadButtons() {
    return Container(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Old TAZ upload button.
          Tooltip(
            message: "Upload Old TAZ shapefile",
            child: IconButton(
              icon: Icon(
                Icons.cloud_upload,
                color: _uploadedOldTaz ? Colors.lightGreen : Colors.red,
              ),
              onPressed: () => _uploadShapefile("old_taz"),
            ),
          ),
          // New TAZ upload button.
          Tooltip(
            message: "Upload New TAZ shapefile",
            child: IconButton(
              icon: Icon(
                Icons.cloud_upload,
                color: _uploadedNewTaz ? Colors.lightGreen : Colors.red,
              ),
              onPressed: () => _uploadShapefile("new_taz"),
            ),
          ),
          // Blocks upload button.
          Tooltip(
            message: "Upload Blocks shapefile",
            child: IconButton(
              icon: Icon(
                Icons.cloud_upload,
                color: _uploadedBlocks ? Colors.lightGreen : Colors.red,
              ),
              onPressed: () => _uploadShapefile("blocks"),
            ),
          ),
        ],
      ),
    );
  }
}

enum MapViewMode { oldTaz, newTaz, blocks, combined }

/// A widget controlling a single MapLibre map instance.
class MapView extends StatefulWidget {
  final String title;
  final MapViewMode mode;
  final bool drawShapes;
  final int? selectedTazId;
  final double? radius;
  final Map<String, dynamic>? cachedOldTaz;
  final Map<String, dynamic>? cachedNewTaz;
  final Map<String, dynamic>? cachedBlocks;
  final RTree<dynamic>? blocksIndex;
  final ValueChanged<int>? onTazSelected;
  final Set<int>? selectedIds;
  final String? mapStyle;
  /// If provided, this map will sync its camera to [syncedCameraPosition].
  final CameraPosition? syncedCameraPosition;
  /// If set, whenever this map finishes moving, it calls [onCameraIdleSync] with its camera position.
  final ValueChanged<CameraPosition>? onCameraIdleSync;
  // New property to toggle TAZ id labels (and now block id labels as well)
  final bool showIdLabels;

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
    this.mapStyle,
    this.syncedCameraPosition,
    this.onCameraIdleSync,
    this.showIdLabels = false, // default value if not provided.
  }) : super(key: key);

  @override
  MapViewState createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  MaplibreMapController? controller;
  bool _hasLoadedLayers = false;
  bool _isProgrammaticallyUpdating = false;

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If selection changes in New TAZ, update the filter.
    if (widget.mode == MapViewMode.newTaz && controller != null) {
      final newFilter =
          (widget.selectedIds != null && widget.selectedIds!.isNotEmpty)
              ? ["in", "taz_id", ...widget.selectedIds!.toList()]
              : ["==", "taz_id", ""];
      controller!.setFilter("selected_new_taz_fill", newFilter);
    }
    // If selection changes in Blocks, update the filter.
    if (widget.mode == MapViewMode.blocks && controller != null) {
      final newFilter =
          (widget.selectedIds != null && widget.selectedIds!.isNotEmpty)
              ? ["in", "geoid20", ...widget.selectedIds!.toList()]
              : ["==", "geoid20", ""];
      controller!.setFilter("selected_blocks_fill", newFilter);
    }

    // Reload layers if TAZ ID, drawing flag, or radius changed.
    if (oldWidget.selectedTazId != widget.selectedTazId ||
        oldWidget.drawShapes != widget.drawShapes ||
        oldWidget.radius != widget.radius) {
      _hasLoadedLayers = false;
      _loadLayers();
    }

    // If camera sync is enabled, move this map to the synced camera position.
    if (widget.syncedCameraPosition != oldWidget.syncedCameraPosition) {
      _maybeMoveToSyncedPosition();
    }

    // Handle changes in the showIdLabels toggle.
    if (widget.showIdLabels != oldWidget.showIdLabels && controller != null) {
      if (widget.mode == MapViewMode.oldTaz) {
        if (widget.showIdLabels) {
          controller!.addSymbolLayer(
            "old_taz_target_source",
            "old_taz_target_labels",
            SymbolLayerProperties(
              textField: "{taz_id}",
              textSize: 12,
              textColor: "#0000FF",
              textHaloColor: "#FFFFFF",
              textHaloWidth: 1,
            ),
          );
          controller!.addSymbolLayer(
            "old_taz_others_source",
            "old_taz_others_labels",
            SymbolLayerProperties(
              textField: "{taz_id}",
              textSize: 12,
              textColor: "#4169E1",
              textHaloColor: "#FFFFFF",
              textHaloWidth: 1,
            ),
          );
        } else {
          controller!.removeLayer("old_taz_target_labels");
          controller!.removeLayer("old_taz_others_labels");
        }
      } else if (widget.mode == MapViewMode.newTaz) {
        if (widget.showIdLabels) {
          controller!.addSymbolLayer(
            "new_taz_source",
            "new_taz_labels",
            SymbolLayerProperties(
              textField: "{taz_id}",
              textSize: 12,
              textColor: "#FF0000",
              textHaloColor: "#FFFFFF",
              textHaloWidth: 1,
            ),
          );
        } else {
          controller!.removeLayer("new_taz_labels");
        }
      } else if (widget.mode == MapViewMode.blocks) {
        if (widget.showIdLabels) {
          controller!.addSymbolLayer(
            "blocks_fill_source",
            "blocks_labels",
            SymbolLayerProperties(
              textField: "{block_label}",
              textSize: 12,
              textColor: "#000000",
              textHaloColor: "#FFFFFF",
              textHaloWidth: 1,
            ),
          );
        } else {
          controller!.removeLayer("blocks_labels");
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The MaplibreMap widget.
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (TapDownDetails details) async {
            // Convert the local tap position to a map coordinate and handle the click.
            final tapPoint = Point<double>(
                details.localPosition.dx, details.localPosition.dy);
            _handleMapClick(tapPoint);
          },
          child: MaplibreMap(
            styleString: widget.mapStyle ??
                'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
            onMapCreated: _onMapCreated,
            initialCameraPosition: const CameraPosition(
              target: LatLng(42.3601, -71.0589), // Default to Boston.
              zoom: 12,
            ),
            onStyleLoadedCallback: _onStyleLoaded,
            onCameraIdle: () async {
              if (controller != null) {
                // Only trigger onCameraIdleSync if the user moved the camera (and not via programmatic update).
                if (!_isProgrammaticallyUpdating &&
                    widget.onCameraIdleSync != null) {
                  CameraPosition? pos = await controller?.cameraPosition;
                  if (pos != null) {
                    widget.onCameraIdleSync!(pos);
                  }
                }
                _isProgrammaticallyUpdating = false;
              }
            },
          ),
        ),
        // Positioned overlay label showing map title and description.
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            color: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              _buildLabelText(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  /// Returns a two-line description:
  /// For old/new TAZ maps: "Title" then "TAZ: ..." (or "None")
  /// For blocks: "Title" then "Selected: ..." (or "None")
  String _buildLabelText() {
    if (widget.mode == MapViewMode.oldTaz ||
        widget.mode == MapViewMode.newTaz) {
      return "${widget.title}\nTAZ: ${widget.selectedTazId ?? 'None'}";
    } else if (widget.mode == MapViewMode.blocks) {
      if (widget.selectedIds != null && widget.selectedIds!.isNotEmpty) {
        return "${widget.title}\nSelected: ${widget.selectedIds!.join(', ')}";
      } else {
        return "${widget.title}\nSelected: None";
      }
    } else {
      return widget.title;
    }
  }

  /// Callback when the map is created.
  void _onMapCreated(MaplibreMapController ctrl) {
    controller = ctrl;
    // After the first frame, check if we need to move the camera to a synced position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeMoveToSyncedPosition();
    });
  }

  /// Called when the map's style is fully loaded.
  Future<void> _onStyleLoaded() async {
    // Reset the flag so that custom layers are always reloaded.
    _hasLoadedLayers = false;
    await _loadLayers();
  }

  /// Moves the map to the globally synced camera position (if any).
  void _maybeMoveToSyncedPosition() async {
    if (controller == null || widget.syncedCameraPosition == null) return;
    _isProgrammaticallyUpdating = true;
    await controller!.moveCamera(
      CameraUpdate.newCameraPosition(widget.syncedCameraPosition!),
    );
  }

  /// Loads the drawing layers based on the current MapView mode.
  Future<void> _loadLayers() async {
    if (controller == null) return;
    try {
      if (widget.mode == MapViewMode.oldTaz) {
        await _loadOldTazLayers();
        await _loadRadiusCircle();
        await _loadBlocksFill();
        // If ID labels toggle is enabled, add the corresponding symbol layers.
        if (widget.showIdLabels) {
          await controller!.addSymbolLayer(
            "old_taz_target_source",
            "old_taz_target_labels",
            SymbolLayerProperties(
              textField: "{taz_id}",
              textSize: 12,
              textColor: "#0000FF",
              textHaloColor: "#FFFFFF",
              textHaloWidth: 1,
            ),
          );
          await controller!.addSymbolLayer(
            "old_taz_others_source",
            "old_taz_others_labels",
            SymbolLayerProperties(
              textField: "{taz_id}",
              textSize: 12,
              textColor: "#4169E1",
              textHaloColor: "#FFFFFF",
              textHaloWidth: 1,
            ),
          );
        }
      } else if (widget.mode == MapViewMode.newTaz) {
        await _loadNewTazLayers();
        await _loadRadiusCircle();
        await _loadBlocksFill();
        await controller!.addFillLayer(
          "new_taz_source",
          "selected_new_taz_fill",
          FillLayerProperties(
            fillColor: "#FFFF00",
            fillOpacity: 0.5,
          ),
          filter: (widget.selectedIds != null && widget.selectedIds!.isNotEmpty)
              ? ["in", "taz_id", ...widget.selectedIds!.toList()]
              : ["==", "taz_id", ""],
        );
        if (widget.showIdLabels) {
          await controller!.addSymbolLayer(
            "new_taz_source",
            "new_taz_labels",
            SymbolLayerProperties(
              textField: "{taz_id}",
              textSize: 12,
              textColor: "#FF0000",
              textHaloColor: "#FFFFFF",
              textHaloWidth: 1,
            ),
          );
        }
      } else if (widget.mode == MapViewMode.blocks) {
        await _loadBlocksFill();
        await _loadRadiusCircle();
        await controller!.addLineLayer(
          "blocks_source",
          "blocks_outline",
          LineLayerProperties(lineColor: "#000000", lineWidth: 1.5),
        );
        await controller!.addFillLayer(
          "blocks_fill_source",
          "selected_blocks_fill",
          FillLayerProperties(
            fillColor: "#FFFF00",
            fillOpacity: 0.7,
          ),
          filter: (widget.selectedIds != null && widget.selectedIds!.isNotEmpty)
              ? ["in", "geoid20", ...widget.selectedIds!.toList()]
              : ["==", "geoid20", ""],
        );
        if (widget.showIdLabels) {
          await controller!.addSymbolLayer(
            "blocks_fill_source",
            "blocks_labels",
            SymbolLayerProperties(
              textField: "{block_label}",
              textSize: 12,
              textColor: "#000000",
              textHaloColor: "#FFFFFF",
              textHaloWidth: 1,
            ),
          );
        }
      } else if (widget.mode == MapViewMode.combined) {
        // Load blocks, old TAZ, and new TAZ layers without auto-zoom.
        final blocksData = await _loadBlocksFill(zoom: false);
        final oldData = await _loadOldTazLayers(zoom: false);
        final newData = await _loadNewTazLayers(zoom: false);
        await _loadRadiusCircle();
        // Zoom out to fit all layers.
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

  /// Loads the Old TAZ polygons within the search radius and adds target and other TAZ layers.
  Future<Map<String, dynamic>?> _loadOldTazLayers({bool zoom = true}) async {
    if (controller == null ||
        widget.selectedTazId == null ||
        widget.radius == null) return null;

    final oldTazData = widget.cachedOldTaz ??
        await loadGeoJson('assets/geojsons/old_taz.geojson');
    final List<dynamic> allFeatures = oldTazData['features'] as List<dynamic>;
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
      'features': withinFeatures
    };

    // The "target" TAZ (drawn in bold orange).
    await _addGeoJsonSourceAndLineLayer(
      sourceId: "old_taz_target_source",
      layerId: "old_taz_target_line",
      geojsonData: {'type': 'FeatureCollection', 'features': targetFeatures},
      lineColor: "#ff8000",
      lineWidth: 2.0,
    );
    await _addGeoJsonSourceAndFillLayer(
      sourceId: "old_taz_target_fill_source",
      layerId: "old_taz_target_fill",
      geojsonData: {'type': 'FeatureCollection', 'features': targetFeatures},
      fillColor: "#ff8000",
      fillOpacity: 0.18,
    );

    // The "other" TAZ polygons within the radius.
    await _addGeoJsonSourceAndLineLayer(
      sourceId: "old_taz_others_source",
      layerId: "old_taz_others_line",
      geojsonData: {'type': 'FeatureCollection', 'features': otherFeatures},
      lineColor: "#4169E1",
      lineWidth: 2.0,
    );
    await _addGeoJsonSourceAndFillLayer(
      sourceId: "old_taz_others_fill_source",
      layerId: "old_taz_others_fill",
      geojsonData: {'type': 'FeatureCollection', 'features': otherFeatures},
      fillColor: "#4169E1",
      fillOpacity: 0.18,
    );

    if (zoom) await _zoomToFeatureBounds(combinedData);
    return combinedData;
  }

  /// Loads the New TAZ polygons within the search radius.
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

    // Filter new TAZ features by distance to the old TAZ centroid.
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

  /// Draws all blocks from the cached GeoJSON with a simple outline and fill.
  Future<void> _drawAllBlocksSimple() async {
    if (controller == null || widget.cachedBlocks == null) return;
    final blocksData = widget.cachedBlocks!;
    await controller!.addSource(
      "blocks_source",
      GeojsonSourceProperties(data: blocksData),
    );
    await controller!.addLineLayer(
      "blocks_source",
      "blocks_outline",
      LineLayerProperties(
        lineColor: "#000000",
        lineWidth: 1.0,
      ),
    );
    await controller!.addFillLayer(
      "blocks_source",
      "blocks_fill",
      FillLayerProperties(
        fillColor: "#FFA500",
        fillOpacity: 0.18,
      ),
    );
    await _zoomToFeatureBounds(blocksData);
  }

  /// Loads the block polygons within the search radius using an R-Tree prefilter.
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
      centerLng - deltaLng,
      centerLat - deltaLat,
      2 * deltaLng,
      2 * deltaLat,
    );
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
    double fillOpacity = widget.mode == MapViewMode.blocks ? 0.18 : 0.05;
    await _addGeoJsonSourceAndFillLayer(
      sourceId: "blocks_fill_source",
      layerId: "blocks_fill",
      geojsonData: filteredBlocksData,
      fillColor: "#FFA500",
      fillOpacity: fillOpacity,
    );
    await _addGeoJsonSourceAndLineLayer(
      sourceId: "blocks_line_source",
      layerId: "blocks_line",
      geojsonData: filteredBlocksData,
      lineColor: "#000000",
      lineWidth: 0.4,
    );
    if (zoom) await _zoomToFeatureBounds(filteredBlocksData);
    return filteredBlocksData;
  }

  /// Draws the circle approximating the radius around the currently selected old TAZ.
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
      "radius_circle_source",
      GeojsonSourceProperties(data: circleFeature),
    );
    await controller!.addFillLayer(
      "radius_circle_source",
      "radius_circle_fill",
      FillLayerProperties(
        fillColor: "#0000FF",
        fillOpacity: 0,
      ),
    );
    await controller!.addLineLayer(
      "radius_circle_source",
      "radius_circle_line",
      LineLayerProperties(
        lineColor: "#FF8C00",
        lineWidth: 2.0,
      ),
    );
  }

  /// Adds a source and a line layer for the provided GeoJSON data.
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
      LineLayerProperties(
        lineColor: lineColor,
        lineWidth: lineWidth,
      ),
    );
  }

  /// Adds a source and a fill layer for the provided GeoJSON data.
  Future<void> _addGeoJsonSourceAndFillLayer({
    required String sourceId,
    required String layerId,
    required Map<String, dynamic> geojsonData,
    required String fillColor,
    double fillOpacity = 0.08,
  }) async {
    await controller!
        .addSource(sourceId, GeojsonSourceProperties(data: geojsonData));
    await controller!.addFillLayer(
      sourceId,
      layerId,
      FillLayerProperties(
        fillColor: fillColor,
        fillOpacity: fillOpacity,
      ),
    );
  }

  /// Zooms the camera to fit all features in the given FeatureCollection.
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
            minLat = (minLat == null) ? lat : math.min(lat, minLat);
            maxLat = (maxLat == null) ? lat : math.max(lat, maxLat);
            minLng = (minLng == null) ? lng : math.min(lng, minLng);
            maxLng = (maxLng == null) ? lng : math.max(lng, maxLng);
          }
        }
      } else if (geomType == 'MultiPolygon') {
        for (final polygon in coords) {
          for (final ring in polygon) {
            for (final point in ring) {
              final double lng = (point[0] as num).toDouble();
              final double lat = (point[1] as num).toDouble();
              minLat = (minLat == null) ? lat : math.min(lat, minLat);
              maxLat = (maxLat == null) ? lat : math.max(lat, maxLat);
              minLng = (minLng == null) ? lng : math.min(lng, minLng);
              maxLng = (maxLng == null) ? lng : math.max(lng, maxLng);
            }
          }
        }
      }
    }
    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      final sw = LatLng(minLat, minLng);
      final ne = LatLng(maxLat, maxLng);
      final bounds = LatLngBounds(southwest: sw, northeast: ne);
      _isProgrammaticallyUpdating = true;
      controller!.moveCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          left: 50,
          right: 50,
          top: 50,
          bottom: 50,
        ),
      );
    }
  }

  /// Handles a map tap event by querying rendered features.
  Future<void> _handleMapClick(Point<double> tapPoint) async {
    if (controller == null) return;
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
    final features =
        await controller!.queryRenderedFeatures(tapPoint, layersToQuery, []);
    if (features != null && features.isNotEmpty) {
      final feature = features.first;
      if (widget.mode == MapViewMode.blocks) {
        final dynamic blockId = feature["properties"]?["geoid20"];
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
