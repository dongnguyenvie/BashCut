import BashCutProject
import Testing

struct SearchFoldedTests {
    @Test("Lowercase, no accents or width variants, đ and Đ as d")
    func folds() {
        #expect("Đã gửi".searchFolded == "da gui")
        #expect("Dịch PHỤ ĐỀ".searchFolded == "dich phu de")
        #expect("ＡＢＣ１".searchFolded == "abc1")
    }
}
