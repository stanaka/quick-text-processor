import XCTest
@testable import QTPCore

final class SeedTasksTests: XCTestCase {

    func testFiveSeedsWithStableKeys() {
        XCTAssertEqual(SeedTasks.all.map(\.key),
                       ["dictation", "proofread", "summarize", "translate_ja", "translate_en"])
    }

    func testEveryTemplateHasRequiredPlaceholders() {
        for seed in SeedTasks.all {
            XCTAssertTrue(seed.template.contains("{{selected_text}}"), seed.key)
            XCTAssertTrue(seed.template.contains("{{glossary}}"), seed.key)
            XCTAssertTrue(seed.template.contains("{{context_before}}"), seed.key)
            XCTAssertTrue(seed.template.contains("{{context_after}}"), seed.key)
            XCTAssertTrue(seed.template.contains("{{app_name}}"), seed.key)
            if seed.key == "dictation" {
                // Auto-insert stays plain text: no reasoning tokens delaying
                // the ⏎-confirmation.
                XCTAssertTrue(seed.template.contains("Output ONLY"), seed.key)
                XCTAssertFalse(seed.template.contains("<reasoning>"), seed.key)
            } else {
                XCTAssertTrue(seed.template.contains("<reasoning>"), seed.key)
                XCTAssertTrue(seed.template.contains("</reasoning>"), seed.key)
            }
        }
    }

    func testLegacyTemplateLookup() {
        for key in ["proofread", "summarize", "translate_ja", "translate_en"] {
            let legacy = SeedTasks.legacyTemplates(forKey: key)
            XCTAssertFalse(legacy.isEmpty, key)
            // Legacy texts are frozen snapshots, distinct from current seeds.
            XCTAssertFalse(legacy.contains(SeedTasks.template(forKey: key) ?? ""), key)
        }
        XCTAssertEqual(SeedTasks.legacyTemplates(forKey: "dictation"), [])
        XCTAssertEqual(SeedTasks.legacyTemplates(forKey: "nope"), [])
    }

    func testDefaultTasksOrderingAndFlags() {
        let tasks = SeedTasks.defaultTasks()
        XCTAssertEqual(tasks.map(\.sortOrder), [0, 1, 2, 3, 4])
        XCTAssertTrue(tasks.allSatisfy(\.includeGlossary))
        // Dictation fixes are meant to flow straight back into the document.
        XCTAssertEqual(tasks.first { $0.seedKey == "dictation" }?.autoInsert, true)
        XCTAssertEqual(tasks.first { $0.seedKey == "summarize" }?.autoInsert, false)
    }

    func testTemplateLookupByKey() {
        XCTAssertEqual(SeedTasks.template(forKey: "proofread"),
                       SeedTasks.all[1].template)
        XCTAssertNil(SeedTasks.template(forKey: "nope"))
    }

    func testTemplatesRenderCleanly() {
        // A rendered seed template must not leave any placeholder behind.
        let values = CapturedText(selected: "Hello", before: "b", after: "a",
                                  appName: "Notes", source: .accessibility)
            .templateValues(glossary: "")
        for seed in SeedTasks.all {
            let rendered = TemplateRenderer.render(seed.template, values: values)
            XCTAssertFalse(rendered.contains("{{"), seed.key)
            XCTAssertTrue(rendered.contains("Hello"), seed.key)
        }
    }
}
