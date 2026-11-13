package local.vibecast.mic;

/** Exactly one user-requested Enter, tied to the original Mac input session.
 * A lost response must never cause an automatic retry of a possible submission. */
public final class SendQueue {
    public enum State { IDLE, QUEUED, SENT, DONE, UNCERTAIN }
    private State state = State.IDLE;
    private String session = "";
    private int revision;
    private long deadline;
    public State state() { return state; }
    public String session() { return session; }
    public int revision() { return revision; }
    public boolean busy() { return state == State.QUEUED || state == State.SENT; }
    public void reset() { state = State.IDLE; session = ""; revision = 0; }
    public boolean enqueue(String currentSession, long now) {
        if (state != State.IDLE || currentSession.isEmpty()) return false;
        state = State.QUEUED; session = currentSession; deadline = now + 12000; return true;
    }
    public boolean dispatch(String currentSession, int currentRevision, int acknowledged, boolean stable, long now) {
        if (state != State.QUEUED) return false;
        if (!session.equals(currentSession) || now >= deadline) { reset(); return false; }
        if (!stable || acknowledged < currentRevision) return false;
        revision = currentRevision; state = State.SENT; deadline = now + 6000; return true;
    }
    public boolean result(String fromSession, int fromRevision, boolean success, boolean uncertain) {
        if (state != State.SENT || !session.equals(fromSession) || revision != fromRevision) return false;
        state = success ? State.DONE : uncertain ? State.UNCERTAIN : State.IDLE; return true;
    }
    public boolean contextChanged(String currentSession) {
        if (session.equals(currentSession)) return false;
        if (state == State.QUEUED) { reset(); return true; }
        // A submit may itself move focus. Keep awaiting that exact result.
        if (state == State.DONE || state == State.UNCERTAIN) reset();
        return false;
    }
    public boolean expire(long now) {
        if (!busy() || now < deadline) return false;
        state = state == State.SENT ? State.UNCERTAIN : State.IDLE; return true;
    }
    public void cancel() {
        if (state == State.SENT) state = State.UNCERTAIN;
        else if (state == State.QUEUED) reset();
    }
}
