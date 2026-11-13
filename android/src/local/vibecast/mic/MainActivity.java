package local.vibecast.mic;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioManager;
import android.media.AudioRecordingConfiguration;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowInsetsAnimationController;
import android.view.WindowInsetsAnimationControlListener;
import android.view.WindowManager;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import okhttp3.HttpUrl;
import org.json.JSONObject;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.UUID;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public final class MainActivity extends Activity implements RelayClient.Events {
    private static final String SOGOU = "com.sohu.inputmethod.sogou.xiaomi";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final FollowSegment segment = new FollowSegment();
    private final RecordingGate recordingGate = new RecordingGate();
    private final StopDrain stopDrain = new StopDrain();
    private final SendQueue sendQueue = new SendQueue();
    private AudioManager audioManager;
    private boolean recordingCallbackRegistered, recordingReady, recordingUnconfirmed, readyCueSent;
    private long tapAt, controlAt, requestAt, recordingAt, firstTextAt, firstAckAt, stopAt, lastTextAt, releaseAt;
    private int lateIgnoredUpdates;
    private String readyEvidence = "";
    private final AudioManager.AudioRecordingCallback recordingCallback = new AudioManager.AudioRecordingCallback() {
        @Override public void onRecordingConfigChanged(List<AudioRecordingConfiguration> configs) {
            if (listening && requestAt > 0 && recordingGate.observe(recordingSessions(configs)))
                markRecordingReady("recording_callback");
        }
    };
    private InputMethodManager ime;
    private RelayClient relay;
    private SharedPreferences prefs;
    private EditText editor;
    private TextView connectionLabel, targetLabel, detailLabel;
    private Button micButton, sendButton, settingsButton;
    private boolean foreground, connected, focused, listening, accepting, settling, blocked;
    private boolean enterSupported;
    private int enterRequests, enterAcknowledgments;
    private String connectionState = "disconnected", notice = "", targetName = "", followId = "", sessionId = "", lastSent = "";
    private int voiceEpoch, revision, lastAck, textUpdates, sentSnapshots, acknowledgedSnapshots;
    private CancellationSignal controlRequest;
    private WindowInsetsAnimationController controlledIme;
    private boolean snapshotScheduled, diagnosticsScheduled;
    private final Runnable snapshot = () -> { snapshotScheduled = false; flush(); };
    private final Runnable sendTick = this::pumpSend;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        ime = getSystemService(InputMethodManager.class);
        audioManager = getSystemService(AudioManager.class);
        try {
            audioManager.registerAudioRecordingCallback(recordingCallback, handler);
            recordingCallbackRegistered = true;
        } catch (RuntimeException ignored) { recordingCallbackRegistered = false; }
        prefs = getSharedPreferences("connection", MODE_PRIVATE);
        if (!prefs.contains("clientId")) prefs.edit().putString("clientId", UUID.randomUUID().toString()).apply();
        // Provisioning is read only from this app's private files, never an exported Intent.
        File provision = new File(getFilesDir(), "pairing-url.txt");
        if (provision.isFile()) {
            try {
                String url = new String(Files.readAllBytes(provision.toPath()), StandardCharsets.UTF_8).trim();
                validate(url); prefs.edit().putString("url", url).commit();
            } catch (Exception ignored) { notice = "连接链接无效, 请重新设置"; }
            provision.delete();
        }
        buildUi();
        relay = new RelayClient(handler, this);
        render();
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private TextView label(String text, int size, int color) {
        TextView view = new TextView(this); view.setText(text); view.setTextSize(size); view.setTextColor(color);
        view.setGravity(Gravity.CENTER); view.setPadding(0, dp(4), 0, dp(4)); return view;
    }
    private void buildUi() {
        int dark = Color.rgb(23, 36, 58), muted = Color.rgb(100, 112, 132);
        FrameLayout frame = new FrameLayout(this); frame.setBackgroundColor(Color.rgb(245, 247, 252));
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER); root.setPadding(dp(28), dp(24), dp(28), dp(24));
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        scroll.addView(root, new ScrollView.LayoutParams(-1, -2));
        FrameLayout.LayoutParams rootParams = new FrameLayout.LayoutParams(dp(480), -1, Gravity.CENTER);
        rootParams.width = Math.min(dp(480), getResources().getDisplayMetrics().widthPixels);
        frame.addView(scroll, rootParams);
        root.addView(label("RogerRoger", 26, dark));
        connectionLabel = label("正在连接电脑", 15, muted); root.addView(connectionLabel);
        targetLabel = label("在 Mac 上点进输入框", 17, dark); root.addView(targetLabel);
        micButton = new Button(this); micButton.setTextSize(28); micButton.setAllCaps(false);
        micButton.setTextColor(Color.WHITE); micButton.setFocusable(false);
        LinearLayout.LayoutParams micParams = new LinearLayout.LayoutParams(-1, dp(170));
        micParams.topMargin = dp(14); micParams.bottomMargin = dp(12);
        root.addView(micButton, micParams);
        micButton.setOnClickListener(v -> { if (listening) stopVoice(true); else startVoice(); });
        sendButton = new Button(this); sendButton.setTextSize(26); sendButton.setAllCaps(false);
        sendButton.setTextColor(Color.WHITE); sendButton.setFocusable(false);
        LinearLayout.LayoutParams sendParams = new LinearLayout.LayoutParams(-1, dp(100));
        root.addView(sendButton, sendParams);
        sendButton.setOnClickListener(v -> requestEnter());
        detailLabel = label("文字跟随 Mac 光标\n无需清空或重新聚焦", 14, muted); root.addView(detailLabel);
        settingsButton = new Button(this); settingsButton.setAllCaps(false); settingsButton.setText("连接设置");
        settingsButton.setTextSize(16); settingsButton.setFocusable(false);
        LinearLayout.LayoutParams settingsParams = new LinearLayout.LayoutParams(-1, dp(48));
        settingsParams.topMargin = dp(10); root.addView(settingsButton, settingsParams);
        settingsButton.setOnClickListener(v -> showConnection());
        editor = new EditText(this);
        editor.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        editor.setImeOptions(EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN | EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING);
        editor.setShowSoftInputOnFocus(false); editor.setCursorVisible(false); editor.setAlpha(0);
        editor.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS);
        editor.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        frame.addView(editor, new FrameLayout.LayoutParams(dp(2), dp(2), Gravity.TOP | Gravity.LEFT));
        editor.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            public void onTextChanged(CharSequence s, int start, int before, int count) {}
            public void afterTextChanged(Editable value) {
                if (!accepting) {
                    if (stopAt > 0 && SystemClock.elapsedRealtime() - stopAt < 5000 && value.length() > 0) {
                        lateIgnoredUpdates++; diagnostics();
                    }
                    return;
                }
                lastTextAt = SystemClock.elapsedRealtime();
                if (firstTextAt == 0) firstTextAt = lastTextAt;
                if (listening && requestAt > 0 && !recordingReady) markRecordingReady("recognized_text");
                textUpdates++;
                if (!snapshotScheduled) { snapshotScheduled = true; handler.postDelayed(snapshot, 40); }
                diagnostics();
            }
        });
        // Apply only system bars. The IME surface is controlled separately while speaking.
        frame.setOnApplyWindowInsetsListener((v, insets) -> {
            Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            root.setPadding(dp(28) + bars.left, dp(14) + bars.top, dp(28) + bars.right, dp(14) + bars.bottom);
            int height = frame.getHeight() > 0 ? frame.getHeight() : getResources().getDisplayMetrics().heightPixels;
            int usable = Math.max(0, height - bars.top - bars.bottom - dp(28));
            micParams.height = Math.max(dp(112), Math.min(dp(170), Math.round(usable * .24f)));
            sendParams.height = Math.max(dp(76), Math.min(dp(100), Math.round(usable * .15f)));
            micButton.setLayoutParams(micParams); sendButton.setLayoutParams(sendParams);
            return insets;
        });
        setContentView(frame);
        frame.post(() -> {
            WindowInsetsController controller = getWindow().getInsetsController();
            if (controller != null) {
                int appearance = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                controller.setSystemBarsAppearance(appearance, appearance);
            }
        });
    }

    private HttpUrl validate(String value) {
        HttpUrl url = HttpUrl.parse(value);
        if (url == null || !url.username().isEmpty() || !url.password().isEmpty()) throw new IllegalArgumentException();
        String token = url.queryParameter("token");
        if (token == null || token.length() < 8 || token.length() > 512) throw new IllegalArgumentException();
        return url;
    }
    private void connect() {
        String value = prefs.getString("url", "");
        if (value.isEmpty()) { notice = "先连接电脑上的 RogerRoger"; render(); return; }
        try {
            HttpUrl url = validate(value);
            String socketUrl = url.newBuilder().encodedPath("/ws").query(null).fragment(null).build().toString();
            socketUrl = socketUrl.replaceFirst("^http", "ws");
            resetTarget(); connected = false; blocked = false; notice = "";
            relay.connect(socketUrl, url.queryParameter("token"), prefs.getString("clientId", ""));
        } catch (IllegalArgumentException error) { notice = "连接链接无效, 请重新设置"; render(); }
    }
    private void showConnection() {
        stopVoice(false);
        EditText input = new EditText(this); input.setSingleLine(true);
        input.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_VARIATION_URI);
        input.setHint("粘贴 Mac 上的连接链接"); input.setText(prefs.getString("url", ""));
        input.setSelectAllOnFocus(true); input.setPadding(dp(20), dp(16), dp(20), dp(16));
        new AlertDialog.Builder(this).setTitle("连接电脑")
                .setMessage("手机与 Mac 连接同一网络, 使用 RogerRoger 菜单里的手机连接链接")
                .setView(input).setNegativeButton("取消", null)
                .setPositiveButton("连接", (dialog, which) -> {
                    String value = input.getText().toString().trim();
                    try { validate(value); prefs.edit().putString("url", value).apply(); connect(); }
                    catch (IllegalArgumentException error) { notice = "需要完整链接, 包含 token 参数"; render(); }
                }).show();
    }

    @Override public void state(String value) {
        connectionState = value;
        if (!"authenticating".equals(value)) {
            connected = false; resetTarget();
            if (listening || accepting) stopVoice(false);
        }
        render();
    }
    private void resetTarget() {
        sendQueue.cancel(); sendQueue.contextChanged(""); enterSupported = false;
        focused = false; followId = ""; sessionId = ""; revision = 0; lastAck = 0; lastSent = "";
        if (editor != null) segment.cut(editor.getText().toString());
        handler.removeCallbacks(snapshot); snapshotScheduled = false;
    }
    private void followCurrent() {
        focused = false; sessionId = ""; revision = 0; lastAck = 0; lastSent = "";
        segment.cut(editor.getText().toString());
        followId = UUID.randomUUID().toString();
        relay.send(RelayClient.json("type", "follow_current", "followId", followId));
    }
    @Override public void message(JSONObject message) {
        String type = message.optString("type");
        if ("hello_ack".equals(type)) {
            if (!message.optBoolean("followFocusSupported") || !message.optBoolean("accessibilityGranted")) {
                notice = "请检查 Mac 的 RogerRoger 版本和辅助功能权限"; blocked = true; relay.close(); render(); return;
            }
            enterSupported = message.optBoolean("currentAppEnterSupported");
            connected = true; connectionState = "connected"; notice = ""; followCurrent(); render();
        } else if ("focus_context".equals(type) && followId.equals(message.optString("followId"))) {
            String nextSession = message.optString("sessionId");
            boolean cancelledSend = sendQueue.contextChanged(nextSession);
            boolean interruptedTail = settling && !sessionId.equals(nextSession);
            if (interruptedTail) stopVoice(false);
            sessionId = message.optString("sessionId"); focused = message.optBoolean("focused");
            targetName = message.optString("displayName", "");
            segment.cut(editor.getText().toString()); lastSent = ""; revision = 0; lastAck = 0;
            notice = cancelledSend || interruptedTail ? "Mac 输入位置已改变, 已取消收尾和发送" : "";
            cueIfReady(); render();
        } else if ("text_ack".equals(type) && !sessionId.isEmpty() && sessionId.equals(message.optString("sessionId"))) {
            if (message.optBoolean("applied")) {
                if (firstAckAt == 0) firstAckAt = SystemClock.elapsedRealtime();
                lastAck = Math.max(lastAck, message.optInt("revision")); acknowledgedSnapshots++; diagnostics(); pumpSend();
            } else {
                String code = message.optString("errorCode");
                // A focus-context update can race an old snapshot while switching Mac fields.
                // Wait for the fresh context without stopping Sogou or replaying the old buffer.
                if ("TARGET_NOT_FOCUSED".equals(code) || "UNKNOWN_TARGET".equals(code)) {
                    focused = false; segment.cut(editor.getText().toString());
                    sendQueue.cancel(); if (settling) stopVoice(false);
                }
                else if (!"STALE_REVISION".equals(code)) {
                    stopVoice(false); notice = "同步未完成, 请检查 Mac 输入框后重新开始";
                }
                render();
            }
        } else if ("send_result".equals(type)) {
            if (sendQueue.result(message.optString("sessionId"), message.optInt("revision"),
                    message.optBoolean("success"), "SEND_UNKNOWN".equals(message.optString("errorCode")))) {
                if (message.optBoolean("success")) { enterAcknowledgments++; notice = "已在 Mac 按下 Enter"; }
                else notice = sendQueue.state() == SendQueue.State.UNCERTAIN ?
                        "发送结果未确认, 请查看 Mac; 不会自动重发" : "未按下 Enter, 请确认 Mac 输入位置后再试";
                render();
            }
        } else if ("error".equals(type)) {
            stopVoice(false);
            String code = message.optString("errorCode");
            if ("INACTIVE_SESSION".equals(code) || "BAD_TOKEN".equals(code) || "UNPAIRED".equals(code)) {
                blocked = true; connected = false; relay.close(); resetTarget();
                notice = "INACTIVE_SESSION".equals(code) ? "其他设备接管了连接, 点连接设置可重新连接" : "配对链接已失效, 请重新连接";
            } else notice = "Mac 返回错误: " + code;
            render();
        }
    }
    private void requestEnter() {
        if (!connected || !focused || listening || !enterSupported || !foreground) return;
        flush();
        if (!sendQueue.enqueue(sessionId, SystemClock.elapsedRealtime())) return;
        notice = ""; pumpSend(); render();
    }
    private void pumpSend() {
        handler.removeCallbacks(sendTick);
        if (!sendQueue.busy()) return;
        long now = SystemClock.elapsedRealtime();
        if (sendQueue.expire(now)) {
            notice = sendQueue.state() == SendQueue.State.UNCERTAIN ?
                    "发送结果未确认, 请查看 Mac; 不会自动重发" : "文字同步未完成, 本次没有按 Enter";
            render(); return;
        }
        if (sendQueue.state() == SendQueue.State.QUEUED && (!connected || !focused || !foreground)) {
            sendQueue.cancel(); notice = "连接或输入位置已变化, 已取消发送"; render(); return;
        }
        if (sendQueue.dispatch(sessionId, revision, lastAck, !listening && !settling && !accepting, now)) {
            if (relay.send(RelayClient.json("type", "send", "sessionId", sendQueue.session(),
                    "targetId", "current_app", "revision", sendQueue.revision(), "pressEnter", true))) {
                enterRequests++;
            } else {
                sendQueue.result(sendQueue.session(), sendQueue.revision(), false, false);
                notice = "连接已断开, 本次没有按 Enter";
            }
            render();
        }
        if (sendQueue.busy()) handler.postDelayed(sendTick, 100);
    }
    private void flush() {
        if (!accepting) return;
        String buffer = editor.getText().toString();
        String text = segment.update(buffer);
        if (!connected || !focused || sessionId.isEmpty()) { segment.cut(buffer); return; }
        if (text.equals(lastSent)) return;
        boolean composing = BaseInputConnection.getComposingSpanStart(editor.getText()) >= 0;
        int next = revision + 1;
        if (relay.send(RelayClient.json("type", "text_snapshot", "sessionId", sessionId,
                "targetId", "current_app", "revision", next, "text", text,
                "selectionStart", text.length(), "selectionEnd", text.length(),
                "isComposing", composing, "clientTimestamp", System.currentTimeMillis()))) {
            revision = next; lastSent = text; sentSnapshots++; diagnostics();
        }
    }

    private void startVoice() {
        if (!connected || settling || !foreground || sendQueue.busy()) return;
        String current = Settings.Secure.getString(getContentResolver(), Settings.Secure.DEFAULT_INPUT_METHOD);
        if (current == null || !current.startsWith(SOGOU + "/")) {
            notice = "请将输入法切换为搜狗输入法小米版"; render(); return;
        }
        accepting = false;
        sendQueue.reset();
        tapAt = SystemClock.elapsedRealtime(); controlAt = requestAt = recordingAt = firstTextAt = firstAckAt = stopAt = lastTextAt = releaseAt = 0;
        lateIgnoredUpdates = 0; readyEvidence = ""; recordingReady = false; recordingUnconfirmed = false; readyCueSent = false;
        recordingGate.begin(activeRecordingSessions());
        final int epoch = ++voiceEpoch;
        releaseControl(); handler.removeCallbacks(snapshot); snapshotScheduled = false;
        editor.setText(""); followCurrent();
        editor.requestFocus(); ime.restartInput(editor);
        listening = true; accepting = true; notice = "";
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); render();
        editor.post(() -> {
            if (epoch != voiceEpoch || !listening) return;
            if (!hasWindowFocus()) { failVoice("请回到 App 后重新开始"); return; }
            controlRequest = new CancellationSignal();
            try {
                editor.getWindowInsetsController().controlWindowInsetsAnimation(WindowInsets.Type.ime(), -1, null,
                        controlRequest, new WindowInsetsAnimationControlListener() {
                    @Override public void onReady(WindowInsetsAnimationController controller, int types) {
                        if (epoch != voiceEpoch || !listening) { controller.finish(false); return; }
                        controlledIme = controller;
                        controlAt = SystemClock.elapsedRealtime();
                        controller.setInsetsAndAlpha(controller.getHiddenStateInsets(), 0f, 0f);
                        // Wait only for the next UI frame, not a fixed 250 ms delay.
                        editor.postOnAnimation(() -> {
                            if (epoch != voiceEpoch || !listening || !controller.isReady() || !hasWindowFocus()) return;
                            try {
                                requestAt = SystemClock.elapsedRealtime(); recordingGate.requested();
                                sendBroadcast(new Intent("miui.intent.action.START_IME_VOICE_INPUT").setPackage(SOGOU));
                                if (recordingGate.observe(activeRecordingSessions())) markRecordingReady("recording_query");
                                handler.postDelayed(() -> {
                                    if (epoch == voiceEpoch && listening && !recordingReady) {
                                        recordingUnconfirmed = true; render();
                                    }
                                }, 3500);
                            }
                            catch (SecurityException error) { failVoice("搜狗语音入口暂不可用"); }
                            diagnostics();
                        });
                    }
                    @Override public void onFinished(WindowInsetsAnimationController controller) {
                        if (controlledIme == controller) controlledIme = null;
                    }
                    @Override public void onCancelled(WindowInsetsAnimationController controller) {
                        if (epoch != voiceEpoch || !listening) return;
                        controlledIme = null; failVoice("语音已暂停, 点一下可重新开始");
                    }
                });
                handler.postDelayed(() -> {
                    if (epoch == voiceEpoch && listening && controlledIme == null) failVoice("未能启动语音, 请重试");
                }, 6000);
            } catch (RuntimeException error) { failVoice("当前无法隐藏输入法面板, 请重试"); }
        });
    }
    private Set<Integer> recordingSessions(List<AudioRecordingConfiguration> configurations) {
        Set<Integer> result = new HashSet<>();
        for (AudioRecordingConfiguration configuration : configurations) {
            int source = configuration.getClientAudioSource();
            if (!configuration.isClientSilenced() && source != 8 && source != 4)
                result.add(configuration.getClientAudioSessionId());
        }
        return result;
    }
    private Set<Integer> activeRecordingSessions() {
        try { return recordingSessions(audioManager.getActiveRecordingConfigurations()); }
        catch (RuntimeException ignored) { return new HashSet<>(); }
    }
    private void markRecordingReady(String evidence) {
        if (!listening || recordingReady) return;
        recordingReady = true; recordingUnconfirmed = false;
        recordingAt = SystemClock.elapsedRealtime(); readyEvidence = evidence;
        cueIfReady();
        render();
    }
    private void cueIfReady() {
        if (listening && recordingReady && focused && !readyCueSent) {
            readyCueSent = true;
            micButton.performHapticFeedback(HapticFeedbackConstants.CONFIRM);
        }
    }
    private void failVoice(String message) { stopVoice(false); notice = message; render(); }
    private void releaseControl() {
        WindowInsetsAnimationController controller = controlledIme; controlledIme = null;
        CancellationSignal signal = controlRequest; controlRequest = null;
        if (controller != null && controller.isReady()) controller.finish(false);
        if (signal != null) signal.cancel();
    }
    private void stopVoice(boolean settle) {
        if (editor == null) return;
        flush(); boolean wasRecording = recordingReady;
        listening = false; recordingReady = false;
        stopAt = SystemClock.elapsedRealtime();
        final int epoch = ++voiceEpoch;
        settling = settle && accepting && connected && requestAt > 0 && wasRecording;
        if (settling) {
            // Hiding the IME immediately can discard Sogou's unfinished phrase.
            // Keep the same hidden input session alive while the final words arrive.
            stopDrain.begin(stopAt); finishWhenQuiet(epoch);
        } else {
            accepting = false; sendQueue.cancel(); endInputSession();
        }
        render();
    }
    private void endInputSession() {
        releaseAt = SystemClock.elapsedRealtime();
        releaseControl(); ime.hideSoftInputFromWindow(editor.getWindowToken(), 0);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
    private void finishWhenQuiet(int epoch) {
        handler.postDelayed(() -> {
            if (epoch != voiceEpoch || !settling) return;
            StopDrain.Action action = stopDrain.step(SystemClock.elapsedRealtime(), lastTextAt);
            if (action == StopDrain.Action.HIDE) { endInputSession(); render(); }
            if (action != StopDrain.Action.FINISH) { finishWhenQuiet(epoch); return; }
            flush(); accepting = false; settling = false; pumpSend(); render();
        }, 100);
    }
    private void render() {
        if (micButton == null) return;
        connectionLabel.setText(connected ? "手机搜狗识别 · 已连接 Mac" : blocked ? "连接已暂停" :
                "connecting".equals(connectionState) || "authenticating".equals(connectionState) ? "正在连接电脑…" : "尚未连接电脑");
        targetLabel.setText(focused ? "当前应用: " + targetName : connected ? "在 Mac 上点进输入框" : "手机和 Mac 连接同一网络");
        micButton.setText(listening ? (recordingReady ? (focused ? "可以说话\n点击停止" : "等待 Mac 光标\n点击停止") : "正在启动…\n点击取消") : settling ? "正在收尾…" : "开始说话");
        micButton.setEnabled(connected && !settling && !sendQueue.busy());
        GradientDrawable background = new GradientDrawable(); background.setCornerRadius(dp(30));
        background.setColor(!connected ? Color.rgb(139, 154, 180) : listening ?
                (recordingReady && focused ? Color.rgb(22, 119, 94) : Color.rgb(152, 111, 42)) : Color.rgb(23, 59, 133));
        micButton.setBackground(background);
        SendQueue.State sendState = sendQueue.state();
        sendButton.setText(sendState == SendQueue.State.QUEUED ? (settling ? "收尾后发送…" : "等待文字同步…") :
                sendState == SendQueue.State.SENT ? "正在按 Enter…" : sendState == SendQueue.State.DONE ? "已按 Enter" :
                sendState == SendQueue.State.UNCERTAIN ? "请查看 Mac 结果" : "发送 (Enter)");
        boolean canSend = connected && focused && enterSupported && !listening && sendState == SendQueue.State.IDLE;
        sendButton.setEnabled(canSend);
        GradientDrawable sendBackground = new GradientDrawable(); sendBackground.setCornerRadius(dp(24));
        sendBackground.setColor(canSend ? Color.rgb(72, 66, 145) : Color.rgb(139, 154, 180));
        sendButton.setBackground(sendBackground);
        detailLabel.setText(!notice.isEmpty() ? notice : listening ?
                (!recordingReady ? (recordingUnconfirmed ? "尚未确认录音状态\n请确认手机麦克风指示灯亮起后再说" : "正在启动手机搜狗\n显示「可以说话」并轻震后再开口") :
                focused ? "手机麦克风已开启\n文字跟随 Mac 光标" : "等待 Mac 输入光标\n此时说的话不会补写到其他位置") :
                settling ? (stopDrain.isHidden() ? "录音已结束, 等待剩余文字\n可先点发送, 同步后自动按 Enter" :
                        "收尾中, 麦克风暂时保持开启\n可先点发送, 收尾后自动按 Enter") :
                !enterSupported && connected ? "Mac 版本暂不支持 Enter, 请更新" : "停止后可点发送\n等同于 Mac 输入框中的 Enter");
        diagnostics();
    }
    private void diagnostics() {
        if (diagnosticsScheduled) return;
        diagnosticsScheduled = true;
        handler.postDelayed(() -> {
            diagnosticsScheduled = false;
            // Metadata only: never persist speech, token, connection URL or input-buffer contents.
            JSONObject data = RelayClient.json("version", "0.1.3", "connected", connected, "focused", focused,
                    "listening", listening, "settling", settling, "controlReady", controlledIme != null && controlledIme.isReady(),
                    "textUpdates", textUpdates, "sentSnapshots", sentSnapshots, "acknowledgedSnapshots", acknowledgedSnapshots,
                    "revision", revision, "lastAck", lastAck, "notice", notice,
                    "recordingReady", recordingReady, "readyEvidence", readyEvidence,
                    "tapToControlMs", latency(controlAt, tapAt), "tapToRequestMs", latency(requestAt, tapAt),
                    "tapToRecordingMs", latency(recordingAt, tapAt), "tapToFirstTextMs", latency(firstTextAt, tapAt),
                    "firstTextToAckMs", latency(firstAckAt, firstTextAt),
                    "lastTextAfterStopMs", latency(lastTextAt, stopAt), "lateIgnoredUpdates", lateIgnoredUpdates,
                    "inputReleaseAfterStopMs", latency(releaseAt, stopAt),
                    "enterSupported", enterSupported, "sendState", sendQueue.state().name(),
                    "enterRequests", enterRequests, "enterAcknowledgments", enterAcknowledgments);
            try { Files.write(new File(getFilesDir(), "status.json").toPath(), data.toString().getBytes(StandardCharsets.UTF_8)); }
            catch (Exception ignored) {}
        }, 500);
    }
    private long latency(long end, long start) { return start > 0 && end >= start ? end - start : -1; }
    @Override protected void onResume() {
        super.onResume(); foreground = true;
        if (relay != null && !blocked) connect();
    }
    @Override protected void onPause() {
        foreground = false; stopVoice(false);
        if (relay != null) relay.close();
        connected = false; connectionState = "disconnected"; resetTarget();
        super.onPause();
    }
    @Override protected void onDestroy() {
        voiceEpoch++; accepting = false; listening = false; releaseControl();
        if (relay != null) relay.destroy();
        if (recordingCallbackRegistered) audioManager.unregisterAudioRecordingCallback(recordingCallback);
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }
}
