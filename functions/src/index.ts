import {setGlobalOptions} from "firebase-functions";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
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

    // 通知メッセージを作成（時間帯によってタイトルと本文を変更）
    let title = "本日のタスクのお知らせ";
    let body = "";

    // 時間帯の判定
    const isMorning = hour >= 5 && hour < 12;
    const isAfternoon = hour >= 12 && hour < 18;
    const isEvening = hour >= 18 && hour < 23;

    // タイトルの設定
    if (isMorning) {
      title = "おはようございます！";
    } else if (isAfternoon) {
      title = "お疲れ様です！";
    } else if (isEvening) {
      title = "今日もお疲れ様でした！";
    }

    // 本文の設定（時間帯別）
    if (todayCount === 0 && overdueCount === 0) {
      if (isMorning) {
        body = "今日のタスクはありません！良い一日を！";
      } else if (isAfternoon) {
        body = "今日のタスクはありません！引き続き良い一日を！";
      } else if (isEvening) {
        body = "今日のタスクはありません！ゆっくり休んでください！";
      } else {
        body = "今日のタスクはありません！";
      }
    } else if (todayCount > 0 && overdueCount === 0) {
      if (isMorning) {
        body = `今日はタスクが${todayCount}件あります！\n今日も一日頑張りましょう！`;
      } else if (isAfternoon) {
        body = `今日はタスクが${todayCount}件あります！\n引き続き頑張りましょう！`;
      } else if (isEvening) {
        body = `今日はタスクが${todayCount}件あります！\n残りも頑張りましょう！`;
      } else {
        body = `今日はタスクが${todayCount}件あります！`;
      }
    } else if (todayCount === 0 && overdueCount > 0) {
      if (isMorning) {
        body = `今日は遅延のタスクが${overdueCount}件あります！\n早めに確認しましょう！`;
      } else if (isAfternoon) {
        body = `今日は遅延のタスクが${overdueCount}件あります！\n時間があれば確認してみてください！`;
      } else if (isEvening) {
        body = `今日は遅延のタスクが${overdueCount}件あります！\n明日の予定に含めましょう！`;
      } else {
        body = `今日は遅延のタスクが${overdueCount}件あります！`;
      }
    } else {
      if (isMorning) {
        body = `今日はタスクが${todayCount}件\n` +
          `遅延のタスクが${overdueCount}件あります。\n` +
          "計画的に進めましょう！";
      } else if (isAfternoon) {
        body = `今日はタスクが${todayCount}件\n` +
          `遅延のタスクが${overdueCount}件あります。\n` +
          "できるところから進めましょう！";
      } else if (isEvening) {
        body = `今日はタスクが${todayCount}件\n` +
          `遅延のタスクが${overdueCount}件あります。\n` +
          "無理せず進めましょう！";
      } else {
        body = `今日はタスクが${todayCount}件\n` +
          `遅延のタスクが${overdueCount}件あります。`;
      }
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
 * 月次タスク自動生成（Plan Aに移行したため無効化）
 * 旧実装: 毎月1日0時（日本時間）に翌月分のタスクを生成
 * 新実装: アプリ起動時にgenerateUserTasks/generateGroupTasksを呼び出し
 */
// export const generateMonthlyTasks = onSchedule(
//   {
//     schedule: "0 0 1 * *", // 毎月1日0時（JST）
//     timeZone: "Asia/Tokyo",
//   },
//   async () => {
//     logger.info("[月次タスク生成] 処理開始");
//     // ... 処理内容は削除 ...
//   }
// );

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
  case RepeatType.NONE:
    // 繰り返しなしの場合は非常に未来の日付を返す（ループ終了）
    return new Date(9999, 11, 31);

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

/**
 * ユーザーの個人タスクを生成するCallable関数
 * アプリ起動時にクライアントから呼び出される
 */
export const generateUserTasks = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "認証が必要です");
    }

    logger.info(`[個人タスク生成] userId: ${userId}, 14日先まで生成`);

    const db = admin.firestore();

    try {
      // 個人テンプレートを取得（グループタスク除外、繰り返し設定あり）
      const templatesSnapshot = await db
        .collection("schedule_templates")
        .where("userId", "==", userId)
        .where("isActive", "==", true)
        .where("isGroupSchedule", "==", false)
        .get();

      if (templatesSnapshot.empty) {
        logger.info(`[個人タスク生成] テンプレートなし userId: ${userId}`);
        return {success: true, tasksCreated: 0, message: "テンプレートなし"};
      }

      // 繰り返し設定のないテンプレートを除外
      const validTemplates = templatesSnapshot.docs.filter((doc) => {
        const template = doc.data() as ScheduleTemplateData;

        // repeatTypeが未定義またはNONEの場合は除外
        if (!template.repeatType || template.repeatType === RepeatType.NONE) {
          logger.info(
            `[個人タスク生成] 除外（繰り返しなし）: template=${doc.id}, ` +
            `repeatType=${template.repeatType}`
          );
          return false;
        }
        return true;
      });

      if (validTemplates.length === 0) {
        logger.info(
          `[個人タスク生成] 有効なテンプレートなし userId: ${userId}`
        );
        return {
          success: true,
          tasksCreated: 0,
          message: "繰り返し設定のあるテンプレートなし",
        };
      }

      let totalTasksCreated = 0;

      // 14日先までの期間を取得
      const {startDate, endDate} = getGenerationRange();

      logger.info(
        "[個人タスク生成] 生成期間: " +
        `${startDate.toISOString()} - ${endDate.toISOString()}`
      );

      // 各テンプレートについて処理
      for (const templateDoc of validTemplates) {
        const template = templateDoc.data() as ScheduleTemplateData;

        // CUSTOM の場合は常にスキップ（Dart側で完了時に生成）
        if (template.repeatType === RepeatType.CUSTOM) {
          logger.info(
            `[個人タスク生成] スキップ（完了後管理）: template=${templateDoc.id}`
          );
          continue;
        }

        logger.info(
          "[個人タスク生成] テンプレート処理開始: " +
          `id=${templateDoc.id}, title=${template.title}, ` +
          `repeatType=${template.repeatType}, ` +
          `weekdays=${JSON.stringify(template.selectedWeekdays)}`
        );

        // 既存タスクの日付を取得（期間内のすべて）
        const existingTaskSnapshot = await db
          .collection("tasks")
          .where("userId", "==", userId)
          .where("templateId", "==", templateDoc.id)
          .where(
            "scheduledDate",
            ">=",
            admin.firestore.Timestamp.fromDate(startDate)
          )
          .where(
            "scheduledDate",
            "<=",
            admin.firestore.Timestamp.fromDate(endDate)
          )
          .get();

        // 既存タスクの日付セット作成(isDeleted含む=再生成防止)
        const existingDates = new Set<string>();
        existingTaskSnapshot.docs.forEach((doc) => {
          const taskData = doc.data();
          // 論理削除タスクも含める(削除済み日付への再生成を防止)
          const sd = taskData.scheduledDate as admin.firestore.Timestamp;
          const scheduledDate = sd.toDate();
          const year = scheduledDate.getFullYear();
          const month = (scheduledDate.getMonth() + 1)
            .toString().padStart(2, "0");
          const day = scheduledDate.getDate().toString().padStart(2, "0");
          const dateKey = `${year}-${month}-${day}`;
          existingDates.add(dateKey);
        });

        if (existingDates.size > 0) {
          logger.info(
            "[個人タスク生成] 既存タスク検出: " +
            `template=${templateDoc.id}, count=${existingDates.size}`
          );
        }

        // カスタム繰り返しの場合のみ、最後のタスク日を取得
        let lastTaskDate: Date | null = null;
        if (template.repeatType === RepeatType.CUSTOM) {
          const lastTaskSnapshot = await db
            .collection("tasks")
            .where("userId", "==", userId)
            .where("templateId", "==", templateDoc.id)
            .orderBy("scheduledDate", "desc")
            .limit(1)
            .get();

          lastTaskDate = !lastTaskSnapshot.empty ?
            (lastTaskSnapshot.docs[0].data()
              .scheduledDate as admin.firestore.Timestamp).toDate() :
            null;

          const lastTaskDateStr = lastTaskDate ?
            lastTaskDate.toISOString() : "なし";
          logger.info(
            "[個人タスク生成] カスタム繰り返し最終タスク日: " +
            `template=${templateDoc.id}, lastTaskDate=${lastTaskDateStr}`
          );
        }

        // この期間のタスク日付リストを生成
        const taskDates = generateTaskDatesForMonth(
          template,
          startDate,
          endDate,
          lastTaskDate
        );

        // 日ごとに重複チェックしてタスクを作成
        let createdCount = 0;
        for (const taskDate of taskDates) {
          const year = taskDate.getFullYear();
          const month = (taskDate.getMonth() + 1)
            .toString().padStart(2, "0");
          const day = taskDate.getDate().toString().padStart(2, "0");
          const dateKey = `${year}-${month}-${day}`;

          // この日付が既に存在する場合はスキップ
          if (existingDates.has(dateKey)) {
            continue;
          }

          await db.collection("tasks").add({
            userId: userId,
            templateId: templateDoc.id,
            title: template.title,
            description: template.description,
            scheduledDate: admin.firestore.Timestamp.fromDate(taskDate),
            completedAt: null,
            completedByMemberId: null,
            groupId: null,
            isGroupSchedule: false,
            isDeleted: false,
            repeatType: template.repeatType,
            weekdays: template.selectedWeekdays || null,
            repeatInterval: template.repeatInterval || null,
            monthlyDay: template.monthlyDay || null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          createdCount++;
          totalTasksCreated++;
        }

        logger.info(
          "[個人タスク生成] 完了: " +
          `template=${templateDoc.id}, ` +
          `created=${createdCount}/${taskDates.length}`
        );
      }

      logger.info(
        `[個人タスク生成] 完了 userId: ${userId}, ` +
        `作成数: ${totalTasksCreated}`
      );
      return {
        success: true,
        tasksCreated: totalTasksCreated,
        message: `${totalTasksCreated}件のタスクを生成しました`,
      };
    } catch (error) {
      logger.error(`[個人タスク生成] エラー userId: ${userId}`, error);
      throw new HttpsError("internal", "タスク生成に失敗しました");
    }
  }
);

