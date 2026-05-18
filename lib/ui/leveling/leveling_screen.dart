
import 'package:flutter/material.dart';

/// a screen that shows your levels in the different subjects
class LevelingScreen extends StatelessWidget {
  const LevelingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Leveling")),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Leveling system coming soon!"),
            SizedBox(height: 16),
            Text("Here you will be able to see your levels in the different subjects and track your progress."),
          ],
        ),
      ),
    );
  }
}