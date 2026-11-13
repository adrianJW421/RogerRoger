import { describe, expect, it } from "vitest";
import { FollowSegment } from "./followSegment.ts";

describe("dictation segments across Mac focus changes", () => {
  it("leaves the old utterance behind and accepts only the new suffix", () => {
    const segment = new FollowSegment();
    segment.cut("前一个应用👨‍👩‍👧‍👦");
    expect(segment.update("前一个应用👨‍👩‍👧‍👦")).toBe("");
    expect(segment.update("前一个应用👨‍👩‍👧‍👦新的句子")).toBe("新的句子");
    expect(segment.update("前一个应用👨‍👩‍👧‍👦新的句子。")).toBe("新的句子。");
  });

  it("keeps late corrections to the old segment out of the new field", () => {
    const segment = new FollowSegment();
    segment.cut("他在电脑上");
    expect(segment.update("他在电脑上新内容")).toBe("新内容");
    expect(segment.update("它在电脑上新内容")).toBe("新内容");
    expect(segment.update("它就在电脑上新内容")).toBe("新内容");
    expect(segment.update("它就在电脑上新内荣")).toBe("新内荣");
  });

  it("excludes ambiguous rewrites spanning the cut, then resumes new text", () => {
    const segment = new FollowSegment();
    segment.cut("我试");
    expect(segment.update("我是一句话")).toBe("");
    expect(segment.update("我是一句话下一段")).toBe("下一段");
  });

  it("handles an IME buffer reset without replaying or requiring manual clear", () => {
    const segment = new FollowSegment();
    segment.cut("旧段");
    expect(segment.update("")).toBe("");
    expect(segment.update("新段")).toBe("新段");
    segment.cut("新段");
    expect(segment.update("新段再下一段")).toBe("再下一段");
  });

  it("does not erase already inserted text when an ambiguous correction crosses destinations", () => {
    const segment = new FollowSegment();
    segment.cut("旧的句子");
    expect(segment.update("旧的句子新文字")).toBe("新文字");
    expect(segment.update("旧句子和新字")).toBe("新文字");
    expect(segment.update("旧句子和新字继续输入")).toBe("新文字继续输入");
  });
});
