import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/models/item_listing.dart';
import 'package:swaply/repositories/items_repository.dart';
import 'package:swaply/services/supabase_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../../models/app_user.dart';

class CreateItemScreen extends StatefulWidget {
  final AppUser user;
  final ItemListing? item;
  final int? repliedTo;
  const CreateItemScreen({
    super.key,
    required this.user,
    this.item,
    this.repliedTo,
  });

  @override
  State<CreateItemScreen> createState() => _CreateItemScreenState();
}

class _CreateItemScreenState extends State<CreateItemScreen> {
  late final AppUser? user = widget.user;

  bool _isLoading = false;
  bool _isSearching = false;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _prefCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _locationSearchCtrl = TextEditingController();
  final MapController _mapController = MapController();

  double? _latitude;
  double? _longitude;
  LatLng? selectedLocation;
  String? selectedAddress;

  String? _selectedCategory;
  bool _enableSelling = true;
  bool _enableTrading = true;

  final List<String> _categories = [
    'Electronics',
    'Fashion',
    'Home',
    'Books',
    'Toys',
    'Others',
  ];

  final ImagePicker _picker = ImagePicker();
  final List<XFile> _images = [];
  List<String> _existingImageUrls = [];
  List<dynamic> _searchResults = [];
  Timer? _debounce;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    if (widget.item != null) {
      final item = widget.item!;
      _nameCtrl.text = item.name;
      _descCtrl.text = item.description;
      _priceCtrl.text = item.price?.toStringAsFixed(0) ?? '';
      _prefCtrl.text = item.preference ?? '';
      _addressCtrl.text = item.address ?? '';
      _latitude = item.latitude;
      _longitude = item.longitude;
      if (_latitude != null && _longitude != null) {
        selectedLocation = LatLng(_latitude!, _longitude!);
        selectedAddress = item.address;
      }
      _existingImageUrls = List.from(item.imageUrls);
      _selectedCategory = item.category;

      _enableSelling = item.listingType == 'sell' || item.listingType == 'both';
      _enableTrading =
          item.listingType == 'trade' || item.listingType == 'both';
    }

