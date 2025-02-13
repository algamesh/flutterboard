import 'package:flutter/material.dart';
import '../widgets/map_view.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _showOldTaz = true;
  bool _showNewTaz = true;
  bool _showBlocks = true;

  final GlobalKey<MapViewState> _mapKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shapefile to GeoJSON Demo'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Old TAZ
                Checkbox(
                  value: _showOldTaz,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _showOldTaz = val);
                    _mapKey.currentState
                        ?.toggleLayerVisibility("oldTazLayer", val);
                  },
                ),
                const Text('Old TAZ'),

                // New TAZ
                Checkbox(
                  value: _showNewTaz,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _showNewTaz = val);
                    _mapKey.currentState
                        ?.toggleLayerVisibility("newTazLayer", val);
                  },
                ),
                const Text('New TAZ'),

                // Blocks
                Checkbox(
                  value: _showBlocks,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _showBlocks = val);
                    _mapKey.currentState
                        ?.toggleLayerVisibility("blockLayer", val);
                  },
                ),
                const Text('Blocks'),
              ],
            ),
          ),
          Expanded(
            child: MapView(key: _mapKey),
          ),
        ],
      ),
    );
  }
}
