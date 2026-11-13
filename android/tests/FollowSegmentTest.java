package local.vibecast.mic;

public final class FollowSegmentTest {
    static int checks;
    static void expect(String want, String got) {
        checks++;
        if (!want.equals(got)) throw new AssertionError("Expected " + want + " but got " + got);
    }
    public static void main(String[] args) {
        FollowSegment s = new FollowSegment();
        s.cut("前一个应用👨‍👩‍👧‍👦");
        expect("", s.update("前一个应用👨‍👩‍👧‍👦"));
        expect("新句子", s.update("前一个应用👨‍👩‍👧‍👦新句子"));
        expect("新句子。", s.update("前一个应用👨‍👩‍👧‍👦新句子。"));
        s.cut("他在电脑上");
        expect("新内容", s.update("他在电脑上新内容"));
        expect("新内容", s.update("它在电脑上新内容"));
        expect("新内容", s.update("它就在电脑上新内容"));
        expect("新内荣", s.update("它就在电脑上新内荣"));
        s.cut("我试");
        expect("", s.update("我是一句话"));
        expect("下一段", s.update("我是一句话下一段"));
        s.cut("旧段"); expect("", s.update("")); expect("新段", s.update("新段"));
        s.cut("新段"); expect("再下一段", s.update("新段再下一段"));
        s.cut("旧的句子"); expect("新文字", s.update("旧的句子新文字"));
        expect("新文字", s.update("旧句子和新字"));
        expect("新文字继续输入", s.update("旧句子和新字继续输入"));
        s.cut(""); expect("新的一次", s.update("新的一次"));
        s.cut("新的一次"); expect("", s.update("新的一次"));
        expect("再说", s.update("新的一次再说"));
        System.out.println("Passed " + checks + " focus-boundary assertions");
    }
}
