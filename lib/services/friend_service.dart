import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/friend_connection.dart';

class FriendService {
  FriendService({this.gymId = '', FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String gymId;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('friendships');

  Future<void> sendRequest({
    required String requesterId,
    required String receiverId,
  }) {
    final docId = FriendConnection.docId(requesterId, receiverId);
    final connection = FriendConnection(
      id: docId,
      requesterId: requesterId,
      receiverId: receiverId,
      gymId: gymId,
      status: 'pending',
      createdAt: DateTime.now(),
    );
    return _col.doc(docId).set(connection.toJson());
  }

  Future<void> acceptRequest(String docId) =>
      _col.doc(docId).update({'status': 'accepted'});

  Future<void> declineRequest(String docId) => _col.doc(docId).delete();

  Future<void> removeFriend(String myUid, String friendUid) =>
      _col.doc(FriendConnection.docId(myUid, friendUid)).delete();

  /// Stream the connection doc between two users (null if none).
  Stream<FriendConnection?> streamConnection(String uidA, String uidB) {
    return _col
        .doc(FriendConnection.docId(uidA, uidB))
        .snapshots()
        .map((s) => s.exists ? FriendConnection.fromSnapshot(s) : null);
  }

  /// Stream all accepted friends of [userId].
  Stream<List<FriendConnection>> streamFriends(String userId) {
    final asRequester = _col
        .where('requesterId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((s) => s.docs.map(FriendConnection.fromSnapshot).toList());

    final asReceiver = _col
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((s) => s.docs.map(FriendConnection.fromSnapshot).toList());

    return _combinedStream(asRequester, asReceiver);
  }

  /// Stream pending requests where [userId] is the receiver (inbox).
  Stream<List<FriendConnection>> streamPendingRequests(String userId) {
    return _col
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.map(FriendConnection.fromSnapshot).toList());
  }

  /// Returns the set of accepted friend UIDs for [userId].
  Stream<Set<String>> streamFriendIds(String userId) {
    return streamFriends(userId).map(
      (connections) => connections.map((c) => c.friendId(userId)).toSet(),
    );
  }

  /// Combines two list streams, emitting whenever either fires, deduplicating
  /// by doc ID. The returned stream is broadcast so multiple listeners are safe.
  Stream<List<FriendConnection>> _combinedStream(
    Stream<List<FriendConnection>> a,
    Stream<List<FriendConnection>> b,
  ) {
    final controller =
        StreamController<List<FriendConnection>>.broadcast();
    List<FriendConnection> lastA = [];
    List<FriendConnection> lastB = [];

    void emit() {
      final seen = <String>{};
      final merged = <FriendConnection>[];
      for (final c in [...lastA, ...lastB]) {
        if (seen.add(c.id)) merged.add(c);
      }
      if (!controller.isClosed) controller.add(merged);
    }

    StreamSubscription<List<FriendConnection>>? subA;
    StreamSubscription<List<FriendConnection>>? subB;

    controller.onListen = () {
      subA = a.listen((list) {
        lastA = list;
        emit();
      }, onError: controller.addError);
      subB = b.listen((list) {
        lastB = list;
        emit();
      }, onError: controller.addError);
    };
    controller.onCancel = () {
      subA?.cancel();
      subB?.cancel();
    };

    return controller.stream;
  }
}
