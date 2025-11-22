/// アプリ全体で使用するメッセージ定数
class AppMessages {
  // エラーメッセージ
  static const String errorGeneric = 'エラーが発生しました';
  static const String errorNetwork = 'ネットワークエラーが発生しました';
  static const String errorAuth = '認証エラーが発生しました';
  static const String errorPermission = '権限がありません';
  static const String errorNotFound = 'データが見つかりませんでした';
  static const String errorTaskNotSelected = '削除するタスクが選択されていません';

  // 削除関連
  static const String deleteScheduleConfirm = 'この予定を削除しますか?\n（関連するタスクも全て削除されます）';
  static const String deleteSingleTaskConfirm = 'のタスクを削除しますか?';
  static const String deleteSuccess = '予定を削除しました';
  static const String deleteTaskSuccess = 'タスクを削除しました';
  static const String deleteFailed = '削除に失敗しました';
  static const String deleteMethodTitle = '削除方法を選択';
  static const String deleteMethodMessage = 'この予定は繰り返し設定があります。\nどのように削除しますか?';
  static const String confirmationTitle = '確認';

  // ボタンラベル
  static const String buttonCancel = 'キャンセル';
  static const String buttonDelete = '削除';
  static const String buttonSave = '保存';
  static const String buttonAdd = '追加';
  static const String buttonEdit = '編集';
  static const String buttonComplete = '完了';
  static const String buttonThisTaskOnly = 'このタスクのみ';
  static const String buttonFutureAll = '今後のすべて';

  // 編集関連
  static const String editMethodTitle = '編集方法を選択';
  static const String editMethodMessage = 'この予定は繰り返し設定があります。\nどのように編集しますか?';
  static const String editThisTaskOnly = 'このタスクのみ編集';
  static const String editFutureAll = '今後のすべてを編集';

  // 空状態メッセージ
  static const String noTasksToday = '今日のタスクはありません';
  static const String noSchedules = '予定がありません';
  static const String addSchedulePrompt = '予定を追加してください';

  // タスク関連
  static const String taskLoadError = 'タスクの読み込みに失敗しました';
  static const String scheduleNotFound = '予定が見つかりませんでした';

  // バリデーション
  static const String validationSelectWeekday = '曜日を1つ以上選択してください';
  static const String validationUserIdNotFound = 'ユーザーIDが取得できませんでした';

  // 権限エラー
  static const String errorGroupNotFound = 'グループが見つかりません';
  static const String errorNotGroupMember = 'このグループのメンバーではありません';
  static const String errorNoUpdateTaskPermission = 'タスクを更新する権限がありません';
  static const String errorNoDeleteTaskPermission = 'タスクを削除する権限がありません';
  static const String errorNoCreateTemplatePermission = '繰り返しタスクを作成する権限がありません';
  static const String errorNoUpdateTemplatePermission = '繰り返しタスクを更新する権限がありません';
  static const String errorNoDeleteTemplatePermission = '繰り返しタスクを削除する権限がありません';
  static const String errorOnlyOwnTask = '自分のタスクのみ操作できます';
  static const String errorOnlyOwnSchedule = '自分のスケジュールのみ削除できます';
  static const String errorTaskNotFound = 'タスクが見つかりません';

  // タスク操作失敗
  static const String errorTaskUpdateFailed = 'タスクの更新に失敗しました';
  static const String errorTaskDeleteFailed = 'タスクの削除に失敗しました';
  static const String errorTaskCompleteFailed = 'タスクの完了に失敗しました';
  static const String errorTaskUncompleteFailed = 'タスクの完了解除に失敗しました';
  static const String errorTasksDeleteByTemplateFailed = '繰り返しタスクに紐づくタスクの削除に失敗しました';

  // 認証関連
  static const String errorSignInFailed = 'サインインに失敗しました';
  static const String errorRegisterFailed = 'アカウント登録に失敗しました';

  // グループ操作
  static const String errorGroupJoinFailed = 'グループへの参加に失敗しました';
  static const String errorGroupRoleChangeFailed = '役割の変更に失敗しました';
  static const String errorGroupMemberDeleteFailed = 'メンバーの削除に失敗しました';

  // 予定操作
  static const String errorScheduleSaveFailed = '予定の保存に失敗しました';
}