    if (widget.repliedTo != null) {
      _enableSelling = false;
      _enableTrading = false;
    }
  }

  Future<void> _pickImage() async {
    final List<XFile> selectedImages = await _picker.pickMultiImage();
    if (selectedImages.isNotEmpty) {
      setState(() {
        _images.addAll(selectedImages);
      });
    }
  }

  void _removeNewImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
    });
  }

  Future<String?> _uploadImage(XFile imageFile) async {
    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(imageFile.path)}';

      final bytes = await imageFile.readAsBytes();

      await SupabaseService.client.storage
          .from('items')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      return SupabaseService.client.storage
          .from('items')
          .getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
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
          "User-Agent": "SwaplyApp/1.0 (jieer524@gmail.com)",
          "Accept-Language": "en-US,en;q=0.5",
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint(
          "Nominatim search error: ${response.statusCode} ${response.body}",
        );
        return [];
      }
    } catch (e) {
      debugPrint("Search error: $e");
      return [];
    }
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (value.trim().isEmpty) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        return;
      }

      setState(() => _isSearching = true);
      final results = await _searchPlaces(value);

      if (!mounted) return;

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  Future<String> reverseGeocode(double lat, double lon) async {
    try {
      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=jsonv2",
      );

      final response = await http.get(
        url,
        headers: {
          "User-Agent": "SwaplyApp/1.0 (jieer524@gmail.com)",
          "Accept-Language": "en-US,en;q=0.5",
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data["display_name"] ?? "Unknown location";
      }
    } catch (e) {
      debugPrint("Reverse geocode error: $e");
    }
    return "Unknown location";
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _prefCtrl.dispose();
    _addressCtrl.dispose();
    _locationSearchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _saveItem() async {
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    final preference = _prefCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final category = _selectedCategory;

    if (_images.isEmpty && _existingImageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one photo.')),
      );
      return;
    }

    if (name.isEmpty || desc.isEmpty || category == null || category.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in name, description and category.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      List<String> finalImageUrls = List.from(_existingImageUrls);
      for (var img in _images) {
        final url = await _uploadImage(img);
        if (url != null) {
          finalImageUrls.add(url);
        }
      }

      if (finalImageUrls.isEmpty)
        throw Exception('At least one image is required.');

      String listingType = 'both';
      if (widget.repliedTo != null) {
        listingType = 'trade';
      } else {
        if (_enableSelling && !_enableTrading) listingType = 'sell';
        if (!_enableSelling && _enableTrading) listingType = 'trade';
      }

      if (widget.item != null) {
        final updatedItem = ItemListing(
          id: widget.item!.id,
          name: name,
          description: desc,
          price: _enableSelling ? price : null,
          listingType: listingType,
          ownerId: widget.item!.ownerId,
          status: widget.item!.status,
          category: category,
          imageUrls: finalImageUrls,
          preference: _enableTrading ? preference : '',
          repliedTo: widget.item!.repliedTo,
          createdAt: widget.item!.createdAt,
          address: address,
          latitude: _latitude,
          longitude: _longitude,
        );

        await ItemsRepository().update(updatedItem);
      } else {
        final lastId = await ItemsRepository().getLastId();
        int nextIdNum = (lastId ?? 0) + 1;

        final newItem = ItemListing(
          id: nextIdNum,
          name: name,
          description: desc,
          price: _enableSelling ? price : null,
          listingType: listingType,
          ownerId: widget.user.id,
          status: widget.repliedTo == null ? 'available' : 'pending',
          category: category,
          imageUrls: finalImageUrls,
          preference: _enableTrading ? preference : 'None',
          repliedTo: widget.repliedTo,
          createdAt: DateTime.now(),
          address: address,
          latitude: _latitude,
          longitude: _longitude,
        );

        await ItemsRepository().create(newItem);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.item != null ? 'Item updated!' : 'Item created!',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF5B21B6);
    const fieldFill = Color(0xFFF3E8FF);
    String title = 'Create Item';
    if (widget.item != null) title = 'Edit Item';
    if (widget.repliedTo != null) title = 'Offer Trade';

    String buttonText = 'Create Item';
    if (widget.item != null) buttonText = 'Update Item';
    if (widget.repliedTo != null) buttonText = 'Offer Trade';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: accent,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Item Photos',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6D28D9),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length + _existingImageUrls.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 100,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6D28D9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.add_a_photo,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      );
                    }

                    final adjustedIndex = index - 1;
                    if (adjustedIndex < _existingImageUrls.length) {
                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: _buildPreviewImage(
                                _existingImageUrls[adjustedIndex],
                                width: 100,
                                height: 100,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 5,
                            right: 15,
                            child: GestureDetector(
                              onTap: () => _removeExistingImage(adjustedIndex),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    } else {
                      final newImageIndex =
                          adjustedIndex - _existingImageUrls.length;
                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(
                                File(_images[newImageIndex].path),
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 5,
                            right: 15,
                            child: GestureDetector(
                              onTap: () => _removeNewImage(newImageIndex),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 26),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  hintText: 'Eg. Premium Headphones',
                  filled: true,
                  fillColor: fieldFill,
                  prefixIcon: Icon(Icons.inventory_2_outlined, color: accent),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                hint: const Text('Select Category'),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: fieldFill,
                  prefixIcon: Icon(Icons.category_outlined, color: accent),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                items: _categories.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCategory = newValue;
                  });
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Tell anything about the item(s). ',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: fieldFill,
                  prefixIcon: Icon(Icons.notes_outlined, color: accent),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 26),

              const Text(
                'Location',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6D28D9),
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _locationSearchCtrl,
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
                  height: 200,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final place = _searchResults[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          place['display_name'],
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: () {
                          final lat = double.parse(place['lat']);
                          final lon = double.parse(place['lon']);
                          final pos = LatLng(lat, lon);

                          setState(() {
                            selectedLocation = pos;
                            selectedAddress = place['display_name'];
                            _latitude = lat;
                            _longitude = lon;
                            _addressCtrl.text = selectedAddress!;
                            _searchResults = [];
                            _locationSearchCtrl.text = selectedAddress!;
                          });

                          _mapController.move(pos, 15);
                        },
                      );
                    },
                  ),
                ),

              const SizedBox(height: 10),

              Container(
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          selectedLocation ?? const LatLng(3.1390, 101.6869),
                      initialZoom: 13,
                      onTap: (tapPos, point) async {
                        final address = await reverseGeocode(
                          point.latitude,
                          point.longitude,
                        );
                        setState(() {
                          selectedLocation = point;
                          selectedAddress = address;
                          _latitude = point.latitude;
                          _longitude = point.longitude;
                          _addressCtrl.text = address;
                          _locationSearchCtrl.text = address;
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                        userAgentPackageName: "com.example.swaply",
                      ),
                      if (selectedLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: selectedLocation!,
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

              if (selectedAddress != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    selectedAddress!,
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontSize: 12,
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              if (widget.repliedTo == null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Enable Selling',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5B21B6),
                            ),
                          ),
                          Text(
                            'Allow users to buy this item',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        activeTrackColor: const Color(0xFF5B21B6),
                        value: _enableSelling,
                        onChanged: (bool newValue) {
                          setState(() {
                            _enableSelling = newValue;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                if (_enableSelling) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefix: Text(
                        'RM  ',
                        style: TextStyle(
                          color: Color(0xFF6D28D9),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      filled: true,
                      fillColor: fieldFill,
                      suffixIcon: Icon(Icons.sell_outlined, color: accent),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Enable Trading',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5B21B6),
                            ),
                          ),
                          Text(
                            'Allow users to offer item trades',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        activeTrackColor: const Color(0xFF5B21B6),
                        value: _enableTrading,
                        onChanged: (bool newValue) {
                          setState(() {
                            _enableTrading = newValue;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                if (_enableTrading) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _prefCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Trade Preferences',
                      hintText:
                          'What are you looking for in exchange? (e.g. vintage cameras, bike accessories)',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: fieldFill,
                      prefixIcon: Icon(Icons.swap_horiz, color: accent),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        buttonText,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewImage(
    String url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (url.startsWith('http')) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, size: 50),
      );
    }
    return Image.asset(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image, size: 50),
    );
  }
}
