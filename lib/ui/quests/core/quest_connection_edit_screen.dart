import 'package:flutter/material.dart';
import 'package:lumox/logic/quests/quest_change_manager.dart';
import 'package:lumox/logic/quests/quest_connection.dart';
import 'package:lumox/logic/quests/quest_system.dart';

import '../../theme/theme_ui_values.dart';

class QuestConnectionEditScreen extends StatelessWidget {
  final QuestConnection connection;
  final QuestSystem questSystem;

  QuestConnectionEditScreen({super.key, required this.connection, required this.questSystem});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.45,
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.uiRadiusLg)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Edit Connection", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                _buildField(
                  context: context,
                  label: "Type",
                  icon: Icons.category,
                  initialValue: connection.type,
                ),

                const SizedBox(height: 16),

                _buildField(
                  context: context,
                  label: "XP Requirement",
                  icon: Icons.star,
                  initialValue: connection.xpRequirement.toString(),
                  isNumber: true,
                  onSubmitted: (value) {
                    if (double.tryParse(value) == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a valid number.")));
                      return;
                    }
                  },
                ),

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        final typeVal = getController("Type", connection.type).text;
                        final typeChanged = typeVal.isNotEmpty && typeVal != connection.type;

                        final xpVal = getController("XP Requirement", connection.xpRequirement.toString()).text;
                        final xpChanged = xpVal.isNotEmpty && double.tryParse(xpVal) != connection.xpRequirement;

                        if (xpChanged || typeChanged) {
                          print("Recording change for connection ${connection.fromQuestId} -> ${connection.toQuestId}: typeChanged=$typeChanged (new value: $typeVal), xpChanged=$xpChanged (new value: $xpVal)");
                          questSystem.changeManager.record(
                            UpdateConnectionChange(
                              fromId: connection.fromQuestId,
                              toId: connection.toQuestId,
                              patch: QuestConnectionPatch(type: typeChanged ? typeVal : null, xpRequirement: xpChanged ? double.tryParse(xpVal) : null),
                              reversePatch: QuestConnectionPatch(type: connection.type),
                            )
                          );
                        }
                        Navigator.pop(context);
                      },
                      child: const Text("Done"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final Map<String, TextEditingController> controllers = {};

  TextEditingController getController(String field, String initialValue) {
    if (!controllers.containsKey(field)) {
      controllers[field] = TextEditingController(text: initialValue);
    }
    return controllers[field]!;
  }

  Widget _buildField({
    required BuildContext context,
    required String label,
    required IconData icon,
    required String initialValue,
    void Function(String)? onSubmitted,
    bool isNumber = false,
  }) {
    return TextFormField(
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.uiRadiusMd)),
      ),
      controller: getController(label, initialValue),
      onFieldSubmitted: onSubmitted,
      onEditingComplete: () => onSubmitted?.call(getController(label, initialValue).text),
    );
  }
}
