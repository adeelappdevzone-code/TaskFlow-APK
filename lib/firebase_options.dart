// Firebase project config for TaskFlow (project: taskflow-ce905).
// Values come from google-services.json. These identify the project; they are
// not secret. Data is protected by the Firestore security rules
// (see firestore.rules in the repo root).
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBjip1baAq-KaDDqJy43rqmiv9607zBckU',
    appId: '1:791768449553:android:9b2577dabf4c5e886de7b0',
    messagingSenderId: '791768449553',
    projectId: 'taskflow-ce905',
    storageBucket: 'taskflow-ce905.firebasestorage.app',
  );
}
