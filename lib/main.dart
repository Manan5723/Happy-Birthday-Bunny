import 'dart:math';

import 'package:animated_splash_screen/animated_splash_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:notification_permissions/notification_permissions.dart';
import 'package:connectivity/connectivity.dart';
import 'package:thingsworld/new.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool initstatus = false;
// ignore: non_constant_identifier_names
bool BackgroundState = false;

final Mtopic = TopicNotifier();
String topic = Mtopic.value;

class TopicNotifier extends ValueNotifier<String> {
  TopicNotifier() : super('Test');

  void changeTopic(String arg) {
    value = arg;
    print(topic);
  }
}

//store locally
Future<void> savetopic() async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setString('topic', topic);
}

Future<String?> gettopic() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('topic');
}

List<Map<String, String>> resultArray = [];
final stateContainer = ProviderContainer();
//notification plugins
FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(
    child: MyApp(),
  ));
}

String clientID = 'Bunny-${DateTime.now()}';

final client = MqttServerClient('broker.thingsworld.cloud', clientID);

const notificationChannelId = 'my_foreground';

// this will be used for notification id, So you can update your custom notification with this id.
const notificationId = 888;

final service = FlutterBackgroundService();
Future<void> initializeService() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    'MY FOREGROUND SERVICE', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
        // this will be executed when app is in foreground or background in separated isolate
        onStart: onStart,
        autoStartOnBoot: true,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId:
            notificationChannelId, // this must match with notification channel you created above.
        initialNotificationTitle: 'GSM M2M',
        initialNotificationContent: 'Welcome to ThingsWorld ',
        foregroundServiceNotificationId: notificationId),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
onStart(ServiceInstance service) async {
  gettopic().then((value) => Mqttcon().bgmq(value!));
}

Future<void> _bgmq() async {
  client.logging(on: true);
  client.setProtocolV311();
  client.keepAlivePeriod = 25;
  client.connectTimeoutPeriod = 2500;
  client.pongCallback = () {
    print('ping');
  };

  final connMess = MqttConnectMessage()
      .withClientIdentifier(clientID)
      .withWillTopic('willtopic') // If you set this you must set a will message
      .withWillMessage('My Will message')
      .startClean() // Non persistent session for testing
      .withWillQos(MqttQos.atLeastOnce);
  print('EXAMPLE::Mosquitto client connecting....');
  client.connectionMessage = connMess;
  try {
    await client.connect();
  } on NoConnectionException catch (e) {
    showNotification(
        'Connection Failed kindly check your internet connection try to turn on and off the internet for reconnecting');
    // showNotification('Connection Error - $e');
    client.disconnect();
  } on SocketException catch (e) {
    // Raised by the socket layer
    showNotification(
        'Connection Failed kindly check your internet connection try to turn on and off the internet for reconnecting');
    // showNotification('Socket Exception - $e');
    client.disconnect();
  }

  /// Check we are connected
  if (client.connectionStatus!.state == MqttConnectionState.connected) {
    showNotification('Conected....');
  } else {
    /// Use status here rather than state if you also want the broker return code.
    showNotification(
        'Connection Failed kindly check your internet connection try to turn on and off the internet for reconnecting');
    client.disconnect();
    exit(-1);
  }

  client.onDisconnected = () async => {
        Connectivity().onConnectivityChanged.listen((event) {
          if (event != ConnectivityResult.none &&
              client.connectionStatus!.state == MqttConnectionState.connected) {
            _bgmq();
            return;
          }
        }),
        showNotification('Disconnected from device $topic')
      };

  client.subscribe(topic, MqttQos.atLeastOnce);
  client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
    final recMess = c![0].payload as MqttPublishMessage;
    final pt =
        MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    showNotification(pt);
  });
}

Future<void> showNotification(String message) async {
  flutterLocalNotificationsPlugin.show(
    0,
    'DEVICE ALERT',
    message,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        '0',
        'GSM Alerts',
        icon: 'ic_launcher',
        ongoing: false,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      ),
    ),
  );
}