/**
 * 14日先までの範囲を取得
 * @return {Object} 今日から14日後までの開始日と終了日
 */
function getGenerationRange(): {startDate: Date; endDate: Date} {
  const today = new Date();
  const year = today.getFullYear();
  const month = today.getMonth();
  const day = today.getDate();

  const startDate = new Date(year, month, day);
  const endDate = new Date(year, month, day + 14);

  return {startDate, endDate};
}

/**
 * 指定期間内のタスク日付リストを生成
 * @param {ScheduleTemplateData} template - テンプレート
 * @param {Date} startDate - 開始日
 * @param {Date} endDate - 終了日
 * @param {Date | null} lastTaskDate - 最後のタスク日（ない場合はnull）
 * @return {Date[]} タスク日付リスト
 */
function generateTaskDatesForMonth(
  template: ScheduleTemplateData,
  startDate: Date,
  endDate: Date,
  lastTaskDate: Date | null = null
): Date[] {
  const dates: Date[] = [];

  // 日本時間（JST）の今日の0時を取得
  const now = new Date();
  const jstOffset = 9 * 60 * 60 * 1000; // 9時間をミリ秒に変換
  const jstNow = new Date(now.getTime() + jstOffset);
  const today = new Date(
    jstNow.getUTCFullYear(),
    jstNow.getUTCMonth(),
    jstNow.getUTCDate()
  );

  // 最後のタスク日がある場合はそこから、ない場合は期間開始の前日から
  const baseDate = lastTaskDate ?
    new Date(lastTaskDate) :
    new Date(startDate.getTime() - 86400000);

  let currentDate = calculateNextTaskDate(template, baseDate);

  while (currentDate <= endDate) {
    // 今日以降かつ期間内の場合のみ追加
    if (currentDate >= startDate && currentDate >= today) {
      dates.push(new Date(currentDate));
    }

    // 次のタスク日を計算（現在のタスク日を基準に）
    currentDate = calculateNextTaskDate(template, currentDate);

    // 無限ループ防止
    if (dates.length > 100) {
      break;
    }
  }

  return dates;
}

