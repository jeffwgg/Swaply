import 'package:flutter/material.dart';

class CreateItemScreen extends StatelessWidget {
  const CreateItemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Item')),
      body: const Center(
        child: Text(
          'Create Item',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
