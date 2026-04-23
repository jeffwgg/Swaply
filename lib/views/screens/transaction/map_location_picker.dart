import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class MapLocationPickerResult {
  final String address;
  final double latitude;
  final double longitude;

  const MapLocationPickerResult({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

class MapLocationPicker extends StatefulWidget {
  const MapLocationPicker({
    super.key,
    this.initialAddress,
    this.initialLat,
    this.initialLon,
    this.title = 'Select location',
  });

  final String? initialAddress;
  final double? initialLat;
  final double? initialLon;
  final String title;

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  final TextEditingController _searchCtrl = TextEditingController();
  final MapController _mapController = MapController();
  Timer? _debounce;

  bool _isSearching = false;
  List<dynamic> _searchResults = const [];

  LatLng? _selected;
  String? _selectedAddress;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLon != null) {
      _selected = LatLng(widget.initialLat!, widget.initialLon!);
      _selectedAddress = widget.initialAddress;
      if (_selectedAddress != null) {
        _searchCtrl.text = _selectedAddress!;
      }
    } else if (widget.initialAddress != null) {
      _searchCtrl.text = widget.initialAddress!;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _searchPlaces(String query) async {
    try {
      final url = Uri.https("nominatim.openstreetmap.org", "/search", {
        "q": query,
        "format": "jsonv2",
        "limit": "5",
        "addressdetails": "1",
      });

      final response = await http.get(
        url,
        headers: {
          "User-Agent": "SwaplyApp/1.0 (swaply)",
          "Accept-Language": "en-US,en;q=0.5",
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<String> _reverseGeocode(double lat, double lon) async {
    try {
      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=jsonv2",
      );
      final response = await http.get(
        url,
        headers: {
          "User-Agent": "SwaplyApp/1.0 (swaply)",
          "Accept-Language": "en-US,en;q=0.5",
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data["display_name"] ?? "Unknown location";
      }
    } catch (_) {}
    return "Unknown location";
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final q = value.trim();
      if (q.isEmpty) {
        if (!mounted) return;
        setState(() {
          _searchResults = const [];
          _isSearching = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() => _isSearching = true);
      final results = await _searchPlaces(q);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  Future<void> _useCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw StateError('Location services are disabled.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw StateError('Location permission denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError('Location permission permanently denied.');
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final address = await _reverseGeocode(pos.latitude, pos.longitude);
      final point = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _selected = point;
        _selectedAddress = address;
        _searchResults = const [];
        _searchCtrl.text = address;
      });
      _mapController.move(point, 15);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location error: $e')),
      );
    }
  }

  void _submitIfReady() {
    final point = _selected;
    final addr = _selectedAddress?.trim();
    if (point == null || addr == null || addr.isEmpty) return;
    Navigator.of(context).pop(
      MapLocationPickerResult(
        address: addr,
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected ?? const LatLng(3.1390, 101.6869);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: "Search location (e.g. KLCC)",
                  prefixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.my_location, color: Color(0xFF6D28D9)),
                    tooltip: "Use current location",
                    onPressed: _useCurrentLocation,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF3E8FF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
              if (_searchResults.isNotEmpty)
                Container(
                  height: 180,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final place = _searchResults[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          place['display_name']?.toString() ?? '',
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          final lat = double.tryParse(place['lat']?.toString() ?? '');
                          final lon = double.tryParse(place['lon']?.toString() ?? '');
                          if (lat == null || lon == null) return;
                          final pos = LatLng(lat, lon);
                          setState(() {
                            _selected = pos;
                            _selectedAddress = place['display_name']?.toString();
                            _searchResults = const [];
                            _searchCtrl.text = _selectedAddress ?? '';
                          });
                          _mapController.move(pos, 15);
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 13,
                        onTap: (tapPos, point) async {
                          final address =
                              await _reverseGeocode(point.latitude, point.longitude);
                          if (!mounted) return;
                          setState(() {
                            _selected = point;
                            _selectedAddress = address;
                            _searchCtrl.text = address;
                            _searchResults = const [];
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                          userAgentPackageName: "com.example.swaply",
                        ),
                        if (_selected != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _selected!,
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.location_pin,
                                  color: Colors.red,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if ((_selectedAddress ?? '').trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                  ),
                  child: Text(
                    _selectedAddress!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitIfReady,
                  child: const Text('Use this location'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

