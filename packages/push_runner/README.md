# push_runner

The Android half of push (ARCHITECTURE section 6.5): the Firebase Cloud Messaging
service, the queue of pushes, and the WorkManager job that runs the app's `pushMain`
entry point in an engine of its own while the app is closed. A plugin, so that every
Flutter engine of the app has its channel `tf/push`, the one the notification plugin
starts for a button included.

A build has FCM only when `app/android/app/google-services.json` of its own Firebase
project is present; without it `PushRunner.token` answers null.
