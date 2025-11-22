import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// タスク自動生成サービス
/// アプリ起動時に当月・翌月分のタスクを自動生成
class TaskGenerationService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  TaskGenerationService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast1'),
        _auth = auth ?? FirebaseAuth.instance;

  /// アプリ起動時に個人タスクとグループタスクを生成
  Future<void> generateTasksOnAppLaunch(WidgetRef ref) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // 個人タスクの生成
      await _generatePersonalTasks(user.uid, ref);

      // グループタスクの生成
      await _generateGroupTasks(user.uid, ref);
    } catch (e) {
      print('[TaskGeneration] エラー: $e');
      // エラーが発生してもアプリは継続
    }
  }

  /// 個人タスクの生成実行
  Future<void> _generatePersonalTasks(String userId, WidgetRef ref) async {
    try {
      print('[TaskGeneration] === 個人タスク生成開始 ===');
      print('[TaskGeneration] userId: $userId');

      // Cloud Functionsでタスク生成（内部で全テンプレートをチェック・生成）
      print('[TaskGeneration] Cloud Functions呼び出し: generateUserTasks');
      final callable = _functions.httpsCallable('generateUserTasks');
      final result = await callable.call({});

      print('[TaskGeneration] 個人タスク生成完了: ${result.data}');
    } catch (e) {
      print('[TaskGeneration] 個人タスク生成エラー: $e');
    }
  }

  /// グループタスクの生成チェック・実行
  Future<void> _generateGroupTasks(String userId, WidgetRef ref) async {
    try {
      // 1. 所属グループを取得
      final groupIds = await _getUserGroupIds(userId);
      if (groupIds.isEmpty) {
        print('[TaskGeneration] 所属グループなし');
        return;
      }

      // 2. 各グループについてタスク生成
      for (final groupId in groupIds) {
        await _generateGroupTasksForGroup(groupId, ref);
      }
    } catch (e) {
      print('[TaskGeneration] グループタスク生成エラー: $e');
    }
  }

  /// 指定グループのタスク生成
  Future<void> _generateGroupTasksForGroup(String groupId, WidgetRef ref) async {
    try {
      print('[TaskGeneration] グループタスク生成開始: $groupId');

      // Cloud Functionsでタスク生成（内部で全テンプレートをチェック・生成）
      final callable = _functions.httpsCallable('generateGroupTasks');
      final result = await callable.call({
        'groupId': groupId,
      });

      print('[TaskGeneration] グループタスク生成完了: ${result.data}');
    } on FirebaseFunctionsException catch (e) {
      print('[TaskGeneration] グループタスク生成エラー ($groupId)');
      print('  Code: ${e.code}');
      print('  Message: ${e.message}');
      print('  Details: ${e.details}');
      print('  Stack trace: ${e.stackTrace}');
    } catch (e, stackTrace) {
      print('[TaskGeneration] グループタスク生成エラー ($groupId): $e');
      print('  Stack trace: $stackTrace');
    }
  }

  /// ユーザーが所属するグループIDリストを取得
  Future<List<String>> _getUserGroupIds(String userId) async {
    // memberIdsまたはmemberRolesにuserIdが含まれるグループを取得
    final snapshot = await _firestore.collection('groups').where('isActive', isEqualTo: true).get();

    final groupIds = <String>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final memberIds = data['memberIds'] as List<dynamic>?;
      final memberRoles = data['memberRoles'] as Map<String, dynamic>?;

      // memberIdsまたはmemberRolesにuserIdが含まれているかチェック
      if ((memberIds != null && memberIds.contains(userId)) ||
          (memberRoles != null && memberRoles.containsKey(userId))) {
        groupIds.add(doc.id);
      }
    }

    return groupIds;
  }
}

/// TaskGenerationServiceのProvider
final taskGenerationServiceProvider = Provider<TaskGenerationService>((ref) {
  return TaskGenerationService();
});
