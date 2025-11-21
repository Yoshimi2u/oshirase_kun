import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/schedule_template.dart';
import '../repositories/schedule_template_repository.dart';
import 'group_provider.dart';

/// ScheduleTemplateRepository のプロバイダー
final scheduleTemplateRepositoryProvider = Provider<ScheduleTemplateRepository>((ref) {
  return ScheduleTemplateRepository();
});

/// 現在のユーザーIDのプロバイダー
final currentUserIdProvider = Provider<String?>((ref) {
  return FirebaseAuth.instance.currentUser?.uid;
});

/// テンプレート一覧のストリームプロバイダー（自分のテンプレート + 所属グループのテンプレート）
final templatesStreamProvider = StreamProvider.autoDispose<List<ScheduleTemplate>>((ref) {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    if (kDebugMode) {
      print('⚠️ userId is null in templatesStreamProvider');
    }
    return Stream.value([]);
  }

  if (kDebugMode) {
    print('🔍 templatesStreamProvider: userId = $userId');
  }

  try {
    final repository = ref.watch(scheduleTemplateRepositoryProvider);

    // 自分のテンプレートストリーム
    final myTemplatesStream = repository.watchTemplatesByUserId(userId);

    // グループテンプレートストリームを取得するため、グループ一覧を監視
    return ref.watch(userGroupsStreamProvider).when(
      data: (groups) {
        if (kDebugMode) {
          print('👥 User groups loaded: ${groups.length} groups');
        }
        if (groups.isEmpty) {
          // グループがない場合は自分のテンプレートのみ
          return myTemplatesStream;
        }

        // グループテンプレートのストリームを作成
        final groupTemplatesStreams = groups.map((group) {
          if (kDebugMode) {
            print('📂 Adding group template stream for: ${group.name} (${group.id})');
          }
          return repository.watchGroupTemplates(group.id);
        }).toList();

        // 自分のテンプレートとグループテンプレートを結合
        return myTemplatesStream.asyncMap((myTemplates) async {
          if (kDebugMode) {
            print('✅ My templates loaded: ${myTemplates.length}');
          }
          final allTemplates = <ScheduleTemplate>[...myTemplates];

          // 各グループテンプレートを取得
          for (final groupStream in groupTemplatesStreams) {
            try {
              final groupTemplates = await groupStream.first;
              if (kDebugMode) {
                print('✅ Group templates loaded: ${groupTemplates.length}');
              }
              allTemplates.addAll(groupTemplates);
            } catch (e) {
              // エラーが発生しても続行（他のグループテンプレートは取得）
              if (kDebugMode) {
                print('❌ Error loading group templates: $e');
              }
              continue;
            }
          }

          // 重複を削除（同じIDのテンプレート）
          final uniqueTemplates = <String, ScheduleTemplate>{};
          for (final template in allTemplates) {
            uniqueTemplates[template.id] = template;
          }

          // createdAtでソート（降順）
          final sortedTemplates = uniqueTemplates.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (kDebugMode) {
            print('📊 Total unique templates: ${sortedTemplates.length}');
          }
          return sortedTemplates;
        });
      },
      loading: () {
        if (kDebugMode) {
          print('⏳ Groups loading...');
        }
        return myTemplatesStream;
      },
      error: (error, stack) {
        if (kDebugMode) {
          print('❌ Error loading groups: $error');
        }
        return myTemplatesStream;
      },
    );
  } catch (e) {
    if (kDebugMode) {
      print('❌ Error in templatesStreamProvider: $e');
    }
    return Stream.value([]);
  }
});

/// アクティブなテンプレート一覧のストリームプロバイダー
final activeTemplatesStreamProvider = StreamProvider.autoDispose<List<ScheduleTemplate>>((ref) {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return Stream.value([]);
  } else {
    try {
      final repository = ref.watch(scheduleTemplateRepositoryProvider);
      return repository.watchTemplatesByUserId(userId);
    } catch (e) {
      return Stream.value([]);
    }
  }
});

/// グループテンプレート一覧のストリームプロバイダー
final groupTemplatesStreamProvider = StreamProvider.autoDispose.family<List<ScheduleTemplate>, String>((ref, groupId) {
  try {
    final repository = ref.watch(scheduleTemplateRepositoryProvider);
    return repository.watchGroupTemplates(groupId);
  } catch (e) {
    return Stream.value([]);
  }
});