Future<void> silentshowNotification(String message) async {
  flutterLocalNotificationsPlugin.show(
    1,
    'Reconecting',
    message,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        '1',
        'GSM Alerts',
        icon: 'ic_launcher',
        ongoing: false,
        priority: Priority.low,
        playSound: false,
        styleInformation: BigTextStyleInformation(''),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // ignore: prefer_const_constructors
    return MaterialApp(
      title: 'Flutter ',
      home: AnimatedSplashScreen(
          duration: 3000,
          splash: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'image/logo3.png',
                width: 200,
              ),
            ],
          ),
          nextScreen: const MyHomePage(
            title: 'GSM Starter',
          ),
          animationDuration: const Duration(milliseconds: 1500),
          splashTransition: SplashTransition.fadeTransition,
          backgroundColor: Colors.white),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  bool fetchingdata = false;
  bool showActivateDialog = true;
  bool showerrorDialog = false;
  bool showCmd = false;
  Future<String>? permissionStatusFuture;
  final TextEditingController controller = TextEditingController();
  final TextEditingController controller2 = TextEditingController();
  var permGranted = "granted";
  var permDenied = "denied";
  var permUnknown = "unknown";
  var permProvisional = "provisional";

  /// Checks the notification permission status
  Future<String> getCheckNotificationPermStatus() {
    return NotificationPermissions.getNotificationPermissionStatus()
        .then((status) {
      switch (status) {
        case PermissionStatus.denied:
          return permDenied;
        case PermissionStatus.granted:
          return permGranted;
        case PermissionStatus.unknown:
          return permUnknown;
        case PermissionStatus.provisional:
          return permProvisional;
        default:
          return ' ';
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        BackgroundState = false;
        setState(() {
          permissionStatusFuture = getCheckNotificationPermStatus();
        });
        print("app in resumed");
        break;
      case AppLifecycleState.inactive:
        initializeService();
        setState(() {
          BackgroundState = true;
        });
        print("app in inactive");
        break;
      case AppLifecycleState.paused:
        initializeService();
        setState(() {
          BackgroundState = true;
        });
        print("app in paused");
        break;
      case AppLifecycleState.detached:
        conectingMqt();
        setState(() {
          BackgroundState = true;
        });
        print("app in detached ");
        break;
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    // set up the notification permissions class
    // set up the future to fetch the notification data
    permissionStatusFuture = getCheckNotificationPermStatus();
    fetchingdata = false;

    gettopic().then((value) => {
          if (value != null)
            {
              Mtopic.changeTopic(value),
              conectingMqt(),
              showActivateDialog = false
            }
        });

    super.initState();
  }

  @pragma('vm:entry-point')
  Future<int> conectingMqt() async {
    client.logging(on: true);
    client.setProtocolV311();
    client.keepAlivePeriod = 25;
    client.connectTimeoutPeriod = 1000;
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;
    client.onSubscribed = onSubscribed;
    client.pongCallback = () {
      print('pong message');
    };

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientID)
        .withWillTopic(
            'willtopic') // If you set this you must set a will message
        .withWillMessage('My Will message')
        .startClean() // Non persistent session for testing
        .withWillQos(MqttQos.atLeastOnce);
    print('EXAMPLE::Mosquitto client connecting....');
    client.connectionMessage = connMess;
    try {
      await client.connect();
      silentshowNotification('Connected To Device $topic');
    } on NoConnectionException catch (e) {
      // Raised by the client when connection fails.
      print('EXAMPLE::client exception - $e');
      client.disconnect();
    } on SocketException catch (e) {
      // Raised by the socket layer
      print('EXAMPLE::socket exception - $e');
      client.disconnect();
    }

    /// Check we are connected
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      print('EXAMPLE::Mosquitto client connected');
    } else {
      /// Use status here rather than state if you also want the broker return code.
      print(
          'EXAMPLE::ERROR Mosquitto client connection failed - disconnecting, status is ${client.connectionStatus}');
      client.disconnect();
      exit(-1);
    }

    client.onDisconnected = () => {
          Connectivity().onConnectivityChanged.listen((event) {
            if (event != ConnectivityResult.none) {
              conectingMqt();
            }
          }),
          showNotification('Disconnected from device'),
        };

    /// Subscribe to it
    print('EXAMPLE::Subscribing to the Dart/Mqtt_client/testtopic topic');
    client.subscribe(topic, MqttQos.exactlyOnce);

    /// Ok, lets try a subscription
    print('EXAMPLE::Subscribing to the test/lol topic');
    // client.subscribe(topic, MqttQos.atMostOnce);

    /// The client has a change notifier object(see the Observable class) which we then listen to to get
    /// notifications of published updates to each subscribed topic.
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final recMess = c![0].payload as MqttPublishMessage;
      final pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      List<Map<String, String>> temp = [];
      resultArray.clear();
      temp.clear();
      List<String> stringArray = pt.split('\n');

      for (String s in stringArray) {
        List<String> propertyArray = s.split(':');

        if (propertyArray.length == 2) {
          Map<String, String> propertyMap = {
            'key': propertyArray[0].trim(),
            'value': propertyArray[1].trim(),
          };

          temp.add(propertyMap);
        }
        // push_Notification(pt);
      }

      setState(() {
        resultArray = temp;
        fetchingdata = true;
      });
      if (BackgroundState) {
        showNotification(pt);
      }
      print(resultArray);
    });

    client.published!.listen((MqttPublishMessage message) {
      print(
          'Published topic is ${message.variableHeader!.topicName}, with Qos ${message.header!.qos}');
    });

    print('EXAMPLE::Sleeping....');
    await MqttUtilities.asyncSleep(60);

    /// Finally, unsubscribe and exit gracefully
    // print('EXAMPLE::Unsubscribing');
    // client.unsubscribe(topic);
    return 0;
  }

  void onSubscribed(String topic) {
    print('EXAMPLE::Subscription confirmed for topic $topic');
  }

  /// The unsolicited disconnect callback
  void onDisconnected() {
    print('EXAMPLE::OnDisconnected client callback - Client disconnection');
    if (client.connectionStatus!.disconnectionOrigin ==
        MqttDisconnectionOrigin.solicited) {
      // setState(() {
      //   ConectStatus = false;
      // });
      print('EXAMPLE::OnDisconnected callback is solicited, this is correct');
    } else {
      print(
          'EXAMPLE::OnDisconnected callback is unsolicited or none, this is incorrect - exiting');
      exit(-1);
    }
  }

  void PubMEssage(String message) {
    setState(() {
      fetchingdata = false;
    });
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    /// Publish it
    print('EXAMPLE::Publishing our topic');
    client.publishMessage('${topic}S', MqttQos.exactlyOnce, builder.payload!);
  }

  /// The successful connect callback
  void onConnected() {
    client.subscribe('${topic}P', MqttQos.atLeastOnce);
    PubMEssage("*GET1#");
    print(
        'EXAMPLE::OnConnected client callback - Client connection was successful');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Color(0xFF4682B4)),
        backgroundColor: Colors.white,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Image.asset(
                "image/logo3.png",
                width: 160,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                'GSM M2M v1.2',
                style: TextStyle(color: Color(0xFF4682B4), fontSize: 14),
              ),
            ),
          ],
        ),
      ),
      drawer: Drawer(
        child: showCmd
            ? customCmd()
            : ListView(
                children: <Widget>[
                  const DrawerHeader(
                    decoration: BoxDecoration(
                      color: Color(0xFF4682B4),
                    ),
                    child: BackButton(),
                  ),
                  ListTile(
                    title: Text("Command"),
                    leading: Icon(Icons.comment),
                    onTap: () {
                      setState(() {
                        showCmd = true;
                      });
                    },
                  ),
                ],
              ),
      ),
      body: SafeArea(
        child: (showActivateDialog)
            ? Center(
                child: showerrorDialog ? alertbox() : _buildTextComposer(),
              )
            : FutureBuilder(
                future: permissionStatusFuture,
                builder: (context, snapshot) {
                  // if we are waiting for data, show a progress indicator
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return CircularProgressIndicator();
                  }

                  if (snapshot.hasError) {
                    return Text(
                        'error while retrieving status: ${snapshot.error}');
                  }

                  if (snapshot.hasData) {
                    var textWidget = Text(
                      "The permission status is ${snapshot.data}",
                      style: TextStyle(fontSize: 20),
                      softWrap: true,
                      textAlign: TextAlign.center,
                    );
                    // The permission is granted, then just show the text
                    if (snapshot.data == permGranted) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(),
                          Expanded(
                            // ignore: prefer_const_constructors
                            child: fetchingdata
                                ? Table(
                                    border: TableBorder.all(
                                      color: const Color(0xFF4682B4),
                                      width: 2,
                                    ),
                                    children: [
                                      const TableRow(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(10.0),
                                            child: Text(
                                              'PARAMETERS',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(10.0),
                                            child: Text(
                                              'VALUE',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      for (var data in resultArray)
                                        TableRow(
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.all(10.0),
                                              child: Text(data['key']!),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.all(10.0),
                                              child: Text(data['value']!),
                                            ),
                                          ],
                                        ),
                                    ],
                                  )
                                : const Center(
                                    child: CupertinoActivityIndicator(),
                                  ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    primary: Color(0xFF4682B4)),
                                onPressed: () {
                                  PubMEssage("*ON1#");
                                },
                                child: const Text("ON").p12(),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    primary: Color(0xFF4682B4)),
                                onPressed: () {
                                  PubMEssage('*OFF1#');
                                },
                                child: const Text("OFF").p12(),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    primary: Color(0xFF4682B4)),
                                onPressed: () {
                                  PubMEssage("*GET1#");
                                },
                                child: const Text("GET").p12(),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    primary: Color(0xFF4682B4)),
                                onPressed: () {
                                  PubMEssage("*GSC1#");
                                },
                                child: const Text("GSC").p12(),
                              ),
                            ],
                          )
                        ],
                      );
                    }

                    // else, we'll show a button to ask for the permissions
                    return AlertDialog(
                      title: const Text("Permision"),
                      content: const Text(
                          "Turn On the Notification Permision in Settings."),
                      actions: [
                        TextButton(
                          onPressed: () {
                            // show the dialog/open settings screen
                            NotificationPermissions
                                    .requestNotificationPermissions(
                                        iosSettings:
                                            const NotificationSettingsIos(
                                                sound: true,
                                                badge: true,
                                                alert: true))
                                .then((_) {
                              // when finished, check the permission status
                              setState(() {
                                permissionStatusFuture =
                                    getCheckNotificationPermStatus();
                              });
                            });
                          },
                          child: Text('OK'),
                        ),
                      ],
                    );
                  }
                  return Container();
                },
              ),
      ).p12(),
    );
  }

  Widget _buildTextComposer() {
    var textcolor = false;
    return AlertDialog(
      title: const Text('Authentication'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration.collapsed(
          hintText: "Enter Your Activation Code",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (controller.text.length <= 14) {
              setState(() {
                showerrorDialog = true;
              });
            } else {
              savetopic();

              setState(() {
                Mtopic.changeTopic(controller.text);
                topic = controller.text;
                showActivateDialog = false;
                conectingMqt();
              });
            }
          },
          child: const Text('SUBMIT'),
        ),
      ],
    );
  }

  Widget alertbox() {
    return AlertDialog(
      title: const Text('Invalid Digits '),
      content: Text('Input Proper 15 Digits Activation Code'),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              showerrorDialog = false;
            });
          },
          child: const Text('Ok'),
        ),
      ],
    );
  }

  Widget customCmd() {
    return AlertDialog(
      title: const Text('Command'),
      content: TextField(
        controller: controller2,
        decoration: const InputDecoration.collapsed(
          hintText: "Enter Command",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              showCmd = false;
            });
          },
          child: const Text('Cancle'),
        ),
        ElevatedButton(
          onPressed: () {
            if (controller2.text.length <= 3) {
              setState(() {
                showCmd = false;
              });
            } else {
              setState(() {
                showCmd = false;
                PubMEssage(controller2.text);
              });
            }
          },
          child: const Text('Send'),
        ),
      ],
    );
  }
}
