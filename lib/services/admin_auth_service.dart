import 'package:cloud_functions/cloud_functions.dart';

class AdminAuthService {
  AdminAuthService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<void> setUserPassword({
    required String userId,
    required String newPassword,
  }) async {
    final callable = _functions.httpsCallable('adminSetUserPassword');
    await callable.call(<String, dynamic>{
      'userId': userId,
      'newPassword': newPassword,
    });
  }
}
