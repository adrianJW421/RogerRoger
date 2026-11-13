import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { App } from "./app.ts";
import { setLang } from "./i18n.ts";

const wire = vi.hoisted(() => ({ options: null as any, sent: [] as any[] }));
vi.mock("./ws/client.ts", () => ({
  WSClient: class {
    constructor(options: any) { wire.options = options; }
    connect() { wire.options.onState("connected"); }
    sendHello() {}
    send(message: any) { wire.sent.push(message); }
  },
}));

const hello = {
  type: "hello_ack", serverName: "Mac", protocolVersion: 1,
  accessibilityGranted: true, voiceRelayEnabled: false,
  targets: [{ id: "current_app", displayName: "当前应用", available: true, clearAfterSend: true, allowEmpty: false, syncMode: "editor" }],
};

function selectInput() {
  const input = document.querySelector("textarea")!;
  input.focus();
  const selection = wire.sent.find(message => message.type === "select_target");
  expect(selection.userInitiated).toBe(true);
  wire.options.onMessage({ type: "target_status", targetId: "current_app", sessionId: selection.sessionId, status: "focused" });
  return { input, sessionId: selection.sessionId };
}

beforeEach(() => {
  vi.useFakeTimers();
  localStorage.clear();
  setLang("zh-CN");
  wire.sent.length = 0;
  document.body.innerHTML = '<div id="app"></div>';
  new App(document.getElementById("app")!).start();
  wire.options.onMessage(hello);
});
afterEach(() => { vi.clearAllTimers(); vi.useRealTimers(); });

describe("focus ownership", () => {
  it("keeps drafts on reconnect without reactivating or replaying the previous target", () => {
    const { input, sessionId } = selectInput();
    input.value = "保留草稿";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(150);
    wire.options.onState("disconnected");
    wire.sent.length = 0;
    wire.options.onState("connected");
    wire.options.onMessage(hello);
    expect(wire.sent).toEqual([]);
    input.value = "断线后继续识别的草稿";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(150);
    expect(wire.sent).toEqual([]);
    expect(input.value).toBe("断线后继续识别的草稿");
    const refocus = [...document.querySelectorAll("button")].find(button => button.textContent === "重新聚焦")!;
    refocus.click();
    expect(wire.sent).toEqual([{ type: "select_target", sessionId, targetId: "current_app", userInitiated: true }]);
  });

  it("pauses snapshots on focus loss and ignores stale-session focus notifications", () => {
    const { input, sessionId } = selectInput();
    wire.options.onMessage({ type: "target_status", targetId: "current_app", sessionId, status: "not_focused", message: "同步已暂停" });
    wire.sent.length = 0;
    wire.options.onMessage({ type: "target_status", targetId: "current_app", sessionId: "old-session", status: "focused" });
    input.value = "切换应用后还在识别";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(150);
    expect(wire.sent).toEqual([]);
    expect(document.querySelector(".card__status")!.textContent).toContain("同步已暂停");
  });
});

describe("automatic Mac focus following", () => {
  function start() {
    const input = document.querySelector("textarea")!;
    input.value = "上一处留下的文字";
    wire.options.onMessage({ ...hello, followFocusSupported: true });
    const follow = wire.sent.find(message => message.type === "follow_current");
    expect(follow).toBeTruthy();
    return { input, followId: follow.followId };
  }
  function context(followId: string, sessionId: string, focused = true) {
    wire.options.onMessage({ type: "focus_context", followId, sessionId, targetId: "current_app", focused,
      displayName: "Mac app", message: focused ? "自动跟随" : "等待 Mac 光标" });
  }
  function type(input: HTMLTextAreaElement, text: string) {
    input.value = text;
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(300);
  }

  it("automatically starts, switches segments and never replays old text", () => {
    const { input, followId } = start();
    context(followId, "field-a");
    expect(wire.sent.filter(message => message.type === "text_snapshot")).toHaveLength(0);
    type(input, "上一处留下的文字第一句");
    expect(wire.sent.at(-1)).toMatchObject({ type: "text_snapshot", sessionId: "field-a", text: "第一句" });
    context(followId, "field-b");
    type(input, "上一处留下的文字第一句第二句");
    expect(wire.sent.at(-1)).toMatchObject({ type: "text_snapshot", sessionId: "field-b", text: "第二句" });
    expect(input.value).toBe("上一处留下的文字第一句第二句");
    expect(wire.sent.some(message => message.type === "select_target" || message.type === "clear")).toBe(false);
    wire.options.onMessage({ type: "text_ack", targetId: "current_app", sessionId: "field-a", revision: 100,
      applied: false, errorCode: "TARGET_NOT_FOCUSED" });
    type(input, "上一处留下的文字第一句第二句。");
    expect(wire.sent.at(-1)).toMatchObject({ sessionId: "field-b", text: "第二句。" });
  });

  it("cuts live composition before its queued snapshot and preserves the Android buffer", () => {
    const { input, followId } = start();
    context(followId, "before");
    input.dispatchEvent(new CompositionEvent("compositionstart"));
    input.value += "还在识别的旧片段";
    input.dispatchEvent(new Event("input"));
    context(followId, "after");
    vi.advanceTimersByTime(300);
    expect(wire.sent.filter(message => message.type === "text_snapshot")).toHaveLength(0);
    type(input, input.value + "新片段");
    expect(wire.sent.at(-1)).toMatchObject({ sessionId: "after", text: "新片段", isComposing: true });
  });

  it("waits on non-input surfaces and reconnects without draft replay", () => {
    const { input, followId } = start();
    context(followId, "no-input", false);
    type(input, input.value + "没有输入框时的文字");
    expect(wire.sent.filter(message => message.type === "text_snapshot")).toHaveLength(0);
    context(followId, "ready");
    type(input, input.value + "新的输入");
    expect(wire.sent.at(-1)).toMatchObject({ sessionId: "ready", text: "新的输入" });
    wire.options.onState("disconnected");
    wire.sent.length = 0;
    wire.options.onState("connected");
    wire.options.onMessage({ ...hello, followFocusSupported: true });
    expect(wire.sent).toHaveLength(1);
    expect(wire.sent[0].type).toBe("follow_current");
    expect(wire.sent[0].followId).not.toBe(followId);
    context(followId, "stale-subscription");
    type(input, input.value + "尚未准备好");
    expect(wire.sent).toHaveLength(1);
    context(wire.sent[0].followId, "reconnected");
    type(input, input.value + "重连后的新段");
    expect(wire.sent.at(-1)).toMatchObject({ sessionId: "reconnected", text: "重连后的新段" });
  });
});
