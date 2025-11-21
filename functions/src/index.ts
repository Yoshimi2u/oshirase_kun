import {setGlobalOptions} from "firebase-functions";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

admin.initializeApp();

setGlobalOptions({maxInstances: 10, region: "asia-northeast1"});

/**
 * タスクの型定義（新モデル）
 */
interface TaskData {
  id: string;
  userId: string;
  templateId?: string;
  title: string;
  description: string;
  scheduledDate: admin.firestore.Timestamp;
  completedAt?: admin.firestore.Timestamp;
  isGroupTask: boolean;
  groupId?: string;
  completedByMemberId?: string;
  groupCompletedAt?: admin.firestore.Timestamp;
}

/**
 * スケジュールテンプレートの型定義
 */
interface ScheduleTemplateData {
  id: string;
  userId: string;
  title: string;
  description: string;
  repeatType: string;
  repeatInterval?: number;
  selectedWeekdays?: number[];
  monthlyDay?: number;
  requiresCompletion: boolean;
  isActive: boolean;
  isGroupSchedule: boolean;
  groupId?: string;
}

/**
 * 繰り返しタイプの列挙型
 */
enum RepeatType {
  NONE = "none",
  DAILY = "daily",
  CUSTOM_WEEKLY = "customWeekly",
  MONTHLY = "monthly",
  MONTHLY_LAST_DAY = "monthlyLastDay",
  CUSTOM = "custom",
}

/**
 * 1時間ごとに実行される通知関数（0-23時）
 * 各時刻に通知を設定しているユーザーにのみ通知を送信
 */

// 0時から23時まで、1時間ごとに実行される関数を生成
for (let hour = 0; hour < 24; hour++) {
  const paddedHour = hour.toString().padStart(2, "0");
  const functionName = `sendNotificationAt${paddedHour}`;

  // eslint-disable-next-line
  (exports as any)[functionName] = onSchedule(
    {
      schedule: `0 ${hour} * * *`,
      timeZone: "Asia/Tokyo",
    },
    async () => {
      logger.info(`[${paddedHour}:00] 通知処理開始`);
      await sendNotificationForHour(hour);
      logger.info(`[${paddedHour}:00] 通知処理完了`);
    }
  );
}

/**
 * 指定された時刻に通知を送信する共通関数
 * 最適化: whereクエリで該当ユーザーのみ取得
 * @param {number} hour - 通知を送信する時刻（0-23）
 * @return {Promise<void>}
 */
async function sendNotificationForHour(hour: number): Promise<void> {
  const db = admin.firestore();
  const messaging = admin.messaging();

  try {
    // 朝の通知が有効で、この時刻に設定しているユーザーを取得
    const morningUsersPromise = db
      .collection("users")
      .where("morningEnabled", "==", true)
      .where("morningHour", "==", hour)
      .get();

    // 夜の通知が有効で、この時刻に設定しているユーザーを取得
    const eveningUsersPromise = db
      .collection("users")
      .where("eveningEnabled", "==", true)
      .where("eveningHour", "==", hour)
      .get();

    // 並列で取得
    const [morningUsersSnapshot, eveningUsersSnapshot] = await Promise.all([
      morningUsersPromise,
      eveningUsersPromise,
    ]);

    // 重複を排除してユーザーIDのセットを作成
    const userIds = new Set<string>();
    morningUsersSnapshot.docs.forEach((doc) => userIds.add(doc.id));
    eveningUsersSnapshot.docs.forEach((doc) => userIds.add(doc.id));

    logger.info(`${hour}時: ${userIds.size}人のユーザーに通知送信`);

    if (userIds.size === 0) {
      return;
    }

    // 各ユーザーに通知を送信
    const promises = Array.from(userIds).map((userId) =>
      sendNotificationToUser(userId, hour, db, messaging)
    );
    await Promise.all(promises);
  } catch (error) {
    logger.error(`${hour}時の通知処理エラー:`, error);
    throw error;
  }
}

