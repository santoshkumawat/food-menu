# Daily Food Menu App - Plan

## Goal
Android app that notifies your wife each day with today's menu, so nobody has to ask "what to cook?" or look at the sheet.

## Decisions
- Stack: Flutter (Dart), Android only
- Menu is editable in-app, stored locally on the phone (no server, no internet)
- 3 notifications daily: breakfast, lunch, dinner
- English only

## Features (v1)
1. **Today screen**: today's breakfast, lunch, dinner as cards; the next upcoming meal is highlighted.
2. **Weekly view**: Mon-Sun grid; tap a day to see or edit it.
3. **Edit menu**: change the dish text for any meal on any day.
4. **Notifications** (repeat weekly, survive reboot):
   - Breakfast / Lunch / Dinner reminders, with the dish name in the notification text
   - Weekday vs weekend default times (from the sheet: weekday breakfast 10:00, lunch 13:00, dinner 20:00; weekend breakfast 11:30, lunch 14:00, dinner 21:00). Reminders go out ~1 hour before cooking time. Adjustable in Settings.
5. **Extras from the sheet** (shown on a "Health" tab):
   - Daily routine: wake up, warm water + honey / Shilajit (alternating), soaked almonds, turmeric milk at night
   - Daily guidelines (water, no fried food, no raw tomato/spinach, etc.)
   - Medicine timings (empty in the sheet, so editable)
   - Optional: turmeric milk reminder on Tue/Thu/Sat at 9:30 PM

## Data model
- `Meal { day (1-7), type (breakfast|lunch|dinner), dishes (text) }` seeded from the sheet on first launch
- `Settings { times per meal for weekday/weekend, notifications on/off }`
- `Routine { day, time, text }` for the morning routine and extras
- Storage: `shared_preferences` (JSON) or `sqflite`; the data is small, so JSON is enough.

## Tech
- Flutter 3.x, packages: `flutter_local_notifications`, `timezone`, `shared_preferences`, `provider` (or Riverpod)
- Android needs: `POST_NOTIFICATIONS` (Android 13+), `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`
- Reschedule all notifications whenever the menu or the times change

## Phases
1. **Setup**: install Flutter + Android Studio / SDK, create the project, run on an emulator or phone
2. **Data + seed**: models, store, load the sheet's menu
3. **UI**: Today, Week, Edit, Settings, Health screens
4. **Notifications**: permissions, scheduling, reboot handling, test on a real phone
5. **Polish + ship**: app icon, name, release APK, install on your wife's phone (send the APK via WhatsApp or Drive)

## Open items / risks
- Some phone brands (Xiaomi, Oppo, Vivo) kill background apps, so the notification can be late. Fix: a one-time "disable battery optimization" prompt.
- The sheet has some gaps (Tue/Thu have no 8:00 almonds; Wed dinner is "Roti + sabzi" with no specifics). These are carried over as-is and editable.
- Next step: check whether Flutter and the Android SDK are already installed on this PC.
