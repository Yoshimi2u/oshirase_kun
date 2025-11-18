import {setGlobalOptions} from "firebase-functions";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

admin.initializeApp();

setGlobalOptions({maxInstances: 10, region: "asia-northeast1"});

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
 * @param {number} hour - 通知を送信する時刻（0-23）
 * @return {Promise<void>}
 */
async function sendNotificationForHour(hour: number): Promise<void> {
  const db = admin.firestore();
  const messaging = admin.messaging();

  try {
    // 朝の通知を有効にしていて、この時刻を設定しているユーザー
    const morningUsersSnapshot = await db
      .collection("users")
      .where("morningEnabled", "==", true)
      .where("morningHour", "==", hour)
      .get();

    // 夜の通知を有効にしていて、この時刻を設定しているユーザー
    const eveningUsersSnapshot = await db
      .collection("users")
      .where("eveningEnabled", "==", true)
      .where("eveningHour", "==", hour)
      .get();

    // 重複を排除してユーザーIDのセットを作成
    const userIds = new Set<string>();
    morningUsersSnapshot.docs.forEach((doc) => userIds.add(doc.id));
    eveningUsersSnapshot.docs.forEach((doc) => userIds.add(doc.id));

    logger.info(`${hour}時: ${userIds.size}人のユーザーに通知送信`);

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

    const schedulesSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("schedules")
      .where("scheduledDate", ">=", admin.firestore.Timestamp.fromDate(today))
      .where("scheduledDate", "<", admin.firestore.Timestamp.fromDate(tomorrow))
      .where("requiresCompletion", "==", true)
      .get();

    // 遅延タスクを取得（過去の未完了タスク）
    const overdueSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("schedules")
      .where("scheduledDate", "<", admin.firestore.Timestamp.fromDate(today))
      .where("requiresCompletion", "==", true)
      .get();

    const todayCount = schedulesSnapshot.size;
    const overdueCount = overdueSnapshot.size;

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
    if (
      errorCode === "messaging/invalid-registration-token" ||
      errorCode === "messaging/registration-token-not-registered"
    ) {
      logger.warn(`[${userId}] 無効なFCMトークンを削除`);
      await db.collection("users").doc(userId).update({
        fcmToken: admin.firestore.FieldValue.delete(),
      });
    } else {
      logger.error(`[${userId}] 通知送信エラー:`, error);
    }
  }
}

/**
 * テスト用の手動実行可能な関数
 * 現在の時刻の通知をテストで送信
 */
export const sendTestNotification = onCall(async (request) => {
  const userId = request.auth?.uid;
  if (!userId) {
    throw new Error("認証が必要です");
  }

  const currentHour = new Date().getHours();
  const db = admin.firestore();
  const messaging = admin.messaging();

  logger.info(`[テスト通知] ユーザー: ${userId}, 時刻: ${currentHour}`);
  await sendNotificationToUser(userId, currentHour, db, messaging);

  return {
    success: true,
    message: `${currentHour}時の通知をテスト送信しました`,
  };
});
