package local.vibecast.mic;
import java.util.Arrays;
import java.util.HashSet;
public final class RecordingGateTest {
    static int checks;
    static HashSet<Integer> sessions(Integer... ids) { return new HashSet<>(Arrays.asList(ids)); }
    static void expect(boolean want, boolean got) {
        checks++; if (want != got) throw new AssertionError("Recording readiness must follow a new recording session");
    }
    public static void main(String[] args) {
        RecordingGate gate = new RecordingGate();
        gate.begin(sessions(10));
        expect(false, gate.observe(sessions(10, 11))); // No speech request yet.
        gate.requested();
        expect(false, gate.observe(sessions(10))); // An existing recorder is not ours.
        expect(false, gate.observe(sessions())); // No recorder, however long we wait.
        expect(true, gate.observe(sessions(10, 11)));
        expect(false, gate.observe(sessions(10, 11))); // One cue per start.
        gate.begin(sessions(11)); gate.requested();
        expect(false, gate.observe(sessions(11))); // Previous session cannot cue a new start.
        expect(true, gate.observe(sessions(12)));
        gate.begin(sessions());
        expect(false, gate.observe(sessions()));
        gate.requested(); expect(true, gate.observe(sessions(0))); // OEM may anonymize IDs.
        System.out.println("Passed " + checks + " recording-readiness assertions");
    }
}
