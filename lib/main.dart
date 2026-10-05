import 'package:flutter/material.dart';
import 'reg.dart'; // Import the registration page
import 'login.dart'; // Import the login page
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';// Import the OTP verification screen

import 'group_room_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();


@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await _localNotifications.initialize(initSettings);

  const channel = AndroidNotificationChannel(
    'default_channel',
    'General Notifications',
    description: 'Assignment, message, and billing updates',
    importance: Importance.high,
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}



Future<void> _showForegroundNotification(RemoteMessage message) async {
  final notification = message.notification;
  if (notification == null) return;
  await _localNotifications.show(
    notification.hashCode,
    notification.title,
    notification.body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'default_channel',
        'General Notifications',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

Future<void> _openRoomFromPush(RemoteMessage m) async {
  if (m.data['type'] != 'group_call') return;
  final prefs = await SharedPreferences.getInstance();
  final sid = prefs.getInt('student_id');
  final tid = prefs.getInt('teacher_id');
  if (sid == null || tid == null) return;
  navigatorKey.currentState?.push(MaterialPageRoute(
    builder: (_) => GroupRoomScreen(teacherId: tid, role: 'student', userId: sid),
  ));
}

/*void main() {
  runApp(const MyApp());
}*/
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await _initLocalNotifications();

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  FirebaseMessaging.onMessageOpenedApp.listen(_openRoomFromPush);

  final first = await FirebaseMessaging.instance.getInitialMessage();
if (first != null) {
  WidgetsBinding.instance.addPostFrameCallback((_) => _openRoomFromPush(first));
}

  FirebaseMessaging.onMessage.listen(_showForegroundNotification);

  final fcmToken = await FirebaseMessaging.instance.getToken();
  debugPrint('FCM TOKEN: $fcmToken');

  runApp(const MyApp()); // keep whatever your actual root widget class is called here
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
     
       // colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        cardTheme: CardThemeData(color: Colors.white),
      ),
      home: const Login(), // Set the home page to the registration page
      initialRoute: '/login', // Set the initial route to the registration page
      routes: {
        '/reg': (context) => const Registration(),
        '/login': (context) => const Login(),
        
        
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});


  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
    
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
 
    return Scaffold(
      appBar: AppBar(
       
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
        
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
