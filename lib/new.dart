import 'dart:async';
import 'dart:io';
import 'package:connectivity/connectivity.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'main.dart';

class Mqttcon {
  Future<void> bgmq(String topic) async {
    // Timer.periodic(Duration(seconds: 5), (timer) {
    //   Connectivity().onConnectivityChanged.listen((event) {
    //     if (event != ConnectivityResult.none) {
    //       bgmq(topic);
    //     }
    //   });
    // });

    client.logging(on: true);
    client.setProtocolV311();
    client.keepAlivePeriod = 25;
    client.connectTimeoutPeriod = 2500;
    client.pongCallback = () {
      print('ping');
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
      // showNotification('Connection Error - $e');
      client.disconnect();
    } on SocketException catch (e) {
      // Raised by the socket layer
      // showNotification('Socket Exception - $e');
      client.disconnect();
    }

    /// Check we are connected
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      silentshowNotification('Conected To Device $topic');
    } else {
      /// Use status here rather than state if you also want the broker return code.
      //showNotification(
      //  'Connection Failed kindly check your internet connection try to turn on and off the internet for reconnecting');
      client.disconnect();
      exit(-1);
    }

    client.onDisconnected = () async => {
          Connectivity().onConnectivityChanged.listen((event) {
            if (event != ConnectivityResult.none) {
              bgmq(topic);
            }
          }),
          showNotification('Disconnected from device $topic'),
        };

    client.subscribe("${topic}P", MqttQos.atLeastOnce);
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final recMess = c![0].payload as MqttPublishMessage;
      final pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      showNotification(pt);
    });
  }
}
