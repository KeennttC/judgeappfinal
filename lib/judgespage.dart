import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class JudgeLandingPage extends StatelessWidget {
  const JudgeLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final CollectionReference participantsRef =
        FirebaseFirestore.instance.collection('participants');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Judge Dashboard'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: participantsRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];

              // Safely check if 'score' exists
              final scoreText = doc.data().toString().contains('score')
                  ? doc['score'].toString()
                  : '';

              final TextEditingController scoreController = TextEditingController(
                text: scoreText,
              );

              return ListTile(
                title: Text(doc['name']),
                subtitle: TextField(
                  controller: scoreController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Score'),
                  onSubmitted: (value) {
                    final score = double.tryParse(value);
                    if (score != null) {
                      participantsRef.doc(doc.id).update({'score': score});
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
