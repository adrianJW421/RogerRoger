package local.vibecast.mic;

import android.os.Handler;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;
import org.json.JSONObject;
import java.util.concurrent.TimeUnit;

/** All callbacks are serialized on the Activity's main Handler. Never queues old dictation. */
final class RelayClient {
    interface Events {
        void state(String state);
        void message(JSONObject message);
    }
    private final Handler handler;
    private final Events events;
    private final OkHttpClient http = new OkHttpClient.Builder()
            .connectTimeout(6, TimeUnit.SECONDS).readTimeout(0, TimeUnit.SECONDS)
            .pingInterval(15, TimeUnit.SECONDS).build();
    private WebSocket socket;
    private int generation;
    private int attempt;
    private boolean running;
    private String url, token, clientId;
    private Runnable retry;

    RelayClient(Handler handler, Events events) { this.handler = handler; this.events = events; }

    void connect(String url, String token, String clientId) {
        close();
        this.url = url; this.token = token; this.clientId = clientId;
        running = true; attempt = 0;
        open();
    }

    private void open() {
        if (!running) return;
        final int current = ++generation;
        events.state("connecting");
        socket = http.newWebSocket(new Request.Builder().url(url).build(), new WebSocketListener() {
            @Override public void onOpen(WebSocket ws, Response response) {
                handler.post(() -> {
                    if (current != generation || !running) { ws.cancel(); return; }
                    attempt = 0;
                    events.state("authenticating");
                    send(json("type", "hello", "protocolVersion", 1, "clientId", clientId,
                            "deviceName", "VibeCast Android Mic", "pairingToken", token));
                });
            }
            @Override public void onMessage(WebSocket ws, String text) {
                if (text.length() > 1024 * 1024) { ws.close(1009, "Message too large"); return; }
                handler.post(() -> {
                    if (current != generation || !running) return;
                    try { events.message(new JSONObject(text)); } catch (org.json.JSONException ignored) {}
                });
            }
            @Override public void onClosing(WebSocket ws, int code, String reason) { ws.close(code, reason); }
            @Override public void onClosed(WebSocket ws, int code, String reason) { lost(current); }
            @Override public void onFailure(WebSocket ws, Throwable error, Response response) { lost(current); }
        });
    }

    private void lost(int current) {
        handler.post(() -> {
            if (current != generation || !running) return;
            generation++; socket = null;
            events.state("disconnected");
            int delay = Math.min(8000, 500 * (1 << Math.min(attempt++, 4)));
            retry = this::open;
            handler.postDelayed(retry, delay);
        });
    }

    boolean send(JSONObject message) { return socket != null && socket.send(message.toString()); }

    void close() {
        running = false; generation++;
        if (retry != null) handler.removeCallbacks(retry);
        retry = null;
        WebSocket old = socket; socket = null;
        if (old != null) old.cancel();
    }

    void destroy() { close(); http.dispatcher().executorService().shutdown(); http.connectionPool().evictAll(); }

    static JSONObject json(Object... pairs) {
        JSONObject object = new JSONObject();
        try {
            for (int i = 0; i < pairs.length; i += 2) object.put((String)pairs[i], pairs[i + 1]);
        } catch (org.json.JSONException error) { throw new IllegalArgumentException(error); }
        return object;
    }
}