/**
 * 個別のユーザーに通知を送信
 * @param {string} userId - ユーザーID
 * @param {number} hour - 通知時刻
 * @param {admin.firestore.Firestore} db - Firestoreインスタンス
 * @param {admin.messaging.Messaging} messaging - FCMインスタンス
 * @return {Promise<void>}
 */
async function sendNotificationToUser(
  userId: string,
  hour: number,
  db: admin.firestore.Firestore,
  messaging: admin.messaging.Messaging
): Promise<void> {
  try {
    // ユーザーのFCMトークンを取得
    const userDoc = await db.collection("users").doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken;

    if (!fcmToken) {
      logger.warn(`[${userId}] FCMトークンが見つかりません`);
      return;
    }

    // 今日のタスクを取得（新モデル: tasks コレクション）
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    // 今日のタスクを取得（未完了のみ）
    const todayTasksSnapshot = await db
      .collection("tasks")
      .where("userId", "==", userId)
      .where(
        "scheduledDate",
        ">=",
        admin.firestore.Timestamp.fromDate(today)
      )
      .where(
        "scheduledDate",
        "<",
        admin.firestore.Timestamp.fromDate(tomorrow)
      )
      .get();

    // 未完了タスクのみカウント
    const todayCount = todayTasksSnapshot.docs.filter(
      (doc) => !doc.data().completedAt
    ).length;

    // 遅延タスクを取得（過去の未完了タスク）
    const overdueTasksSnapshot = await db
      .collection("tasks")
      .where("userId", "==", userId)
      .where(
        "scheduledDate",
        "<",
        admin.firestore.Timestamp.fromDate(today)
      )
      .get();

    // 未完了タスクのみカウント
    const overdueCount = overdueTasksSnapshot.docs.filter(
      (doc) => !doc.data().completedAt
    ).length;

    // 通知メッセージを作成
    const title = "タスクのお知らせ";
    let body = "";

    if (todayCount === 0 && overdueCount === 0) {
      body = "今日のタスクはありません";
    } else if (todayCount > 0 && overdueCount === 0) {
      body = `今日は${todayCount}件のタスクがあります`;
    } else if (todayCount === 0 && overdueCount > 0) {
      body = `遅延: ${overdueCount}件`;
    } else {
      body = `今日は${todayCount}件のタスクがあります。遅延: ${overdueCount}件`;
    }

    // FCM通知を送信
    await messaging.send({
      token: fcmToken,
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: "scheduled_notification",
        hour: hour.toString(),
        todayCount: todayCount.toString(),
        overdueCount: overdueCount.toString(),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "default_channel",
          priority: "high",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: todayCount + overdueCount,
          },
        },
      },
    });

    logger.info(`[${userId}] 通知送信成功: ${body}`);
  } catch (error) {
    const errorCode = (error as {code?: string}).code;
    const errorMessage = (error as {message?: string}).message;

    // 無効なトークンの場合は削除
    if (
      errorCode === "messaging/invalid-registration-token" ||
      errorCode === "messaging/registration-token-not-registered"
    ) {
      logger.warn(`[${userId}] 無効なFCMトークンを削除`);
      await db.collection("users").doc(userId).update({
        fcmToken: admin.firestore.FieldValue.delete(),
      });
    } else if (
      // APNS認証エラーの場合
      errorCode === "messaging/third-party-auth-error" ||
      errorMessage?.includes("Auth error from APNS")
    ) {
      logger.error(
        `[${userId}] APNS認証エラー。Firebase ConsoleでAPNS証明書を確認してください`,
        {errorCode, errorMessage}
      );
      // APNS認証エラーの場合もトークンを削除（再登録を促す）
      await db.collection("users").doc(userId).update({
        fcmToken: admin.firestore.FieldValue.delete(),
      });
    } else {
      // その他のエラー
      logger.error(
        `[${userId}] 通知送信エラー`,
        {errorCode, errorMessage, error}
      );
    }
  }
}

/**
 * グループタスク完了時の通知（新モデル対応）
 * グループメンバーがタスクを完了した時、他のメンバーに通知
 */
