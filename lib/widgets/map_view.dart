import 'package:flutter/material.dart';

import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class MapView extends StatefulWidget {
  const MapView({Key? key}) : super(key: key);

  @override
  MapViewState createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  MaplibreMapController? _controller;

  @override
  Widget build(BuildContext context) {
    return MaplibreMap(
      styleString: 'https://demotiles.maplibre.org/style.json',
      onMapCreated: _onMapCreated,
      initialCameraPosition: const CameraPosition(
        target: LatLng(39.0, -95.0),
        zoom: 4,
      ),
    );
  }

  Future<void> _onMapCreated(MaplibreMapController controller) async {
    _controller = controller;

    // Load each geojson from assets and add them as separate layers
    await _addGeoJsonSourceAndLayer(
      sourceId: "oldTazSource",
      layerId: "oldTazLayer",
      assetPath: "assets/geojson/CTPS_TDM23_TAZ_2017g_v202303.geojson",
      fillColor: "#F28F42",
    );

    await _addGeoJsonSourceAndLayer(
      sourceId: "newTazSource",
      layerId: "newTazLayer",
      assetPath: "assets/geojson/taz_new_Feb05_1.geojson",
      fillColor: "#5CA2D1",
    );

    await _addGeoJsonSourceAndLayer(
      sourceId: "blockSource",
      layerId: "blockLayer",
      assetPath: "assets/geojson/blocks20a.geojson",
      fillColor: "#D15C5C",
    );
  }

  Future<void> _addGeoJsonSourceAndLayer({
    required String sourceId,
    required String layerId,
    required String assetPath,
    required String fillColor,
  }) async {
    final geojsonString = await rootBundle.loadString(assetPath);
    final geojsonData = json.decode(geojsonString);

    // Add the source
    await _controller?.addSource(
      sourceId,
      GeojsonSourceProperties(data: geojsonData),
    );

    // Add a fill layer
    await _controller?.addFillLayer(
      sourceId,
      layerId,
      FillLayerProperties(
        fillColor: fillColor,
        fillOpacity: 0.6,
      ),
    );
  }

  /// Toggle layer visibility by ID
  Future<void> toggleLayerVisibility(String layerId, bool visible) async {
    if (_controller == null) return;
    await _controller!.setLayerVisibility(layerId, visible);
  }
}
