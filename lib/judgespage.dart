import 'package:flutter/material.dart';

class JudgeLandingPage extends StatelessWidget {
  const JudgeLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Judge Dashboard'),
      ),
      body: const Center(
        child: Text(
          'Welcome to the Judge Dashboard!',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}