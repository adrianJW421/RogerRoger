package local.vibecast.mic;

/** Sogou exposes no final-result callback. Keep its live input session briefly,
 * then drain late edits after hiding. These are bounded heuristics, not an ASR final signal. */
public final class StopDrain {
    public enum Action { WAIT, HIDE, FINISH }
    private long stoppedAt, hiddenAt;
    private boolean hidden;
    public void begin(long now) { stoppedAt = now; hiddenAt = 0; hidden = false; }
    public boolean isHidden() { return hidden; }
    public Action step(long now, long lastTextAt) {
        if (!hidden) {
            if (now - stoppedAt >= 4500 ||
                    (now - stoppedAt >= 2000 && now - lastTextAt >= 700)) {
                hidden = true; hiddenAt = now; return Action.HIDE;
            }
        } else if (now - hiddenAt >= 1600 ||
                (now - hiddenAt >= 600 && now - lastTextAt >= 350)) {
            return Action.FINISH;
        }
        return Action.WAIT;
    }
}