export const notifyGroupTaskCompletion = onDocumentUpdated(
  {
    document: "tasks/{taskId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const beforeData = event.data?.before.data() as TaskData | undefined;
    const afterData = event.data?.after.data() as TaskData | undefined;

    // データが存在しない場合は処理しない
    if (!beforeData || !afterData) {
      return;
    }

    // グループタスクでない場合は処理しない
    if (!afterData.isGroupTask || !afterData.groupId) {
      return;
    }

    // 完了状態が変更されていない場合は処理しない
    const wasCompleted = beforeData.groupCompletedAt != null;
    const isNowCompleted = afterData.groupCompletedAt != null;

    if (wasCompleted || !isNowCompleted) {
      return;
    }

    // 完了したメンバーIDを取得
    const completedByMemberId = afterData.completedByMemberId;
    if (!completedByMemberId) {
      return;
    }

    const groupId = afterData.groupId;
    const taskTitle = afterData.title || "タスク";

    try {
      const db = admin.firestore();
      const messaging = admin.messaging();

      // グループ情報を取得
      const groupDoc = await db.collection("groups").doc(groupId).get();
      if (!groupDoc.exists) {
        logger.warn(`グループが見つかりません: ${groupId}`);
        return;
      }

      const groupData = groupDoc.data();
      const groupName = groupData?.name || "グループ";
      const memberIds = groupData?.memberIds || [];

      // 完了したメンバーの情報を取得
      const completedByUserDoc = await db
        .collection("users")
        .doc(completedByMemberId)
        .get();
      const completedByUserName =
        completedByUserDoc.data()?.displayName || "メンバー";

      // 完了したメンバー以外に通知
      const otherMemberIds = memberIds.filter(
        (id: string) => id !== completedByMemberId
      );

      logger.info(
        // eslint-disable-next-line max-len
        `グループタスク完了通知: ${groupName} - ${taskTitle} by ${completedByUserName}`
      );

      // 各メンバーに通知を送信
      const notificationPromises = otherMemberIds.map(
        async (memberId: string) => {
          try {
            // メンバーのFCMトークンを取得
            const memberDoc = await db.collection("users").doc(memberId).get();
            const fcmToken = memberDoc.data()?.fcmToken;

            if (!fcmToken) {
              logger.warn(`[${memberId}] FCMトークンが見つかりません`);
              return;
            }

            // 通知を送信
            await messaging.send({
              token: fcmToken,
              notification: {
                title: `${groupName} - タスク完了`,
                body: `${completedByUserName}さんが「${taskTitle}」を完了しました`,
              },
              data: {
                type: "group_task_completion",
                groupId: groupId,
                taskId: event.params.taskId,
                completedByMemberId: completedByMemberId,
                completedByUserName: completedByUserName,
                taskTitle: taskTitle,
              },
              android: {
                priority: "high",
                notification: {
                  channelId: "group_notification_channel",
                  priority: "high",
                },
              },
              apns: {
                payload: {
                  aps: {
                    sound: "default",
                  },
                },
              },
            });

            logger.info(
              `[${memberId}] グループタスク完了通知送信成功: ${taskTitle}`
            );
          } catch (error) {
            const errorCode = (error as {code?: string}).code;
            const errorMessage = (error as {message?: string}).message;

            // 無効なトークンの場合は削除
            if (
              errorCode === "messaging/invalid-registration-token" ||
              errorCode === "messaging/registration-token-not-registered"
            ) {
              logger.warn(`[${memberId}] 無効なFCMトークンを削除`);
              await db.collection("users").doc(memberId).update({
                fcmToken: admin.firestore.FieldValue.delete(),
              });
            } else if (
              // APNS認証エラーの場合
              errorCode === "messaging/third-party-auth-error" ||
              errorMessage?.includes("Auth error from APNS")
            ) {
              logger.error(
                `[${memberId}] APNS認証エラー。Firebase ConsoleでAPNS証明書を確認してください`,
                {errorCode, errorMessage}
              );
              // APNS認証エラーの場合もトークンを削除（再登録を促す）
              await db.collection("users").doc(memberId).update({
                fcmToken: admin.firestore.FieldValue.delete(),
              });
            } else {
              // その他のエラー
              logger.error(
                `[${memberId}] 通知送信エラー`,
                {errorCode, errorMessage, error}
              );
            }
          }
        }
      );

      await Promise.all(notificationPromises);
      logger.info(
        `グループタスク完了通知処理完了: ${otherMemberIds.length}人に送信`
      );
    } catch (error) {
      logger.error("グループタスク完了通知エラー:", error);
    }
  }
);

