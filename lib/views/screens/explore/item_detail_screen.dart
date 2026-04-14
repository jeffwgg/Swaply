import 'package:flutter/material.dart';
import '../../../models/item_listing.dart';

class ItemDetailsScreen extends StatelessWidget {
  final ItemListing item;

  const ItemDetailsScreen(this.item, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Item Details')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 250,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 1, // Using 1 for now as we have one primary image
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          item.imageUrl,
                          height: 250,
                          width: MediaQuery.of(context).size.width - 40,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Text(
                item.name,
                style: const TextStyle(
                  fontSize: 24,
                  color: Color(0xFF5B21B6),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, color: Color(0xFF7C3AED), size: 18.0),
                  SizedBox(width: 5),
                  Text(
                    '@shirley_tan',
                    style: TextStyle(
                      fontSize: 18,
                      color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEDE9FE)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Asking Price',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFFA78BFA),
                              ),
                            ),
                            Text(
                              item.price != null ? 'RM ${item.price!.toStringAsFixed(0)}' : 'Trade Only',
                              style: const TextStyle(
                                fontSize: 24,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9E1FE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFC9AFF9)),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Status',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                            Text(
                              'Trading Open',
                              style: TextStyle(
                                fontSize: 24,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                    left: BorderSide(color: Color(0xFF5B21B6), width: 5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            color: Color(0xFF5B21B6),
                            size: 20,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Item Description',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5B21B6),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        item.description,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                    left: BorderSide(color: Color(0xFF5B21B6), width: 5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.transfer_within_a_station,
                            color: Color(0xFF5B21B6),
                            size: 20,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Trade Preferences',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5B21B6),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        item.preference,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
