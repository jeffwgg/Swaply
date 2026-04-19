import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationAddressService {
  LocationAddressService();

  Future<String?> resolveCurrentAddressLine() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition();
    final marks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    if (marks.isEmpty) {
      return null;
    }

    final p = marks.first;
    final parts = <String>[];

    void add(String? value) {
      final t = value?.trim();
      if (t != null && t.isNotEmpty) {
        parts.add(t);
      }
    }

    add(p.street);
    add(p.subLocality);
    add(p.locality);
    add(p.postalCode);
    add(p.administrativeArea);
    add(p.country);

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(', ');
  }
}
