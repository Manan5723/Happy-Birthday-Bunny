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

bool initstatus = false;
// ignore: non_constant_identifier_names
bool BackgroundState = false;
final clientactive = ClientActivation();

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
    importance: Importance.high, // importance must be at low or higher level
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
      initialNotificationContent: 'Welcome',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

void ClientIDActivate(String ClientID) {
  pubTopic = '${ClientID}S';
  topic = '${ClientID}P';
}

@pragma('vm:entry-point')
onStart(ServiceInstance service) async {
  _bgmq();
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
    _showNotification('Connection Error - $e');
    client.disconnect();
  } on SocketException catch (e) {
    // Raised by the socket layer
    _showNotification('Socket Exception - $e');
    client.disconnect();
  }

  /// Check we are connected
  if (client.connectionStatus!.state == MqttConnectionState.connected) {
    _showNotification('Conected....');
  } else {
    /// Use status here rather than state if you also want the broker return code.
    _showNotification('Connection Failed... ${client.connectionStatus}');
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
        _showNotification('Disconnected from device')
      };

  client.subscribe(topic, MqttQos.atLeastOnce);
  client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
    final recMess = c![0].payload as MqttPublishMessage;
    final pt =
        MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    _showNotification(pt);
  });
}

Future<void> _showNotification(String message) async {
  flutterLocalNotificationsPlugin.show(
    0,
    'DEVICE ALERT',
    message,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        '0',
        'MY FOREGROUND SERVICE',
        icon: 'ic_bg_service_small',
        ongoing: false,
        priority: Priority.high,
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
  Future<String>? permissionStatusFuture;
  final TextEditingController controller = TextEditingController();
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
          Timer.periodic(Duration(seconds: 5), (timer) {
            Connectivity().onConnectivityChanged.listen((event) {
              if (event != ConnectivityResult.none) {
                conectingMqt();
                _bgmq();
              }
            });
          }),
          _showNotification('Disconnected from device'),
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
        _showNotification(pt);
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
    client.publishMessage(pubTopic, MqttQos.exactlyOnce, builder.payload!);
  }

  /// The successful connect callback
  void onConnected() {
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
            Image.asset(
              'image/logo3.png',
              width: 160,
            ),
            const Text(
              'GSM M2M',
              style: TextStyle(color: Color(0xFF4682B4), fontSize: 18),
            )
          ],
        ),
      ),
      drawer: Drawer(
        child: ListView(
          children: const <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: Color(0xFF4682B4),
              ),
              child: BackButton(),
            ),
            ListTile(
              title: Text("Settings"),
              leading: Icon(Icons.settings),
            ),
            ListTile(
              title: Text("Command"),
              leading: Icon(Icons.comment),
            ),
            ListTile(
              title: Text("Timer"),
              leading: Icon(Icons.lock_clock),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: (pubTopic == '')
            ? Center(
                child: _buildTextComposer(),
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
                                ? DataTable(
                                    border: TableBorder.all(
                                        color: const Color(0xFF4682B4)),
                                    columns: const [
                                      DataColumn(label: Text('Device Data')),
                                      DataColumn(label: Text('Status')),
                                    ],
                                    rows: resultArray.map((data) {
                                      return DataRow(cells: [
                                        DataCell(Text(data['key']!)),
                                        DataCell(Text(data['value']!)),
                                      ]);
                                    }).toList(),
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
    return AlertDialog(
      title: const Text('Activate Device'),
      content: TextField(
        controller: controller,
        decoration:
            const InputDecoration.collapsed(hintText: "Enter Activation Code"),
      ),
      actions: [
        TextButton(
            onPressed: () {
              setState(() {
                ClientIDActivate(controller.text);
                conectingMqt();
              });
            },
            child: const Text('Activate'))
      ],
    );
    // return Row(
    //   children: [
    //     Expanded(
    //       child: TextField(
    //         controller: controller,
    //         decoration:
    //             const InputDecoration.collapsed(hintText: "Ask AnyThing"),
    //       ),
    //     ),
    //     IconButton(
    //         onPressed: () => {conectingMqt()}, icon: const Icon(Icons.send))
    //   ],
    // ).px16();
  }
}
