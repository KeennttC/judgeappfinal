import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share/share.dart';
import 'package:flutter/services.dart';

class AdminLandingPage extends StatefulWidget {
  const AdminLandingPage({super.key});

  @override
  _AdminLandingPageState createState() => _AdminLandingPageState();
}

class _AdminLandingPageState extends State<AdminLandingPage> {
  final participantsRef = FirebaseFirestore.instance.collection('participants');
  final criteriaRef = FirebaseFirestore.instance.collection('criteria');

  Future<double> _getTotalWeight() async {
    final snapshot = await criteriaRef.get();
    return snapshot.docs.fold<double>(0.0, (sum, doc) {
      final weight = (doc['weight'] ?? 0).toDouble();
      return sum + weight;
    });
  }

  void _addCriterionDialog() {
    String name = '';
    String weight = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Criterion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (value) => name = value,
            ),
            TextField(
              decoration: const InputDecoration(labelText: 'Weight (1-100%)'),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                if (int.tryParse(value) != null &&
                    int.parse(value) >= 1 &&
                    int.parse(value) <= 100) {
                  weight = value;
                }
              },
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            Text('$weight%'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final parsedWeight = int.tryParse(weight);
              if (name.trim().isNotEmpty && parsedWeight != null) {
                final currentTotal = await _getTotalWeight();
                final newTotal = currentTotal + (parsedWeight / 100);
                if (newTotal > 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Total weight cannot exceed 100%')),
                  );
                  return;
                }
                await criteriaRef.add({'name': name.trim(), 'weight': parsedWeight / 100});
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _editCriterionDialog(DocumentSnapshot doc) {
    String name = doc['name'];
    String weight = (doc['weight'] * 100).toString();
    final nameCtrl = TextEditingController(text: name);
    final weightCtrl = TextEditingController(text: weight);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Criterion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: weightCtrl,
              decoration: const InputDecoration(labelText: 'Weight (1-100%)'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            Text('${weightCtrl.text}%'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newWeight = int.tryParse(weightCtrl.text);
              if (nameCtrl.text.isNotEmpty && newWeight != null) {
                final currentTotal = await _getTotalWeight();
                final currentWeight = doc['weight'];
                final adjustedTotal = currentTotal - currentWeight + (newWeight / 100);
                if (adjustedTotal > 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Total weight cannot exceed 100%')),
                  );
                  return;
                }
                await criteriaRef.doc(doc.id).update({
                  'name': nameCtrl.text,
                  'weight': newWeight / 100,
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _removeCriterion(String id) => criteriaRef.doc(id).delete();

  void _exportResults(List<Map<String, dynamic>> results) async {
    final dir = await getApplicationDocumentsDirectory();
    final jsonFile = File('${dir.path}/results.json');
    final csvFile = File('${dir.path}/results.csv');
    final pdf = pw.Document();

    await jsonFile.writeAsString(jsonEncode(results));

    final headers = ['Rank', 'Name', ...results[0]['scores'].keys, 'Total'];
    final csvContent = StringBuffer()..writeln(headers.join(','));
    for (var r in results) {
      final row = [r['rank'], r['name'], ...r['scores'].values, r['total'].toStringAsFixed(2)];
      csvContent.writeln(row.join(','));
    }
    await csvFile.writeAsString(csvContent.toString());

    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Table.fromTextArray(
            headers: headers,
            data: results.map((r) => [r['rank'], r['name'], ...r['scores'].values, r['total'].toStringAsFixed(2)]).toList(),
          );
        },
      ),
    );
    final pdfFile = File('${dir.path}/results.pdf');
    await pdfFile.writeAsBytes(await pdf.save());

    Share.shareFiles([jsonFile.path, csvFile.path, pdfFile.path], text: 'Judging Results');
  }

  Future<List<Map<String, dynamic>>> _calculateRankings() async {
    final criteriaSnap = await criteriaRef.get();
    final participantsSnap = await participantsRef.get();

    final weights = {
      for (var doc in criteriaSnap.docs) doc['name']: doc['weight'] as double
    };

    final results = participantsSnap.docs.map((doc) {
      final scores = Map<String, dynamic>.from(doc['scores'] ?? {});
      double total = 0;
      weights.forEach((k, w) {
        total += (scores[k] ?? 0) * w;
      });
      return {
        'id': doc.id,
        'name': doc['name'],
        'scores': scores,
        'total': double.parse(total.toStringAsFixed(2))
      };
    }).toList();

    results.sort((a, b) => b['total'].compareTo(a['total']));

    double? lastScore;
    int rank = 0;
    int displayRank = 0;
    for (var r in results) {
      rank++;
      if (r['total'] != lastScore) {
        displayRank = rank;
        lastScore = r['total'];
      }
      r['rank'] = displayRank;
    }

    return results;
  }

  void _finalizeScores() async {
    final ranked = await _calculateRankings();
    for (var r in ranked) {
      await participantsRef.doc(r['id']).update({'finalScore': r['total'], 'rank': r['rank']});
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scores finalized & ranked')),
    );
  }

  void _resetParticipantScores(String id) {
    participantsRef.doc(id).update({'scores': {}});
  }

  void _createJudgeAccountDialog() {
    final emailCtrl = TextEditingController();
    final pwCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Judge Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: pwCtrl, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseAuth.instance.createUserWithEmailAndPassword(
                  email: emailCtrl.text, password: pwCtrl.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Judge account created')));
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _addParticipantDialog() {
    String name = '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Participant'),
        content: TextField(
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (name.trim().isNotEmpty) {
                participantsRef.add({'name': name, 'scores': {}});
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: Column(
        children: [
          const SizedBox(height: 10),
          const Text('Criteria Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          StreamBuilder<QuerySnapshot>(
            stream: criteriaRef.snapshots(),
            builder: (_, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              return SizedBox(
                height: 100,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: snapshot.data!.docs.map((doc) {
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(children: [
                          Text('${doc['name']} (${(doc['weight'] * 100).toStringAsFixed(0)}%)'),
                          Row(
                            children: [
                              IconButton(icon: const Icon(Icons.edit), onPressed: () => _editCriterionDialog(doc)),
                              IconButton(icon: const Icon(Icons.delete), onPressed: () => _removeCriterion(doc.id)),
                            ],
                          )
                        ]), 
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          ElevatedButton(onPressed: _addCriterionDialog, child: const Text('Add Criterion')),
          const Divider(),
          const Text('Participants', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: participantsRef.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    return ListTile(
                      title: Text(doc['name']),
                      subtitle: const Text('Tap to reset scores'),
                      onTap: () => _resetParticipantScores(doc.id),
                      trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => participantsRef.doc(doc.id).delete()),
                    );
                  },
                );
              },
            ),
          ),
          ElevatedButton(onPressed: _addParticipantDialog, child: const Text('Add Participant')),
          ElevatedButton(onPressed: _createJudgeAccountDialog, child: const Text('Create Judge Account')),
          ElevatedButton(
            onPressed: () async {
              final results = await _calculateRankings();
              _exportResults(results);
            },
            child: const Text('Export Results'),
          ),
          ElevatedButton(onPressed: _finalizeScores, child: const Text('Finalize & Rank')),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
