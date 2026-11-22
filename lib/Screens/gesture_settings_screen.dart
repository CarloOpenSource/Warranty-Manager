import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Services/settings_provider.dart';
import '../Services/Helpers/grouped_card.dart';

class GestureSettingsScreen extends StatelessWidget {
  const GestureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        final lang = settings.languageCode;

        return Scaffold(
          appBar: AppBar(
            title: Text(getText(lang, 'swipe_actions')),
          ),
          body: SafeArea(
  top: false,
   child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: GroupedCard(
                  items: [
                    // Wischgesten Ein/Aus
                    GroupedCardItem.switchTile(
                      switchSecondary: Icon(
                        Icons.swipe,
                        color: settings.appButtonColor,
                      ),
                      title: Text(getText(lang, 'swipe_actions')),
                      subtitle: Text(getText(lang, 'swipe_actions_desc')),
                      value: settings.useSwipeActions,
                      onChanged: (bool value) {
                        settings.setUseSwipeActions(value);
                      },
                      dividerAbove: false,
                    ),

                    // Rechte Wischgeste (nur wenn aktiviert)
                    if (settings.useSwipeActions)
                      GroupedCardItem(
                        leading: const Icon(
                          Icons.arrow_right_alt,
                          color: Colors.blue,
                          size: 22,
                        ),
                        title: Text(
                          getText(lang, 'swipe_right_action'),
                          style: const TextStyle(fontSize: 15),
                        ),
                        trailing: DropdownButton<String>(
                          value: settings.swipeRightAction,
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem(
                              value: 'edit',
                              child: Text(
                                getText(lang, 'swipe_action_edit'),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'delete',
                              child: Text(
                                getText(lang, 'swipe_action_delete'),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              settings.setSwipeRightAction(val);
                              if (val == settings.swipeLeftAction) {
                                settings.setSwipeLeftAction(
                                    val == 'edit' ? 'delete' : 'edit');
                              }
                            }
                          },
                        ),
                      ),

                    // Linke Wischgeste (nur wenn aktiviert)
                    if (settings.useSwipeActions)
                      GroupedCardItem(
                        leading: const Icon(
                          Icons.arrow_back,
                          color: Colors.red,
                          size: 22,
                        ),
                        title: Text(
                          getText(lang, 'swipe_left_action'),
                          style: const TextStyle(fontSize: 15),
                        ),
                        trailing: DropdownButton<String>(
                          value: settings.swipeLeftAction,
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem(
                              value: 'edit',
                              child: Text(
                                getText(lang, 'swipe_action_edit'),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'delete',
                              child: Text(
                                getText(lang, 'swipe_action_delete'),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              settings.setSwipeLeftAction(val);
                              if (val == settings.swipeRightAction) {
                                settings.setSwipeRightAction(
                                    val == 'edit' ? 'delete' : 'edit');
                              }
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        )
        );
      },
    );
  }
}