/**
 * 特定のテンプレートIDに対してタスクを生成するCallable関数
 * 予定の追加・更新時にクライアントから呼び出される
 */
export const generateTasksForTemplate = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "認証が必要です");
    }

    const {templateId} = request.data as {
      templateId: string;
    };

    if (!templateId) {
      throw new HttpsError("invalid-argument", "templateIdが必要です");
    }

    logger.info(
      `[テンプレートタスク生成] templateId: ${templateId}, 14日先まで生成`
    );

    const db = admin.firestore();

    try {
      // テンプレートを取得
      const templateDoc = await db
        .collection("schedule_templates")
        .doc(templateId)
        .get();

      if (!templateDoc.exists) {
        throw new HttpsError("not-found", "テンプレートが見つかりません");
      }

      const template = templateDoc.data() as ScheduleTemplateData;

      // 権限チェック：個人予定の場合はuserIdが一致、グループ予定の場合はメンバー確認
      if (template.isGroupSchedule) {
        if (!template.groupId) {
          throw new HttpsError(
            "invalid-argument",
            "グループ予定にgroupIdがありません"
          );
        }

        const groupDoc = await db
          .collection("groups")
          .doc(template.groupId)
          .get();

        if (!groupDoc.exists) {
          throw new HttpsError("not-found", "グループが見つかりません");
        }

        const groupData = groupDoc.data();
        // memberIdsまたはmemberRolesからメンバーをチェック
        const memberIds = groupData?.memberIds as
          string[] | undefined;
        const memberRoles = groupData?.memberRoles as
          Record<string, string> | undefined;

        const isMember = memberIds?.includes(userId) ||
                        (memberRoles && userId in memberRoles);

        if (!isMember) {
          throw new HttpsError(
            "permission-denied",
            "このグループのメンバーではありません"
          );
        }
      } else {
        // 個人予定の場合はuserIdをチェック
        if (template.userId !== userId) {
          throw new HttpsError(
            "permission-denied",
            "この予定にアクセスする権限がありません"
          );
        }
      }

      // 繰り返し設定がない場合は何もしない
      if (!template.repeatType || template.repeatType === RepeatType.NONE) {
        logger.info(
          `[テンプレートタスク生成] 繰り返しなし templateId: ${templateId}`
        );
        return {
          success: true,
          tasksCreated: 0,
          message: "繰り返し設定がありません",
        };
      }

      // テンプレートが無効な場合は何もしない
      if (!template.isActive) {
        logger.info(
          `[テンプレートタスク生成] 無効なテンプレート templateId: ${templateId}`
        );
        return {
          success: true,
          tasksCreated: 0,
          message: "無効なテンプレートです",
        };
      }

      let totalTasksCreated = 0;

      // 14日先までの期間を取得
      const {startDate, endDate} = getGenerationRange();

      logger.info(
        "[テンプレートタスク生成] 生成期間: " +
        `${startDate.toISOString()} - ${endDate.toISOString()}`
      );

      // CUSTOM の場合、初回タスクが存在すればスキップ
      if (template.repeatType === RepeatType.CUSTOM) {
        const query = template.isGroupSchedule ?
          db
            .collection("tasks")
            .where("groupId", "==", template.groupId)
            .where("templateId", "==", templateId) :
          db
            .collection("tasks")
            .where("userId", "==", userId)
            .where("templateId", "==", templateId);

        const hasAnyTask = await query.limit(1).get();

        if (!hasAnyTask.empty) {
          logger.info(
            `[テンプレートタスク生成] スキップ（完了後管理）: template=${templateId}`
          );
          return {
            success: true,
            tasksCreated: 0,
            message: "完了後に次のタスクが生成されます",
          };
        }
      }

      // 既存タスクの日付を取得（期間内のすべて）
      const existingTaskQuery = template.isGroupSchedule ?
        db
          .collection("tasks")
          .where("groupId", "==", template.groupId)
          .where("templateId", "==", templateId) :
        db
          .collection("tasks")
          .where("userId", "==", userId)
          .where("templateId", "==", templateId);

      const existingTaskSnapshot = await existingTaskQuery
        .where(
          "scheduledDate",
          ">=",
          admin.firestore.Timestamp.fromDate(startDate)
        )
        .where(
          "scheduledDate",
          "<=",
          admin.firestore.Timestamp.fromDate(endDate)
        )
        .get();

      // 既存タスクの日付セット作成(isDeleted含む=再生成防止)
      const existingDates = new Set<string>();
      existingTaskSnapshot.docs.forEach((doc) => {
        const taskData = doc.data();
        // 論理削除タスクも含める(削除済み日付への再生成を防止)
        const sd = taskData.scheduledDate as admin.firestore.Timestamp;
        const scheduledDate = sd.toDate();
        const year = scheduledDate.getFullYear();
        const month = (scheduledDate.getMonth() + 1)
          .toString().padStart(2, "0");
        const day = scheduledDate.getDate().toString().padStart(2, "0");
        const dateKey = `${year}-${month}-${day}`;
        existingDates.add(dateKey);
      });

      if (existingDates.size > 0) {
        logger.info(
          "[テンプレートタスク生成] 既存タスク検出: " +
          `template=${templateId}, count=${existingDates.size}`
        );
      }

      // カスタム繰り返しの場合のみ、最後のタスク日を取得
      let lastTaskDate: Date | null = null;
      if (template.repeatType === RepeatType.CUSTOM) {
        const lastTaskQuery = template.isGroupSchedule ?
          db
            .collection("tasks")
            .where("groupId", "==", template.groupId)
            .where("templateId", "==", templateId) :
          db
            .collection("tasks")
            .where("userId", "==", userId)
            .where("templateId", "==", templateId);

        const lastTaskSnapshot = await lastTaskQuery
          .orderBy("scheduledDate", "desc")
          .limit(1)
          .get();

        lastTaskDate = !lastTaskSnapshot.empty ?
          (lastTaskSnapshot.docs[0].data()
            .scheduledDate as admin.firestore.Timestamp).toDate() :
          null;

        const lastTaskDateStr = lastTaskDate ?
          lastTaskDate.toISOString() : "なし";
        logger.info(
          "[テンプレートタスク生成] カスタム繰り返し最終タスク日: " +
          `template=${templateId}, lastTaskDate=${lastTaskDateStr}`
        );
      }

      // この期間のタスク日付リストを生成
      const taskDates = generateTaskDatesForMonth(
        template,
        startDate,
        endDate,
        lastTaskDate
      );

      // 日ごとに重複チェックしてタスクを作成
      for (const taskDate of taskDates) {
        const year = taskDate.getFullYear();
        const month = (taskDate.getMonth() + 1)
          .toString().padStart(2, "0");
        const day = taskDate.getDate().toString().padStart(2, "0");
        const dateKey = `${year}-${month}-${day}`;

        // この日付が既に存在する場合はスキップ
        if (existingDates.has(dateKey)) {
          continue;
        }

        interface TaskData {
          templateId: string;
          title: string;
          description: string;
          scheduledDate: admin.firestore.Timestamp;
          completedAt: admin.firestore.Timestamp | null;
          completedByMemberId: string | null;
          isDeleted: boolean;
          repeatType: string;
          weekdays: number[] | null;
          repeatInterval: number | null;
          monthlyDay: number | null;
          createdAt: admin.firestore.FieldValue;
          updatedAt: admin.firestore.FieldValue;
          userId: string | null;
          groupId: string | null;
          isGroupSchedule: boolean;
        }

        const taskData: TaskData = {
          templateId: templateId,
          title: template.title,
          description: template.description,
          scheduledDate: admin.firestore.Timestamp.fromDate(taskDate),
          completedAt: null,
          completedByMemberId: null,
          isDeleted: false,
          repeatType: template.repeatType,
          weekdays: template.selectedWeekdays || null,
          repeatInterval: template.repeatInterval || null,
          monthlyDay: template.monthlyDay || null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          userId: null,
          groupId: null,
          isGroupSchedule: false,
        };

        if (template.isGroupSchedule) {
          taskData.userId = null;
          taskData.groupId = template.groupId || null;
          taskData.isGroupSchedule = true;
        } else {
          taskData.userId = userId;
          taskData.groupId = null;
          taskData.isGroupSchedule = false;
        }

        await db.collection("tasks").add(taskData);
        totalTasksCreated++;
      }

      logger.info(
        `[テンプレートタスク生成] 完了 templateId: ${templateId}, ` +
        `作成数: ${totalTasksCreated}`
      );
      return {
        success: true,
        tasksCreated: totalTasksCreated,
        message: `${totalTasksCreated}件のタスクを生成しました`,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error(
        `[テンプレートタスク生成] エラー templateId: ${templateId}`,
        error
      );
      throw new HttpsError("internal", "タスク生成に失敗しました");
    }
  }
);

