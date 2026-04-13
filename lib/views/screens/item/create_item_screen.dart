import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:swaply/models/item_listing.dart';
import 'package:swaply/repositories/items_repository.dart';
import 'package:swaply/services/supabase_service.dart';

class CreateItemScreen extends StatefulWidget {
  const CreateItemScreen({super.key});

  @override
  State<CreateItemScreen> createState() => _CreateItemScreenState();
}

class _CreateItemScreenState extends State<CreateItemScreen> {
  bool _isLoading = false;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _prefCtrl = TextEditingController();
  final _customCategoryCtrl = TextEditingController();

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
  final _formKey = GlobalKey<FormState>();

  Future<void> _pickImage() async {
    final XFile? selectedImage = await _picker.pickImage(
      source: ImageSource.gallery,
    );
    if (selectedImage != null) {
      setState(() {
        _images.add(selectedImage);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _prefCtrl.dispose();
    _customCategoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _createItem() async {
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    final preference = _prefCtrl.text.trim();

    final category = _selectedCategory == 'Others'
        ? _customCategoryCtrl.text.trim()
        : _selectedCategory;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in item name.')),
      );
      return;
    }

    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in item description.')),
      );
      return;
    }

    if (category == null || category.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill in category.')));
      return;
    }

    if (!_enableSelling && !_enableTrading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable selling or trading.')),
      );
      return;
    }

    if (_enableSelling && price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price.')),
      );
      return;
    }

    if (_enableTrading && preference.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter trade preferences.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Logic to get the next ID
      final lastIdStr = await ItemsRepository().getLastId();
      int nextIdNum = 1;
      if (lastIdStr != null) {
        nextIdNum = (int.tryParse(lastIdStr) ?? 0) + 1;
      }
      final newId = nextIdNum.toString();

      final currentUser = SupabaseService.client.auth.currentUser;
      final ownerId = currentUser?.id ?? '1'; // todo

      String listingType = 'both';
      if (_enableSelling && !_enableTrading) listingType = 'sell';
      if (!_enableSelling && _enableTrading) listingType = 'trade';

      final item = ItemListing(
        id: newId,
        name: name,
        description: desc,
        price: _enableSelling ? price : null,
        listingType: listingType,
        ownerId: ownerId,
        status: 'available',
        category: category,
        preference: _enableTrading ? preference : 'None',
        createdAt: DateTime.now(),
      );

      await ItemsRepository().create(item);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item created successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating item: $e')));
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
    return Scaffold(
      appBar: AppBar(title: const Text('Create Item')),
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
                  itemCount: _images.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Picker Box
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

                    // Preview Boxes
                    final imageIndex = index - 1;
                    return Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(_images[imageIndex].path),
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
                            onTap: () => _removeImage(imageIndex),
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
                  },
                ),
              ),
              const SizedBox(height: 30),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  hintText: 'Eg. Premium Headphones',
                  filled: true,
                  fillColor: Color(0xFFF3E8FF),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter item name.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                hint: const Text('Select Category'),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFFF3E8FF),
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
              if (_selectedCategory == 'Others') ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _customCategoryCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Custom Category',
                    hintText: 'Enter your category',
                    filled: true,
                    fillColor: Color(0xFFF3E8FF),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                  ),
                  validator: (value) {
                    if (_selectedCategory == 'Others') {
                      if (value == null || value.isEmpty) {
                        return 'Please enter item category.';
                      }
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Tell anything about the item(s). ',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: Color(0xFFF3E8FF),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter item description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
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
                    fillColor: Color(0xFFF3E8FF),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                  ),
                  validator: (value) {
                    if (_enableSelling) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter item price.';
                      }
                    }
                    return null;
                  },
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
                    fillColor: Color(0xFFF3E8FF),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  validator: (value) {
                    if (_enableTrading) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter trade preferences.';
                      }
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isLoading ? null : _createItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Create Item',
                        style: TextStyle(
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
}
