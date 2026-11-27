package com.budgeting.bugeting_app;

import android.app.Notification;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Parcelable;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Free, offline e-wallet tracking: Android hands Pitaka the notifications
 * of the apps the user connected (Maya, GCash, MariBank, BDO Pay), only
 * after the user turns on "Notification access" for Pitaka.
 *
 * Only notifications from the watched packages are kept, and only their
 * title, text and time. They wait in a small file in Pitaka's private
 * storage (not backed up) until the app is next unlocked; the Dart side
 * then reads them with {@link #drain}, parses them on the phone and
 * deletes the file. Nothing is ever sent over the network.
 */
public class PaymentNotificationListener extends NotificationListenerService {
    static final String PREFS = "pitaka_wallet_notifications";
    static final String KEY_PACKAGES = "packages";
    private static final String QUEUE_FILE = "wallet_notifications.json";
    private static final int MAX_QUEUE = 300;
    private static final Object LOCK = new Object();

    /** The packages to keep notifications from (set from Dart). */
    static void setWatched(Context context, List<String> packages) {
        Set<String> set = new HashSet<>();
        if (packages != null) set.addAll(packages);
        prefs(context).edit().putStringSet(KEY_PACKAGES, set).apply();
        if (set.isEmpty()) clear(context);
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        try {
            if (sbn == null) return;
            String pkg = sbn.getPackageName();
            Set<String> watched = prefs(this).getStringSet(KEY_PACKAGES, Collections.emptySet());
            if (watched == null || !watched.contains(pkg)) return;
            Notification n = sbn.getNotification();
            if (n == null || (n.flags & Notification.FLAG_GROUP_SUMMARY) != 0) return;
            Bundle extras = n.extras;
            if (extras == null) return;
            String title = firstNonEmpty(
                    extras.getCharSequence(Notification.EXTRA_TITLE_BIG),
                    extras.getCharSequence(Notification.EXTRA_TITLE));
            String body = textOf(n, extras);
            // Some apps put the whole alert in the title ("You received
            // P500.00") and leave the text empty; that is still a payment.
            if (body.isEmpty()) body = title;
            if (body.isEmpty()) return;
            if (body.equals(title)) title = "";
            long when = sbn.getPostTime();
            JSONObject o = new JSONObject();
            // Same app + same text within the same minute = the same payment
            // (apps often re-post or update a notification).
            o.put("id", pkg + "|" + Integer.toHexString(body.hashCode()) + "|" + (when / 60000L));
            o.put("package", pkg);
            o.put("title", title);
            o.put("text", body);
            o.put("date", when);
            append(this, o);
        } catch (Exception ignored) {
            // Never crash the listener over one notification.
        }
    }

    /**
     * The notification's message. Apps word and style these differently:
     * big text (most), plain text, inbox lines (several transfers in one
     * notification) or a messaging style. Received-money alerts often use
     * the last two, which were dropped before.
     */
    static String textOf(Notification n, Bundle extras) {
        String text = firstNonEmpty(
                extras.getCharSequence(Notification.EXTRA_BIG_TEXT),
                extras.getCharSequence(Notification.EXTRA_TEXT));
        if (!text.isEmpty()) return text;
        CharSequence[] lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES);
        if (lines != null && lines.length > 0) {
            StringBuilder sb = new StringBuilder();
            for (CharSequence line : lines) {
                if (line == null || line.length() == 0) continue;
                if (sb.length() > 0) sb.append(". ");
                sb.append(line);
            }
            if (sb.length() > 0) return sb.toString();
        }
        Parcelable[] messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES);
        if (messages != null && messages.length > 0) {
            // The newest message is last.
            for (int i = messages.length - 1; i >= 0; i--) {
                if (messages[i] instanceof Bundle) {
                    CharSequence t = ((Bundle) messages[i]).getCharSequence("text");
                    if (t != null && t.length() > 0) return t.toString();
                }
            }
        }
        return firstNonEmpty(
                extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT),
                n.tickerText);
    }

    private static String firstNonEmpty(CharSequence... values) {
        for (CharSequence v : values) {
            if (v != null) {
                String s = v.toString().trim();
                if (!s.isEmpty()) return s;
            }
        }
        return "";
    }

    private static File queueFile(Context context) {
        return new File(context.getNoBackupFilesDir(), QUEUE_FILE);
    }

    private static JSONArray read(Context context) {
        File f = queueFile(context);
        if (!f.isFile()) return new JSONArray();
        try (FileInputStream in = new FileInputStream(f)) {
            byte[] bytes = new byte[(int) f.length()];
            int off = 0;
            while (off < bytes.length) {
                int r = in.read(bytes, off, bytes.length - off);
                if (r < 0) break;
                off += r;
            }
            return new JSONArray(new String(bytes, 0, off, StandardCharsets.UTF_8));
        } catch (IOException | JSONException e) {
            return new JSONArray();
        }
    }

    private static void write(Context context, JSONArray items) throws IOException {
        File f = queueFile(context);
        File tmp = new File(f.getParentFile(), QUEUE_FILE + ".tmp");
        try (FileOutputStream out = new FileOutputStream(tmp)) {
            out.write(items.toString().getBytes(StandardCharsets.UTF_8));
        }
        if (!tmp.renameTo(f)) {
            //noinspection ResultOfMethodCallIgnored
            f.delete();
            //noinspection ResultOfMethodCallIgnored
            tmp.renameTo(f);
        }
    }

    static void append(Context context, JSONObject item) throws IOException, JSONException {
        synchronized (LOCK) {
            JSONArray items = read(context);
            String id = item.getString("id");
            for (int i = 0; i < items.length(); i++) {
                JSONObject o = items.optJSONObject(i);
                if (o != null && id.equals(o.optString("id"))) return;
            }
            items.put(item);
            // Keep only the newest MAX_QUEUE.
            JSONArray trimmed = new JSONArray();
            for (int i = Math.max(0, items.length() - MAX_QUEUE); i < items.length(); i++) trimmed.put(items.get(i));
            write(context, trimmed);
        }
    }

    /** Everything waiting, oldest first; the queue is emptied. */
    static List<Map<String, Object>> drain(Context context) {
        synchronized (LOCK) {
            JSONArray items = read(context);
            clear(context);
            List<Map<String, Object>> out = new ArrayList<>();
            for (int i = 0; i < items.length(); i++) {
                JSONObject o = items.optJSONObject(i);
                if (o == null) continue;
                Map<String, Object> m = new HashMap<>();
                m.put("id", o.optString("id"));
                m.put("package", o.optString("package"));
                m.put("title", o.optString("title"));
                m.put("text", o.optString("text"));
                m.put("date", o.optLong("date"));
                out.add(m);
            }
            return out;
        }
    }

    static void clear(Context context) {
        synchronized (LOCK) {
            //noinspection ResultOfMethodCallIgnored
            queueFile(context).delete();
        }
    }
}
