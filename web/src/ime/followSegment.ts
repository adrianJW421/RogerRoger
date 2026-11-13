/** Keep the Android IME's buffer intact while routing only the current segment.
 * Clearing a textarea during dictation can cancel composition or resurrect text.
 * Changes wholly in an older segment adjust the boundary, never replay that text.
 * Ambiguous corrections crossing the boundary are excluded conservatively.
 */
export class FollowSegment {
  private previous: string[] = [];
  private boundary = 0;
  private retained = "";

  cut(text: string): void {
    this.previous = Array.from(text);
    this.boundary = this.previous.length;
    this.retained = "";
  }

  update(text: string): string {
    const next = Array.from(text);
    let prefix = 0;
    while (prefix < this.previous.length && prefix < next.length && this.previous[prefix] === next[prefix]) prefix++;
    let suffix = 0;
    while (suffix < this.previous.length - prefix && suffix < next.length - prefix &&
           this.previous[this.previous.length - 1 - suffix] === next[next.length - 1 - suffix]) suffix++;
    const oldEnd = this.previous.length - suffix;
    const newEnd = next.length - suffix;
    if (prefix < this.boundary) {
      if (oldEnd <= this.boundary) this.boundary += newEnd - oldEnd;
      else {
        // A late rewrite spans both destinations. Preserve what was already
        // shown in this destination rather than deleting it with an empty result.
        this.retained += this.previous.slice(this.boundary, oldEnd).join("");
        this.boundary = newEnd;
      }
    }
    this.boundary = Math.max(0, Math.min(this.boundary, next.length));
    this.previous = next;
    return this.retained + next.slice(this.boundary).join("");
  }
}
