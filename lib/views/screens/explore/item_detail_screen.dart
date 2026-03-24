import 'package:flutter/material.dart';

class ItemDetailsScreen extends StatelessWidget {
  const ItemDetailsScreen({super.key});

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
                  itemCount: 3,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/sample.jpeg',
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
              const Text(
                'Premium Headphones',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'RM 249.00',
                style: TextStyle(
                    fontSize: 20,
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.w600
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Description',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'High-quality wireless headphones with noise cancellation and 40-hour battery life.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
