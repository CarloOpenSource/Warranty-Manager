import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';

class RecurringEventDialog extends StatefulWidget {
  const RecurringEventDialog(this.deviceCalendarPlugin, this.calendarEvent, this.onLoadingStarted, this.onDeleteFinished, {super.key});

  final DeviceCalendarPlugin deviceCalendarPlugin;
  final Event calendarEvent;

  final VoidCallback onLoadingStarted;
  final Function(bool) onDeleteFinished;

  @override
  State<RecurringEventDialog> createState() => _RecurringEventDialogState();
}

class _RecurringEventDialogState extends State<RecurringEventDialog> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Are you sure you want to delete this event?'),
      children: <Widget>[
        SimpleDialogOption(
          onPressed: () async {
            Navigator.of(context).pop(true);
            widget.onLoadingStarted();

            final deleteResult = await widget.deviceCalendarPlugin.deleteEventInstance(
              widget.calendarEvent.calendarId,
              widget.calendarEvent.eventId,
              widget.calendarEvent.start?.millisecondsSinceEpoch,
              widget.calendarEvent.end?.millisecondsSinceEpoch,
              false,
            );

            widget.onDeleteFinished(deleteResult.isSuccess && deleteResult.data != null);
          },
          child: const Text('This instance only'),
        ),
        SimpleDialogOption(
          onPressed: () async {
            Navigator.of(context).pop(true);
            widget.onLoadingStarted();

            final deleteResult = await widget.deviceCalendarPlugin.deleteEventInstance(
              widget.calendarEvent.calendarId,
              widget.calendarEvent.eventId,
              widget.calendarEvent.start?.millisecondsSinceEpoch,
              widget.calendarEvent.end?.millisecondsSinceEpoch,
              true,
            );

            widget.onDeleteFinished(deleteResult.isSuccess && deleteResult.data != null);
          },
          child: const Text('This and following instances'),
        ),
        SimpleDialogOption(
          onPressed: () async {
            Navigator.of(context).pop(true);
            widget.onLoadingStarted();

            final deleteResult = await widget.deviceCalendarPlugin.deleteEvent(
              widget.calendarEvent.calendarId,
              widget.calendarEvent.eventId,
            );

            widget.onDeleteFinished(deleteResult.isSuccess && deleteResult.data != null);
          },
          child: const Text('All instances'),
        ),
        SimpleDialogOption(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          child: const Text('Cancel'),
        )
      ],
    );
  }
}
