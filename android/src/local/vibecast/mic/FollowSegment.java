package local.vibecast.mic;

/** Code-point port of the locally patched VibeCast web FollowSegment. */
public final class FollowSegment {
    private int[] previous = new int[0];
    private int boundary;
    private String retained = "";

    public void cut(String text) {
        previous = text.codePoints().toArray();
        boundary = previous.length;
        retained = "";
    }

    public String update(String text) {
        int[] next = text.codePoints().toArray();
        int prefix = 0;
        while (prefix < previous.length && prefix < next.length && previous[prefix] == next[prefix]) prefix++;
        int suffix = 0;
        while (suffix < previous.length - prefix && suffix < next.length - prefix
                && previous[previous.length - 1 - suffix] == next[next.length - 1 - suffix]) suffix++;
        int oldEnd = previous.length - suffix;
        int newEnd = next.length - suffix;
        if (prefix < boundary) {
            if (oldEnd <= boundary) boundary += newEnd - oldEnd;
            else {
                retained += new String(previous, boundary, oldEnd - boundary);
                boundary = newEnd;
            }
        }
        boundary = Math.max(0, Math.min(boundary, next.length));
        previous = next;
        return retained + new String(next, boundary, next.length - boundary);
    }
}
