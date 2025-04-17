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
  String searchQuery = '';
  bool isLoading = false;
  final ScrollController _scrollController = ScrollController();

  Future<double> _getTotalWeight() async {
    final snapshot = await criteriaRef.get();
    return snapshot.docs.fold<double>(0.0, (sum, doc) {
      final weight = (doc['weight'] ?? 0).toDouble();
      return sum + weight;
    });
  }

  void _showLoadingIndicator(bool value) {
    setState(() {
      isLoading = value;
    });
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showConfirmationDialog({
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true, // Tap-to-dismiss
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            onConfirm();
          }, child: const Text('Confirm')),
        ],
      ),
    );
  }

  void _editParticipantName(DocumentSnapshot doc) {
    final nameCtrl = TextEditingController(text: doc['name']);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text('Edit Participant Name'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) {
                _showErrorSnackbar('Name cannot be empty');
                return;
              }
              try {
                await participantsRef.doc(doc.id).update({'name': nameCtrl.text.trim()});
                Navigator.pop(context);
                _showErrorSnackbar('Participant name updated');
              } catch (e) {
                _showErrorSnackbar('Error updating name: $e');
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _resetParticipantScores(String id) {
    _showConfirmationDialog(
      title: 'Reset Scores',
      content: 'Are you sure you want to reset scores for this participant?',
      onConfirm: () async {
        try {
          await participantsRef.doc(id).update({'scores': {}});
          _showErrorSnackbar('Scores reset successfully');
        } catch (e) {
          _showErrorSnackbar('Error resetting scores: $e');
        }
      },
    );
  }

  Future<bool> _validateAllParticipantsHaveScores() async {
    final participantsSnap = await participantsRef.get();
    for (var doc in participantsSnap.docs) {
      final scores = doc['scores'] ?? {};
      if (scores.isEmpty) {
        return false;
      }
    }
    return true;
  }

  void _finalizeScores() async {
    final allHaveScores = await _validateAllParticipantsHaveScores();
    if (!allHaveScores) {
      _showErrorSnackbar('Cannot finalize scores. All participants must have scores.');
      return;
    }

    final ranked = await _calculateRankings();
    for (var r in ranked) {
      await participantsRef.doc(r['id']).update({'finalScore': r['total'], 'rank': r['rank']});
    }
    _showErrorSnackbar('Scores finalized & ranked');
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

  void _exportResults(List<Map<String, dynamic>> results) async {
    _showLoadingIndicator(true);
    try {
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Results exported successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting results: $e')));
    } finally {
      _showLoadingIndicator(false);
    }
  }

  Widget _buildWeightProgressBar() {
    return FutureBuilder<double>(
      future: _getTotalWeight(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final totalWeight = snapshot.data!;
        return Column(
          children: [
            LinearProgressIndicator(value: totalWeight, minHeight: 10),
            Text('${(totalWeight * 100).toStringAsFixed(0)}% of 100% used'),
          ],
        );
      },
    );
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

  void _removeCriterion(String id) {
    _showConfirmationDialog(
      title: 'Delete Criterion',
      content: 'Are you sure you want to delete this criterion?',
      onConfirm: () async {
        await criteriaRef.doc(id).delete();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Criterion deleted')));
      },
    );
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

  Widget _buildTabs() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: 'Criteria'),
              Tab(text: 'Participants'),
              Tab(text: 'Judges'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildCriteriaSection(),
                _buildParticipantsSection(),
                _buildJudgesSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCriteriaSection() {
    return Column(
      children: [
        const SizedBox(height: 10),
        const Text('Criteria Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        _buildWeightProgressBar(),
        StreamBuilder<QuerySnapshot>(
          stream: criteriaRef.snapshots(),
          builder: (_, snapshot) {
            if (!snapshot.hasData) return const CircularProgressIndicator();
            final filteredDocs = snapshot.data!.docs.where((doc) {
              final name = doc['name'].toString().toLowerCase();
              return name.contains(searchQuery);
            }).toList();
            return SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: filteredDocs.map((doc) {
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
      ],
    );
  }

  Widget _buildParticipantsSection() {
    return Column(
      children: [
        const SizedBox(height: 10),
        const Text(
          'Participants',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: _addParticipantDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Participant'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final results = await _calculateRankings();
                if (results.isEmpty) {
                  _showErrorSnackbar('No participants to rank.');
                  return;
                }
                _showRankingsDialog(results);
              },
              icon: const Icon(Icons.leaderboard),
              label: const Text('View Rankings'),
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: participantsRef.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final filteredDocs = snapshot.data!.docs.where((doc) {
                final name = doc['name'].toString().toLowerCase();
                return name.contains(searchQuery);
              }).toList();
              if (filteredDocs.isEmpty) {
                return const Center(child: Text('No participants found.'));
              }
              return ListView.builder(
                controller: _scrollController,
                itemCount: filteredDocs.length,
                itemBuilder: (_, i) {
                  final doc = filteredDocs[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    child: ListTile(
                      title: Text(doc['name']),
                      subtitle: const Text('Tap to reset scores'),
                      onTap: () => _resetParticipantScores(doc.id),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _editParticipantName(doc),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _showConfirmationDialog(
                              title: 'Delete Participant',
                              content: 'Are you sure you want to delete this participant?',
                              onConfirm: () async {
                                await participantsRef.doc(doc.id).delete();
                                _showErrorSnackbar('Participant deleted.');
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showRankingsDialog(List<Map<String, dynamic>> results) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text('Rankings'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Rank')),
                const DataColumn(label: Text('Name')),
                ...results[0]['scores'].keys.map((c) => DataColumn(label: Text(c))).toList(),
                const DataColumn(label: Text('Total')),
              ],
              rows: results.map((r) {
                return DataRow(
                  cells: [
                    DataCell(Text('${r['rank']}')),
                    DataCell(Text(r['name'])),
                    ...r['scores'].values.map((s) => DataCell(Text('$s'))).toList(),
                    DataCell(Text('${r['total'].toStringAsFixed(2)}')),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            onPressed: () async {
              for (var r in results) {
                await participantsRef.doc(r['id']).update({
                  'finalScore': r['total'],
                  'rank': r['rank'],
                });
              }
              Navigator.pop(context);
              _showErrorSnackbar('Scores finalized & ranked.');
            },
            child: const Text('Finalize Scores'),
          ),
        ],
      ),
    );
  }

  Widget _buildJudgesSection() {
    return Column(
      children: [
        const SizedBox(height: 10),
        const Text('Judges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ElevatedButton(onPressed: _createJudgeAccountDialog, child: const Text('Create Judge Account')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search participants or criteria...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildTabs(),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        ),
        child: const Icon(Icons.arrow_upward),
      ),
    );
  }
}
