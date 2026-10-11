import XCTest
@testable import QTPCore

final class TemplateRendererTests: XCTestCase {

    func testSubstitutesAllPlaceholders() {
        let template = "app={{app_name}} before={{context_before}} sel={{selected_text}} after={{context_after}} g={{glossary}}"
        let out = TemplateRenderer.render(template, values: [
            "app_name": "Mail",
            "context_before": "B",
            "selected_text": "S",
            "context_after": "A",
            "glossary": "G",
        ])
        XCTAssertEqual(out, "app=Mail before=B sel=S after=A g=G")
    }

    func testSinglePassNeverExpandsSubstitutedValues() {
        let template = "X {{selected_text}} Y {{glossary}} Z"
        let out = TemplateRenderer.render(template, values: [
            "selected_text": "text with {{glossary}} inside",
            "glossary": "GLOSSARY",
        ])
        XCTAssertEqual(out, "X text with {{glossary}} inside Y GLOSSARY Z")
    }

    func testUnknownPlaceholderLeftVerbatim() {
        let out = TemplateRenderer.render("a {{nope}} b", values: ["selected_text": "s"])
        XCTAssertEqual(out, "a {{nope}} b")
    }

    func testUnterminatedBracesLeftVerbatim() {
        let out = TemplateRenderer.render("a {{selected_text", values: ["selected_text": "s"])
        XCTAssertEqual(out, "a {{selected_text")
    }

    func testWhitespaceInsideBracesIsTolerated() {
        let out = TemplateRenderer.render("{{ app_name }}", values: ["app_name": "Notes"])
        XCTAssertEqual(out, "Notes")
    }

    func testMultilineAndEmojiPayloadsSurvive() {
        let value = "line1\nline2 😀🇯🇵 𠮷野家\n\"quoted\" & <tags>"
        let out = TemplateRenderer.render("<t>{{selected_text}}</t>", values: ["selected_text": value])
        XCTAssertEqual(out, "<t>\(value)</t>")
    }

    func testEmptyValues() {
        let out = TemplateRenderer.render("[{{glossary}}]", values: ["glossary": ""])
        XCTAssertEqual(out, "[]")
    }
}
