import 'package:flutter_riverpod/flutter_riverpod.dart';

class ClientActivation extends StateNotifier<String> {
  String? pubTopic;
  String? subTopic;

  ClientActivation() : super('');

  void setActivation(String msg) {
    pubTopic = '${msg}P';
    subTopic = '${msg}S';
    state = '$pubTopic,$subTopic';
  }
}
