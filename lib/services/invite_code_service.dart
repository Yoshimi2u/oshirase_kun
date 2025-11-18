import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 招待コード生成サービス
class InviteCodeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 6桁の招待コードを生成
  /// 紛らわしい文字（O, 0, I, 1, l など）を除外
  String generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// ユニークな招待コードを生成（重複チェック付き）
  Future<String> generateUniqueInviteCode() async {
    int maxAttempts = 10;

    for (int i = 0; i < maxAttempts; i++) {
      final code = generateInviteCode();
      final exists = await _checkCodeExists(code);

      if (!exists) {
        return code;
      }
    }

    // 10回試してもユニークなコードが生成できなかった場合
    throw Exception('招待コードの生成に失敗しました。もう一度お試しください。');
  }

  /// 招待コードが既に存在するかチェック
  Future<bool> _checkCodeExists(String code) async {
    try {
      final querySnapshot = await _firestore.collection('groups').where('inviteCode', isEqualTo: code).limit(1).get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      // エラーが発生した場合は false を返す（コードは使用可能と判断）
      print('招待コード重複チェックエラー: $e');
      return false;
    }
  }

  /// 招待コードからグループを検索
  Future<DocumentSnapshot?> findGroupByInviteCode(String code) async {
    try {
      final querySnapshot =
          await _firestore.collection('groups').where('inviteCode', isEqualTo: code.toUpperCase()).limit(1).get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return querySnapshot.docs.first;
    } catch (e) {
      throw Exception('グループの検索に失敗しました: $e');
    }
  }

  /// 招待コードのフォーマット検証
  bool isValidInviteCode(String code) {
    // 6文字で、許可された文字のみで構成されているかチェック
    if (code.length != 6) {
      return false;
    }

    final validChars = RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]+$');
    return validChars.hasMatch(code.toUpperCase());
  }
}
