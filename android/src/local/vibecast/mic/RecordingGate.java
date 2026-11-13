package local.vibecast.mic;

import java.util.HashSet;
import java.util.Set;

/** A button press or elapsed timer is never evidence that recording has started. */
public final class RecordingGate {
    private Set<Integer> baseline = new HashSet<>();
    private boolean requested, confirmed;
    public void begin(Set<Integer> activeSessions) {
        baseline = new HashSet<>(activeSessions); requested = false; confirmed = false;
    }
    public void requested() { requested = true; }
    public boolean observe(Set<Integer> activeSessions) {
        if (!requested || confirmed) return false;
        for (Integer session : activeSessions) if (!baseline.contains(session)) {
            confirmed = true; return true;
        }
        return false;
    }
}