/**
 * グループタスクを生成するCallable関数
 * アプリ起動時にクライアントから呼び出される
 */
export const generateGroupTasks = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "認証が必要です");
    }

    const {groupId} = request.data as {
      groupId: string;
    };

    if (!groupId) {
      throw new HttpsError("invalid-argument", "groupIdが必要です");
    }

    logger.info(
      `[グループタスク生成] groupId: ${groupId}, 14日先まで生成`
    );

    const db = admin.firestore();

    try {
      // グループの存在確認とメンバーシップ確認
      const groupDoc = await db.collection("groups").doc(groupId).get();
      if (!groupDoc.exists) {
        throw new HttpsError("not-found", "グループが見つかりません");
      }

      const groupData = groupDoc.data();
      // memberIdsまたはmemberRolesからメンバーをチェック
      const memberIds = groupData?.memberIds as
        string[] | undefined;
      const memberRoles = groupData?.memberRoles as
        Record<string, string> | undefined;

      const isMember = memberIds?.includes(userId) ||
                      (memberRoles && userId in memberRoles);

      if (!isMember) {
        throw new HttpsError(
          "permission-denied",
          "このグループのメンバーではありません"
        );
      }

      // グループテンプレートを取得
      const templatesSnapshot = await db
        .collection("schedule_templates")
        .where("groupId", "==", groupId)
        .where("isActive", "==", true)
        .where("isGroupSchedule", "==", true)
        .get();

      if (templatesSnapshot.empty) {
        logger.info(
          `[グループタスク生成] テンプレートなし groupId: ${groupId}`
        );
        return {success: true, tasksCreated: 0, message: "テンプレートなし"};
      }

      // 繰り返し設定のないテンプレートを除外
      const validTemplates = templatesSnapshot.docs.filter((doc) => {
        const template = doc.data() as ScheduleTemplateData;

        // repeatTypeが未定義またはNONEの場合は除外
        if (!template.repeatType || template.repeatType === RepeatType.NONE) {
          logger.info(
            `[グループタスク生成] 除外（繰り返しなし）: template=${doc.id}, ` +
            `repeatType=${template.repeatType}`
          );
          return false;
        }
        return true;
      });

      if (validTemplates.length === 0) {
        logger.info(
          `[グループタスク生成] 有効なテンプレートなし groupId: ${groupId}`
        );
        return {
          success: true,
          tasksCreated: 0,
          message: "繰り返し設定のあるテンプレートなし",
        };
      }

      let totalTasksCreated = 0;

      // 14日先までの期間を取得
      const {startDate, endDate} = getGenerationRange();

      logger.info(
        "[グループタスク生成] 生成期間: " +
        `${startDate.toISOString()} - ${endDate.toISOString()}`
      );

      // 各テンプレートについて処理
      for (const templateDoc of validTemplates) {
        const template = templateDoc.data() as ScheduleTemplateData;

        // CUSTOM の場合は常にスキップ（Dart側で完了時に生成）
        if (template.repeatType === RepeatType.CUSTOM) {
          logger.info(
            `[グループタスク生成] スキップ（完了後管理）: template=${templateDoc.id}`
          );
          continue;
        }

        logger.info(
          "[グループタスク生成] テンプレート処理開始: " +
          `id=${templateDoc.id}, title=${template.title}, ` +
          `repeatType=${template.repeatType}, ` +
          `weekdays=${JSON.stringify(template.selectedWeekdays)}`
        );

        // 既存タスクの日付を取得（期間内のすべて）
        const existingTaskSnapshot = await db
          .collection("tasks")
          .where("groupId", "==", groupId)
          .where("templateId", "==", templateDoc.id)
          .where(
            "scheduledDate",
            ">=",
            admin.firestore.Timestamp.fromDate(startDate)
          )
          .where(
            "scheduledDate",
            "<=",
            admin.firestore.Timestamp.fromDate(endDate)
          )
          .get();

        // 既存タスクの日付セット作成(isDeleted含む=再生成防止)
        const existingDates = new Set<string>();
        existingTaskSnapshot.docs.forEach((doc) => {
          const taskData = doc.data();
          // 論理削除タスクも含める(削除済み日付への再生成を防止)
          const sd = taskData.scheduledDate as admin.firestore.Timestamp;
          const scheduledDate = sd.toDate();
          const year = scheduledDate.getFullYear();
          const month = (scheduledDate.getMonth() + 1)
            .toString().padStart(2, "0");
          const day = scheduledDate.getDate().toString().padStart(2, "0");
          const dateKey = `${year}-${month}-${day}`;
          existingDates.add(dateKey);
        });

        if (existingDates.size > 0) {
          logger.info(
            "[グループタスク生成] 既存タスク検出: " +
            `template=${templateDoc.id}, count=${existingDates.size}`
          );
        }
        // カスタム繰り返しの場合のみ、最後のタスク日を取得
        let lastTaskDate: Date | null = null;
        if (template.repeatType === RepeatType.CUSTOM) {
          const lastTaskSnapshot = await db
            .collection("tasks")
            .where("groupId", "==", groupId)
            .where("templateId", "==", templateDoc.id)
            .orderBy("scheduledDate", "desc")
            .limit(1)
            .get();

          lastTaskDate = !lastTaskSnapshot.empty ?
            (lastTaskSnapshot.docs[0].data()
              .scheduledDate as admin.firestore.Timestamp).toDate() :
            null;

          const lastTaskDateStr = lastTaskDate ?
            lastTaskDate.toISOString() : "なし";
          logger.info(
            "[グループタスク生成] カスタム繰り返し最終タスク日: " +
              `template=${templateDoc.id}, lastTaskDate=${lastTaskDateStr}`
          );
        }

        // この月のタスク日付リストを生成
        const taskDates = generateTaskDatesForMonth(
          template,
          startDate,
          endDate,
          lastTaskDate
        );

        // 日ごとに重複チェックしてタスクを作成
        let createdCount = 0;
        for (const taskDate of taskDates) {
          const year = taskDate.getFullYear();
          const month = (taskDate.getMonth() + 1)
            .toString().padStart(2, "0");
          const day = taskDate.getDate().toString().padStart(2, "0");
          const dateKey = `${year}-${month}-${day}`;

          // この日付が既に存在する場合はスキップ
          if (existingDates.has(dateKey)) {
            continue;
          }

          // グループタスクを作成(userIdはnull)
          await db.collection("tasks").add({
            userId: null, // グループタスクはuserIdをnullに
            templateId: templateDoc.id,
            title: template.title,
            description: template.description,
            scheduledDate: admin.firestore.Timestamp.fromDate(taskDate),
            completedAt: null,
            completedByMemberId: null,
            groupId: groupId,
            isGroupSchedule: true,
            isDeleted: false,
            repeatType: template.repeatType,
            weekdays: template.selectedWeekdays || null,
            repeatInterval: template.repeatInterval || null,
            monthlyDay: template.monthlyDay || null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          createdCount++;
          totalTasksCreated++;
        }

        logger.info(
          "[グループタスク生成] 完了: " +
          `template=${templateDoc.id}, ` +
          `created=${createdCount}/${taskDates.length}`
        );
      }

      logger.info(
        `[グループタスク生成] 完了 groupId: ${groupId}, 作成数: ${totalTasksCreated}`
      );
      return {
        success: true,
        tasksCreated: totalTasksCreated,
        message: `${totalTasksCreated}件のタスクを生成しました`,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error(`[グループタスク生成] エラー groupId: ${groupId}`, error);
      throw new HttpsError("internal", "タスク生成に失敗しました");
    }
  }
);

