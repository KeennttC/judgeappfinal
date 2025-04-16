import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JudgeLandingPage extends StatefulWidget {
  const JudgeLandingPage({super.key});

  @override
  State<JudgeLandingPage> createState() => _JudgeLandingPageState();
}

class _JudgeLandingPageState extends State<JudgeLandingPage> {
  final CollectionReference participantsRef =
      FirebaseFirestore.instance.collection('participants');
  final CollectionReference criteriaRef =
      FirebaseFirestore.instance.collection('criteria');
  final String judgeEmail = FirebaseAuth.instance.currentUser?.email ?? '';

  late Future<List<String>> _criteriaFuture;
  final Map<String, Map<String, TextEditingController>> _controllers = {};

  @override
  void initState() {
    super.initState();
    _criteriaFuture = _fetchCriteria();
  }

  Future<List<String>> _fetchCriteria() async {
    final snapshot = await criteriaRef.get();
    return snapshot.docs.map((doc) => doc['name'].toString()).toList();
  }

  @override
  void dispose() {
    for (var entry in _controllers.values) {
      for (var controller in entry.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Judge Dashboard')),
      body: FutureBuilder<List<String>>(
        future: _criteriaFuture,
        builder: (context, criteriaSnapshot) {
          if (!criteriaSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final criteriaList = criteriaSnapshot.data!;

          return StreamBuilder<QuerySnapshot>(
            stream: participantsRef.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final participantId = doc.id;
                  final participantName = doc['name'];

                  final Map<String, dynamic> scoresMap =
                      Map<String, dynamic>.from(doc['scores'] ?? {});
                  final Map<String, dynamic> judgeScores =
                      Map<String, dynamic>.from(scoresMap[judgeEmail] ?? {});

                  // Initialize controllers for this participant if not already created
                  _controllers.putIfAbsent(participantId, () {
                    final Map<String, TextEditingController> ctrls = {};
                    for (var criterion in criteriaList) {
                      ctrls[criterion] = TextEditingController(
                        text: judgeScores[criterion]?.toString() ?? '',
                      );
                    }
                    return ctrls;
                  });

                  return Card(
                    margin: const EdgeInsets.all(10),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            participantName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...criteriaList.map((criterion) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: TextField(
                                controller: _controllers[participantId]![criterion],
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: '$criterion Score',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            );
                          }).toList(),
                          ElevatedButton(
                            onPressed: () async {
                              bool valid = true;
                              Map<String, double> updatedScores = {};

                              for (var criterion in criteriaList) {
                                final text = _controllers[participantId]![criterion]!.text;
                                final score = double.tryParse(text);
                                if (score == null || score < 0 || score > 100) {
                                  valid = false;
                                  break;
                                } else {
                                  updatedScores[criterion] = score;
                                }
                              }

                              if (valid) {
                                scoresMap[judgeEmail] = updatedScores;
                                await participantsRef.doc(participantId).update({
                                  'scores': scoresMap,
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Scores submitted successfully'),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Scores must be between 0 and 100'),
                                  ),
                                );
                              }
                            },
                            child: const Text('Submit Scores'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
