import {setGlobalOptions} from "firebase-functions";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

admin.initializeApp();

setGlobalOptions({maxInstances: 10, region: "asia-northeast1"});

/**
 * 繰り返しタイプの列挙型（Dartと同期）
 */
enum RepeatType {
  NONE = "none",
  DAILY = "daily",
  WEEKLY = "weekly",
  MONTHLY = "monthly",
  CUSTOM = "custom",
}

/**
 * スケジュールの型定義
 */
interface ScheduleData {
  id: string;
  repeatType: RepeatType;
  repeatInterval?: number;
  nextScheduledDate: admin.firestore.Timestamp;
  lastCompletedDate?: admin.firestore.Timestamp;
  startDate?: admin.firestore.Timestamp;
  requiresCompletion: boolean;
  status?: string;
}

/**
 * 次回予定日を計算（Dartのロジックと同期）
 * @param {ScheduleData} schedule - スケジュールデータ
 * @return {Date | null} 次回予定日
 */
function calculateNextScheduledDate(schedule: ScheduleData): Date | null {
  // 基準日: 元のnextScheduledDateを使用（完了不要タスクなので）
  const baseDate = schedule.nextScheduledDate.toDate();

  switch (schedule.repeatType) {
  case RepeatType.NONE:
    return null;

  case RepeatType.DAILY:
    return new Date(
      baseDate.getFullYear(),
      baseDate.getMonth(),
      baseDate.getDate() + 1
    );

  case RepeatType.WEEKLY:
    return new Date(
      baseDate.getFullYear(),
      baseDate.getMonth(),
      baseDate.getDate() + 7
    );

  case RepeatType.MONTHLY:
    return new Date(
      baseDate.getFullYear(),
      baseDate.getMonth() + 1,
      baseDate.getDate()
    );

  case RepeatType.CUSTOM:
    if (!schedule.repeatInterval || schedule.repeatInterval <= 0) {
      return null;
    }
    return new Date(
      baseDate.getFullYear(),
      baseDate.getMonth(),
      baseDate.getDate() + schedule.repeatInterval
    );

  default:
    return null;
  }
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

    // 今日のタスクを取得
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    // 今日のタスクを取得（範囲クエリのみ使用）
    const todaySchedulesSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("schedules")
      .where(
        "nextScheduledDate",
        ">=",
        admin.firestore.Timestamp.fromDate(today)
      )
      .where(
        "nextScheduledDate",
        "<",
        admin.firestore.Timestamp.fromDate(tomorrow)
      )
      .get();

    // クライアント側でrequiresCompletionをフィルタリング
    const todayCount = todaySchedulesSnapshot.docs.filter(
      (doc) => doc.data().requiresCompletion === true
    ).length;

    // 遅延タスクを取得（過去の未完了タスク）
    const overdueSchedulesSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("schedules")
      .where(
        "nextScheduledDate",
        "<",
        admin.firestore.Timestamp.fromDate(today)
      )
      .get();

    // クライアント側でrequiresCompletionをフィルタリング
    const overdueCount = overdueSchedulesSnapshot.docs.filter(
      (doc) => doc.data().requiresCompletion === true
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
 * グループタスク完了時の通知
 * グループメンバーがタスクを完了した時、他のメンバーに通知
 */
export const notifyGroupTaskCompletion = onDocumentUpdated(
  {
    document: "users/{userId}/schedules/{scheduleId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    // データが存在しない場合は処理しない
    if (!beforeData || !afterData) {
      return;
    }

    // グループタスクでない場合は処理しない
    if (!afterData.isGroupSchedule || !afterData.groupId) {
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

    // このトリガーが完了者本人のドキュメント更新でない場合はスキップ
    // （バッチ更新で全メンバーのドキュメントが更新されるが、通知は1回だけ）
    if (event.params.userId !== completedByMemberId) {
      return;
    }

    const groupId = afterData.groupId;
    const scheduleTitle = afterData.title || "タスク";

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
        `グループタスク完了通知: ${groupName} - ${scheduleTitle} by ${completedByUserName}`
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
                body: `${completedByUserName}さんが「${scheduleTitle}」を完了しました`,
              },
              data: {
                type: "group_task_completion",
                groupId: groupId,
                scheduleId: event.params.scheduleId,
                completedByMemberId: completedByMemberId,
                completedByUserName: completedByUserName,
                scheduleTitle: scheduleTitle,
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
              `[${memberId}] グループタスク完了通知送信成功: ${scheduleTitle}`
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
 * 完了不要の繰り返しタスクの予定日を自動更新
 * 毎日0時（日本時間）に実行
 */
export const updateNonRequiredSchedules = onSchedule(
  {
    schedule: "0 0 * * *", // 毎日0時（JST）
    timeZone: "Asia/Tokyo",
  },
  async () => {
    logger.info("[完了不要タスク更新] 処理開始");

    const db = admin.firestore();
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    try {
      // 完了不要 & 予定日が過去 & 繰り返しあり
      const schedulesSnapshot = await db
        .collectionGroup("schedules")
        .where("requiresCompletion", "==", false)
        .where(
          "nextScheduledDate",
          "<",
          admin.firestore.Timestamp.fromDate(today)
        )
        .get();

      logger.info(`[完了不要タスク更新] 対象: ${schedulesSnapshot.size}件`);

      if (schedulesSnapshot.empty) {
        logger.info("[完了不要タスク更新] 更新対象なし");
        return;
      }

      // バッチ処理（500件ごと）
      const batches: admin.firestore.WriteBatch[] = [];
      let currentBatch = db.batch();
      let operationCount = 0;
      let updatedCount = 0;

      for (const doc of schedulesSnapshot.docs) {
        const data = doc.data() as ScheduleData;

        // 完了済みは除外
        if (data.status === "completed") {
          continue;
        }

        // 繰り返しがない場合は除外
        if (data.repeatType === RepeatType.NONE) {
          continue;
        }

        // 次回予定日を計算
        const nextDate = calculateNextScheduledDate(data);

        if (!nextDate) {
          logger.warn(`[${doc.id}] 次回予定日の計算失敗`);
          continue;
        }

        // バッチに追加
        currentBatch.update(doc.ref, {
          nextScheduledDate: admin.firestore.Timestamp.fromDate(nextDate),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        operationCount++;
        updatedCount++;

        // 500件ごとにバッチをコミット
        if (operationCount >= 500) {
          batches.push(currentBatch);
          currentBatch = db.batch();
          operationCount = 0;
        }
      }

      // 残りのバッチを追加
      if (operationCount > 0) {
        batches.push(currentBatch);
      }

      // 全バッチをコミット
      await Promise.all(batches.map((batch) => batch.commit()));

      logger.info(`[完了不要タスク更新] 完了: ${updatedCount}件更新`);
    } catch (error) {
      logger.error("[完了不要タスク更新] エラー:", error);
      throw error;
    }
  }
);
