import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/schedule_template.dart';
import '../models/group_role.dart';
import '../constants/app_messages.dart';

/// スケジュールテンプレート（繰り返し設定の親要素）のCRUD操作を管理するリポジトリクラス
class ScheduleTemplateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'schedule_templates';

  /// コレクション参照を取得
  CollectionReference get _collection => _firestore.collection(_collectionName);

  /// テンプレートを作成
  Future<String> createTemplate(ScheduleTemplate template) async {
    try {
      // グループテンプレートの場合は全メンバーに作成
      if (template.isGroupSchedule && template.groupId != null) {
        return await _createGroupTemplate(template);
      }

      // 個人テンプレートの作成
      final docRef = _collection.doc();
      final templateWithId = template.copyWith(id: docRef.id);
      await docRef.set(templateWithId.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('テンプレートの作成に失敗しました: $e');
    }
  }

  /// グループテンプレートを作成（全メンバーに作成）
  Future<String> _createGroupTemplate(ScheduleTemplate template) async {
    // グループ情報を取得
    final groupDoc = await _firestore.collection('groups').doc(template.groupId).get();
    if (!groupDoc.exists) {
      throw Exception('グループが見つかりません');
    }

    // IDを生成してテンプレートを作成
    final templateId = _collection.doc().id;
    final templateWithId = template.copyWith(id: templateId);

    // グループテンプレートは1つのドキュメントとして作成（全メンバー共有）
    await _collection.doc(templateId).set(templateWithId.toFirestore());

    return templateId;
  }

  /// 権限チェック付きテンプレート作成
  Future<String> createTemplateWithPermission(ScheduleTemplate template, String userId) async {
    try {
      // グループテンプレートの場合は権限チェック
      if (template.isGroupSchedule && template.groupId != null) {
        final groupDoc = await _firestore.collection('groups').doc(template.groupId).get();

        if (!groupDoc.exists) {
          throw Exception(AppMessages.errorGroupNotFound);
        }

        final memberRoles = groupDoc.data()?['memberRoles'] as Map<String, dynamic>?;
        final roleString = memberRoles?[userId] as String?;

        if (roleString == null) {
          throw Exception(AppMessages.errorNotGroupMember);
        }

        final role = GroupRoleExtension.fromFirestore(roleString);
        if (!GroupPermission.canCreateTemplate(role)) {
          throw Exception(AppMessages.errorNoCreateTemplatePermission);
        }
      } else {
        // 個人テンプレートの場合はuserIdをチェック
        if (template.userId != userId) {
          throw Exception(AppMessages.errorOnlyOwnSchedule);
        }
      }

      return await createTemplate(template);
    } catch (e) {
      rethrow;
    }
  }

  /// テンプレートを更新
  Future<void> updateTemplate(ScheduleTemplate template) async {
    try {
      // updatedAtを現在時刻に更新
      final updatedTemplate = template.copyWith(updatedAt: DateTime.now());

      // グループテンプレートの場合は全メンバーのテンプレートを更新
      if (updatedTemplate.isGroupSchedule && updatedTemplate.groupId != null) {
        await _updateGroupTemplate(updatedTemplate);
        return;
      }

      // 個人テンプレートの更新
      await _collection.doc(updatedTemplate.id).set(
            updatedTemplate.toFirestore(),
            SetOptions(merge: true),
          );
    } catch (e) {
      throw Exception('テンプレートの更新に失敗しました: $e');
    }
  }

  /// グループテンプレートを更新（全メンバーのテンプレートを更新）
  Future<void> _updateGroupTemplate(ScheduleTemplate template) async {
    // グループ情報を取得
    final groupDoc = await _firestore.collection('groups').doc(template.groupId).get();
    if (!groupDoc.exists) {
      throw Exception('グループが見つかりません');
    }

    // グループテンプレートは1つのドキュメントとして更新（全メンバー共有）
    await _collection.doc(template.id).set(
          template.toFirestore(),
          SetOptions(merge: true),
        );
  }

  /// 権限チェック付きテンプレート更新
  Future<void> updateTemplateWithPermission(ScheduleTemplate template, String userId) async {
    try {
      // グループテンプレートの場合は権限チェック
      if (template.isGroupSchedule && template.groupId != null) {
        final groupDoc = await _firestore.collection('groups').doc(template.groupId).get();

        if (!groupDoc.exists) {
          throw Exception(AppMessages.errorGroupNotFound);
        }

        final memberRoles = groupDoc.data()?['memberRoles'] as Map<String, dynamic>?;
        final roleString = memberRoles?[userId] as String?;

        if (roleString == null) {
          throw Exception(AppMessages.errorNotGroupMember);
        }

        final role = GroupRoleExtension.fromFirestore(roleString);
        if (!GroupPermission.canUpdateTemplate(role)) {
          throw Exception(AppMessages.errorNoUpdateTemplatePermission);
        }
      } else {
        // 個人テンプレートの場合はuserIdをチェック
        if (template.userId != userId) {
          throw Exception(AppMessages.errorOnlyOwnSchedule);
        }
      }

      await updateTemplate(template);
    } catch (e) {
      rethrow;
    }
  }

  /// テンプレートを削除（論理削除: isActiveをfalseに設定）
  Future<void> deleteTemplate(String templateId) async {
    try {
      await _collection.doc(templateId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('テンプレートの削除に失敗しました: $e');
    }
  }

  /// テンプレートを物理削除
  Future<void> permanentlyDeleteTemplate(String templateId) async {
    try {
      await _collection.doc(templateId).delete();
    } catch (e) {
      throw Exception('テンプレートの削除に失敗しました: $e');
    }
  }

  /// テンプレートを取得
  Future<ScheduleTemplate?> getTemplate(String templateId) async {
    try {
      if (kDebugMode) {
        print('🔍 Getting template: $templateId');
        print('📂 Collection: $_collectionName');
        print('🔗 Full path: ${_collection.path}/$templateId');
      }

      final doc = await _collection.doc(templateId).get();

      if (kDebugMode) {
        print('📄 Document exists: ${doc.exists}');
        if (doc.exists) {
          print('📋 Document data: ${doc.data()}');
        }
      }

      if (!doc.exists) {
        if (kDebugMode) {
          print('⚠️ Template not found: $templateId');
        }
        return null;
      }
      final template = ScheduleTemplate.fromFirestore(doc);
      if (kDebugMode) {
        print(
            '✅ Template loaded: ${template.title}, isGroupSchedule: ${template.isGroupSchedule}, groupId: ${template.groupId}');
      }
      return template;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting template: $e');
      }
      throw Exception('テンプレートの取得に失敗しました: $e');
    }
  }

  /// ユーザーのテンプレート一覧を取得
  Future<List<ScheduleTemplate>> getTemplatesByUserId(String userId) async {
    try {
      final querySnapshot = await _collection
          .where('userId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) => ScheduleTemplate.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('テンプレート一覧の取得に失敗しました: $e');
    }
  }

  /// アクティブなテンプレート一覧を取得
  Future<List<ScheduleTemplate>> getActiveTemplates(String userId) async {
    try {
      final querySnapshot = await _collection
          .where('userId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) => ScheduleTemplate.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('アクティブなテンプレートの取得に失敗しました: $e');
    }
  }

  /// グループのテンプレート一覧を取得
  Future<List<ScheduleTemplate>> getGroupTemplates(String groupId) async {
    try {
      final querySnapshot = await _collection
          .where('groupId', isEqualTo: groupId)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) => ScheduleTemplate.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('グループテンプレートの取得に失敗しました: $e');
    }
  }

  /// テンプレートをリアルタイムで監視
  Stream<List<ScheduleTemplate>> watchTemplatesByUserId(String userId) {
    if (kDebugMode) {
      print('🔍 Watching templates for userId: $userId');
    }
    return _collection
        .where('userId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      if (kDebugMode) {
        print('📋 Found ${snapshot.docs.length} templates for user');
      }
      return snapshot.docs.map((doc) => ScheduleTemplate.fromFirestore(doc)).toList();
    });
  }

  /// グループテンプレートをリアルタイムで監視
  Stream<List<ScheduleTemplate>> watchGroupTemplates(String groupId) {
    if (kDebugMode) {
      print('🔍 Watching templates for groupId: $groupId');
    }
    return _collection
        .where('groupId', isEqualTo: groupId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      if (kDebugMode) {
        print('📋 Found ${snapshot.docs.length} templates for group');
      }
      return snapshot.docs.map((doc) => ScheduleTemplate.fromFirestore(doc)).toList();
    }).handleError((error) {
      if (kDebugMode) {
        print('❌ Error watching group templates: $error');
      }
      throw error;
    });
  }
}
