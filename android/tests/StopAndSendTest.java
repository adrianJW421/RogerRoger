package local.vibecast.mic;

public final class StopAndSendTest {
    private static int checks;
    private static void check(boolean value) { checks++; if (!value) throw new AssertionError("check " + checks); }
    public static void main(String[] args) {
        StopDrain drain = new StopDrain(); drain.begin(1000);
        check(drain.step(1100, 900) == StopDrain.Action.WAIT);
        check(drain.step(2999, 900) == StopDrain.Action.WAIT);
        check(drain.step(3000, 2900) == StopDrain.Action.WAIT); // a late ending keeps session alive
        check(drain.step(3600, 2900) == StopDrain.Action.HIDE);
        check(drain.step(4000, 3900) == StopDrain.Action.WAIT); // drain commits after hide
        check(drain.step(4300, 3900) == StopDrain.Action.FINISH);
        drain.begin(1000);
        check(drain.step(5500, 5499) == StopDrain.Action.HIDE); // bounded, even if continuous noise
        check(drain.step(7100, 7099) == StopDrain.Action.FINISH);

        SendQueue queue = new SendQueue();
        check(queue.enqueue("input-a", 1000));
        check(!queue.enqueue("input-a", 1001)); // double tap
        check(!queue.dispatch("input-a", 20, 20, false, 1100)); // stop is still draining
        check(!queue.dispatch("input-a", 21, 20, true, 4000)); // final edit not acknowledged
        check(queue.dispatch("input-a", 21, 21, true, 4100));
        check(!queue.dispatch("input-a", 21, 21, true, 4101)); // no repeated Enter
        check(!queue.result("input-old", 21, true, false));
        check(!queue.result("input-a", 20, true, false));
        check(!queue.contextChanged("input-b")); // application moved after submission
        check(queue.result("input-a", 21, true, false));
        check(queue.state() == SendQueue.State.DONE);
        check(!queue.enqueue("input-a", 5000));
        queue.reset(); queue.enqueue("input-a", 1000);
        check(queue.contextChanged("input-b"));
        check(!queue.dispatch("input-b", 0, 0, true, 1100)); // no send in new target
        queue.enqueue("input-b", 2000); check(queue.expire(14000));
        check(queue.state() == SendQueue.State.IDLE); // ACK timeout before any Enter
        queue.enqueue("input-b", 20000); queue.dispatch("input-b", 0, 0, true, 20001);
        check(queue.expire(26001)); check(queue.state() == SendQueue.State.UNCERTAIN);
        check(!queue.enqueue("input-b", 27000)); // lost result cannot retry
        queue.reset(); queue.enqueue("input-a", 1000); queue.cancel();
        check(queue.state() == SendQueue.State.IDLE);
        queue.enqueue("input-a", 1000); queue.dispatch("input-a", 1, 1, true, 1001); queue.cancel();
        check(queue.state() == SendQueue.State.UNCERTAIN);
        System.out.println("PASS: " + checks + " tail-drain / queued Enter assertions");
    }
}
