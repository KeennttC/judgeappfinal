import 'package:flutter/material.dart';

class AdminLandingPage extends StatelessWidget {
  const AdminLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
      ),
      body: const Center(
        child: Text(
          'Welcome to the Admin Dashboard!',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}