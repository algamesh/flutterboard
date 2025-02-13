import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  runApp(const MyApp());
}

/// Main App Widget
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

/// The Dashboard Page – mimicking the multi‐panel Bokeh layout
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

  // A label to show which TAZ is currently searched
  String _searchLabel = "Currently Searching TAZ: (none)";

  // Map keys (so we can programmatically control each map)
  final GlobalKey<MapViewState> _mapOldKey = GlobalKey();
  final GlobalKey<MapViewState> _mapNewKey = GlobalKey();
  final GlobalKey<MapViewState> _mapCombinedKey = GlobalKey();
  final GlobalKey<MapViewState> _mapBlocksKey = GlobalKey();

  // Example data for the "New TAZ" table
  List<Map<String, dynamic>> _newTazTableData = [];
  // Example data for the "Blocks" table
  List<Map<String, dynamic>> _blocksTableData = [];

  /// Called when the user presses "Search TAZ"
  void _runSearch() {
    final tazIdStr = _searchController.text.trim();
    if (tazIdStr.isEmpty) {
      setState(() {
        _searchLabel = "Currently Searching TAZ: (none)";
      });
      return;
    }

    // Parse the TAZ ID
    final tazId = int.tryParse(tazIdStr);
    if (tazId == null) {
      setState(() {
        _searchLabel = "Currently Searching TAZ: (invalid ID)";
      });
      return;
    }

    // Parse the radius
    final radius = double.tryParse(_radiusController.text.trim()) ?? 1000;

    setState(() {
      _searchLabel = "Currently Searching TAZ: $tazId";

      // TODO: Implement the real logic to:
      //  1) Find the geometry for this TAZ
      //  2) Buffer it by 'radius'
      //  3) Filter old/new/blocks data to within that buffer
      //  4) Update each map’s data/layers to show relevant polygons
      //  5) Update these tables to reflect the selected polygons

      // For demonstration, we’ll just set some dummy table data:
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

  /// Example function to synchronize zoom between maps
  Future<void> _matchZoom() async {
    // if (_mapOldKey.currentState?.controller == null) return;

    // final currentCamera =
    //     await _mapOldKey.currentState!.controller!.getCameraPosition();

    // // Update the other maps with the same camera settings:
    // _mapNewKey.currentState?.controller?.moveCamera(
    //   CameraUpdate.newCameraPosition(currentCamera),
    // );
    // _mapCombinedKey.currentState?.controller?.moveCamera(
    //   CameraUpdate.newCameraPosition(currentCamera),
    // );
    // _mapBlocksKey.currentState?.controller?.moveCamera(
    //   CameraUpdate.newCameraPosition(currentCamera),
    // );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("VizTAZ Dashboard"),
      ),
      body: Column(
        children: [
          // -----------------
          // TOP CONTROL BAR
          // -----------------
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
                // Search Button
                ElevatedButton(
                  onPressed: _runSearch,
                  child: const Text("Search TAZ"),
                ),
                const SizedBox(width: 8),
                // Match Zoom Button
                ElevatedButton(
                  onPressed: _matchZoom,
                  child: const Text("Match Zoom"),
                ),
                const SizedBox(width: 16),
                // Label: "Currently Searching TAZ: ..."
                Text(
                  _searchLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // -----------------
          // MAIN CONTENT
          // -----------------
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: 2×2 grid of maps
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: MapView(
                                key: _mapOldKey,
                                title: "Old TAZ (Green)",
                              ),
                            ),
                            Expanded(
                              child: MapView(
                                key: _mapNewKey,
                                title: "New TAZ (Red)",
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: MapView(
                                key: _mapCombinedKey,
                                title: "Combined",
                              ),
                            ),
                            Expanded(
                              child: MapView(
                                key: _mapBlocksKey,
                                title: "Blocks",
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Right side: Data Tables in a vertical column
                Container(
                  width: 400, // adjust as needed
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

/// Minimal MapView widget with MapLibre GL
class MapView extends StatefulWidget {
  final String title;

  const MapView({Key? key, required this.title}) : super(key: key);

  @override
  MapViewState createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  MaplibreMapController? controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MaplibreMap(
          // A public style; you can host your own style if needed
          styleString: 'https://demotiles.maplibre.org/style.json',
          onMapCreated: _onMapCreated,
          initialCameraPosition: const CameraPosition(
            target: LatLng(39.0, -95.0), // center on US
            zoom: 4,
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

  void _onMapCreated(MaplibreMapController ctrl) async {
    controller = ctrl;

    // If you want to load geojson layers right away:
    // await _addGeoJsonSourceAndLayer(...);
  }

  /// Example: function to load a GeoJSON source and add a fill layer
  Future<void> _addGeoJsonSourceAndLayer({
    required String sourceId,
    required String layerId,
    required Map<String, dynamic> geojsonData,
    required String fillColor,
  }) async {
    if (controller == null) return;

    // Add the source
    await controller!.addSource(
      sourceId,
      GeojsonSourceProperties(data: geojsonData),
    );

    // Add a fill layer
    await controller!.addFillLayer(
      sourceId,
      layerId,
      FillLayerProperties(
        fillColor: fillColor,
        fillOpacity: 0.6,
      ),
    );
  }

  /// Example: function to set a layer's visibility
  Future<void> toggleLayerVisibility(String layerId, bool visible) async {
    if (controller == null) return;
    await controller!.setLayerVisibility(layerId, visible);
  }
}
