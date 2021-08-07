import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:whatsapp_launcher/constants/const.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

/// Define a top-level named handler which background/terminated messages will
/// call.
///
/// To verify things are working, check out the native platform logs.
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  await Firebase.initializeApp();
  print('Handling a background message ${message.messageId}');
}

Future<bool> checkConnectivity() async {
  var connectivityResult = await (Connectivity().checkConnectivity());
  if (connectivityResult == ConnectivityResult.mobile) {
    return true;
  } else if (connectivityResult == ConnectivityResult.wifi) {
    return true;
  }
  return false;
}

/// Create a [AndroidNotificationChannel] for heads up notifications
AndroidNotificationChannel channel = const AndroidNotificationChannel(
  'high_importance_channel', // id
  'High Importance Notifications', // title
  'This channel is used for important notifications.', // description
  importance: Importance.high,
);

/// Initialize the [FlutterLocalNotificationsPlugin] package.
FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Set the background messaging handler early on, as a named top-level function
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  /// Update the iOS foreground notification presentation options to allow
  /// heads up notifications.
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  if (await checkConnectivity()) {
    try {
      await FirebaseMessaging.instance
          .subscribeToTopic('whatsapp_launcher_notification');

      print(await FirebaseMessaging.instance.getToken());
    } catch (e) {}
  }

  if (!kIsWeb) {
    /// Create an Android Notification Channel.
    ///
    /// We use this channel in the `AndroidManifest.xml` file to override the
    /// default FCM channel to enable heads up notifications.
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Whatsapp Launcher',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _token = '';

  @override
  void initState() {
    super.initState();
    FirebaseMessaging.instance
        .getInitialMessage()
        .then((RemoteMessage? message) {
      if (message != null) {
        // Navigator.pushNamed(context, '/message',
        //     arguments: MessageArguments(message, true));
      }
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification notification =
          message.notification as RemoteNotification;
      AndroidNotification android =
          message.notification?.android as AndroidNotification;
      if (notification != null && !kIsWeb) {
        flutterLocalNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channel.description,
                // TODO add a proper drawable resource to android, for now using
                //      one that already exists in example app.
                icon: 'launch_background',
              ),
            ));
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('A new onMessageOpenedApp event was published!');
      // Navigator.pushNamed(context, '/message',
      //     arguments: MessageArguments(message, true));
    });

    Timer(
        Duration(seconds: 1),
        () => Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (context) => SecondScreen())));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
            statusBarColor: Color(0xff232d36),
            systemNavigationBarColor: Color(0xff232d36)),
        child: Scaffold(
          body: Container(
            color: Color(0xffececec),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 6,
                    child: Container(
                      child: Image(
                        image: AssetImage("images/logo.png"),
                        // height: MediaQuery.of(context).size.height * .50,
                        width: MediaQuery.of(context).size.width * .75,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        "Powered by The Watchtower",
                        style: TextStyle(
                            color: Color(0xFFE9442B),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
  }
}

class SecondScreen extends StatefulWidget {
  @override
  _SecondScreenState createState() => _SecondScreenState();
}

class _SecondScreenState extends State<SecondScreen> {
  InAppWebViewController? _controller;
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  final Completer<InAppWebViewController> _controllerCompleter =
      Completer<InAppWebViewController>();
  var url = webViewInitUrl;

  @override
  void initState() {
    initConnectivity();

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((connection) {
      if (connection == ConnectivityResult.none) {
        _updateConnectionStatus(connection);
      }
    });

    _determinePosition();
    super.initState();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();

    super.dispose();
  }

  Future<bool> _exitApp(BuildContext context) async {
    if (await _controller!.canGoBack()) {
      print("onwill goback");
      _controller!.goBack();
    } else {
      // Scaffold.of(context).showSnackBar(
      //   const SnackBar(content: Text("No back history item")),
      // );
      return Future.value(true);
    }
    return false;
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initConnectivity() async {
    late ConnectivityResult result;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      result = await _connectivity.checkConnectivity();
    } on PlatformException catch (e) {
      print(e.toString());
      return;
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) {
      return Future.value(null);
    }

    return _updateConnectionStatus(result);
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    setState(() {
      _connectionStatus = result;
    });
  }

  /// Determine the current position of the device.
  ///
  /// When the location services are not enabled or permissions
  /// are denied the `Future` will return an error.
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await Geolocator.getCurrentPosition();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () => _exitApp(context),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
              statusBarColor: Color(0xff232d36),
              systemNavigationBarColor: Color(0xff232d36)),
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Color(0xff232d36), // status bar color
              brightness: Brightness.dark,
              toolbarHeight: 00, // status bar brightness
              elevation: 0,
            ),
            body: _connectionStatus == ConnectivityResult.none
                ? Container(
                    color: Colors.white,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Padding(
                            padding: EdgeInsets.only(bottom: 30),
                            child: Text(
                              'Looks like you are offline',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold),
                            )),
                        Padding(
                            padding: EdgeInsets.only(
                                bottom: 50, left: 20, right: 20),
                            child: Text(
                                'Please connect to the internet and try again.',
                                style: TextStyle(
                                    color: Colors.black, fontSize: 17))),
                        Container(
                          child: InkWell(
                            onTap: () async {
                              await initConnectivity();
                            },
                            child: Icon(
                              Icons.refresh,
                              color: Color(0xFFE9442B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : InAppWebView(
                    initialOptions: InAppWebViewGroupOptions(
                        crossPlatform: InAppWebViewOptions(
                            javaScriptEnabled: true,
                            javaScriptCanOpenWindowsAutomatically: true)),
                    initialUrlRequest: URLRequest(url: Uri.parse(url)),
                    androidOnGeolocationPermissionsShowPrompt:
                        (InAppWebViewController controller,
                            String origin) async {
                      return GeolocationPermissionShowPromptResponse(
                          origin: origin, allow: true, retain: true);
                    },
                    onWebViewCreated:
                        (InAppWebViewController webViewController) async {
                      _controllerCompleter.future
                          .then((value) => _controller = value);
                      _controllerCompleter.complete(webViewController);
                    },
                    onLoadStart: (controller, uri) {
                      url = uri.toString();
                    },
                  ),
          ),
        ));
  }
}