/**
 * 月次タスク自動生成
 * 毎月1日0時（日本時間）に翌月分のタスクを生成
 */
export const generateMonthlyTasks = onSchedule(
  {
    schedule: "0 0 1 * *", // 毎月1日0時（JST）
    timeZone: "Asia/Tokyo",
  },
  async () => {
    logger.info("[月次タスク生成] 処理開始");

    const db = admin.firestore();

    try {
      // アクティブなテンプレートを全て取得
      const templatesSnapshot = await db
        .collection("schedule_templates")
        .where("isActive", "==", true)
        .get();

      logger.info(`[月次タスク生成] 対象テンプレート: ${templatesSnapshot.size}件`);

      if (templatesSnapshot.empty) {
        logger.info("[月次タスク生成] 対象テンプレートなし");
        return;
      }

      let totalTasksCreated = 0;

      // 各テンプレートに対してタスクを生成
      for (const templateDoc of templatesSnapshot.docs) {
        const template = templateDoc.data() as ScheduleTemplateData;

        // カスタム（完了必須あり）は除外（完了時に生成される）
        if (
          template.repeatType === RepeatType.CUSTOM &&
          template.requiresCompletion
        ) {
          continue;
        }

        // 繰り返しなしは除外
        if (template.repeatType === RepeatType.NONE) {
          continue;
        }

        // 翌月分のタスク日付リストを生成
        const taskDates = generateTaskDatesForNextMonth(template);

        // 各日付に対してタスクを作成（重複チェック付き）
        for (const taskDate of taskDates) {
          // 既にタスクが存在するかチェック
          const existingTaskSnapshot = await db
            .collection("tasks")
            .where("userId", "==", template.userId)
            .where("templateId", "==", templateDoc.id)
            .where(
              "scheduledDate",
              "==",
              admin.firestore.Timestamp.fromDate(taskDate)
            )
            .limit(1)
            .get();

          if (!existingTaskSnapshot.empty) {
            // 既に存在する場合はスキップ
            continue;
          }

          // タスクを作成
          await db.collection("tasks").add({
            userId: template.userId,
            templateId: templateDoc.id,
            title: template.title,
            description: template.description,
            scheduledDate: admin.firestore.Timestamp.fromDate(taskDate),
            completedAt: null,
            completedByMemberId: null,
            groupId: template.groupId || null,
            isGroupSchedule: template.isGroupSchedule,
            repeatType: template.repeatType,
            weekdays: template.selectedWeekdays || null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          totalTasksCreated++;
        }
      }

      logger.info(`[月次タスク生成] 完了: ${totalTasksCreated}件のタスクを生成`);
    } catch (error) {
      logger.error("[月次タスク生成] エラー:", error);
      throw error;
    }
  }
);

/**
 * 翌月分のタスク日付リストを生成
 * @param {ScheduleTemplateData} template - テンプレートデータ
 * @return {Date[]} タスク日付リスト
 */
function generateTaskDatesForNextMonth(
  template: ScheduleTemplateData
): Date[] {
  const today = new Date();
  const dates: Date[] = [];

  // 翌月の1日と末日を計算
  const nextMonth = today.getMonth() === 11 ? 0 : today.getMonth() + 1;
  const nextMonthYear =
    today.getMonth() === 11 ? today.getFullYear() + 1 : today.getFullYear();
  const startOfNextMonth = new Date(nextMonthYear, nextMonth, 1);
  const endOfNextMonth = new Date(nextMonthYear, nextMonth + 1, 0);

  // 初回日付を計算（翌月1日を基準）
  let currentDate = calculateNextTaskDate(template, startOfNextMonth);

  // 翌月末まで生成
  while (currentDate <= endOfNextMonth) {
    // 翌月内の日付のみ追加
    if (currentDate >= startOfNextMonth) {
      dates.push(new Date(currentDate));
    }

    // 次の日付を計算
    const prevDate = new Date(currentDate);
    prevDate.setDate(prevDate.getDate() - 1);
    currentDate = calculateNextTaskDate(template, prevDate);

    // 無限ループ防止
    if (dates.length > 100) {
      break;
    }
  }

  return dates;
}

/**
 * 次回のタスク予定日を計算
 * @param {ScheduleTemplateData} template - テンプレートデータ
 * @param {Date} baseDate - 基準日
 * @return {Date} 次回のタスク予定日
 */
function calculateNextTaskDate(
  template: ScheduleTemplateData,
  baseDate: Date
): Date {
  switch (template.repeatType) {
  case RepeatType.DAILY:
    return new Date(
      baseDate.getFullYear(),
      baseDate.getMonth(),
      baseDate.getDate() + 1
    );

  case RepeatType.CUSTOM_WEEKLY: {
    // 曜日指定
    if (!template.selectedWeekdays || template.selectedWeekdays.length === 0) {
      return new Date(
        baseDate.getFullYear(),
        baseDate.getMonth(),
        baseDate.getDate() + 1
      );
    }
    return findNextWeekday(baseDate, template.selectedWeekdays);
  }

  case RepeatType.MONTHLY: {
    // monthlyDayが指定されている場合はその日を使用
    const targetDay = template.monthlyDay ?? baseDate.getDate();
    const day = targetDay > 28 ? 28 : targetDay;

    let nextMonth = baseDate.getMonth() + 1;
    let nextYear = baseDate.getFullYear();
    if (nextMonth > 11) {
      nextMonth = 0;
      nextYear++;
    }

    return new Date(nextYear, nextMonth, day);
  }

  case RepeatType.MONTHLY_LAST_DAY: {
    // 翌月の月末を計算
    let nextMonth = baseDate.getMonth() + 1;
    let nextYear = baseDate.getFullYear();
    if (nextMonth > 11) {
      nextMonth = 0;
      nextYear++;
    }
    
    // 翌月の末日を取得（翌々月の0日 = 翌月の末日）
    return new Date(nextYear, nextMonth + 1, 0);
  }

  case RepeatType.CUSTOM: {
    if (!template.repeatInterval || template.repeatInterval <= 0) {
      return new Date(
        baseDate.getFullYear(),
        baseDate.getMonth(),
        baseDate.getDate() + 1
      );
    }
    return new Date(
      baseDate.getFullYear(),
      baseDate.getMonth(),
      baseDate.getDate() + template.repeatInterval
    );
  }

  default:
    return new Date(
      baseDate.getFullYear(),
      baseDate.getMonth(),
      baseDate.getDate() + 1
    );
  }
}

/**
 * 指定された曜日リストから次回の日付を検索
 * @param {Date} baseDate - 基準日
 * @param {number[]} weekdays - 曜日リスト（1=月曜, 7=日曜）
 * @return {Date} 次回の日付
 */
function findNextWeekday(baseDate: Date, weekdays: number[]): Date {
  const nextDate = new Date(baseDate);
  nextDate.setDate(nextDate.getDate() + 1);

  // 最大14日先まで検索（2週間分）
  for (let i = 0; i < 14; i++) {
    // JavaScriptのweekdayは0=日曜, Dartは1=月曜なので変換
    const jsWeekday = nextDate.getDay() === 0 ? 7 : nextDate.getDay();
    if (weekdays.includes(jsWeekday)) {
      return nextDate;
    }
    nextDate.setDate(nextDate.getDate() + 1);
  }

  // 見つからない場合は翌日を返す（フォールバック）
  const fallback = new Date(baseDate);
  fallback.setDate(fallback.getDate() + 1);
  return fallback;
}
