import Testing
@testable import Slingshot

@Suite("AlgrebraicEffects TaggedDelimitations test")
struct AlgebraicEffects_TaggedDelimitationsTest {
    @Test func `does the thing`() async {
        #expect(example(tag: 2, body: twice) == "<Hi A! | Hi B!>")
        #expect(example(tag: 1, body: twice) == "<Hi A!> | <Hi B!>")
        #expect(example(tag: 2, body: abort) == "<skipped>")
        #expect(example(tag: 1, body: abort) == "skipped")
    }
}

fileprivate func twice(body: @escaping (String) -> Continuation<TaggedDelimitations.Block, String>) -> Continuation<TaggedDelimitations.Block, String> {
    body("A").flatMap { a in body("B").map { b in "\(a) | \(b)" }  }
}

fileprivate func abort(body: @escaping (String) -> Continuation<TaggedDelimitations.Block, String>) -> Continuation<TaggedDelimitations.Block, String> {
    .pure("skipped")
}


fileprivate func example(
    tag: TaggedDelimitations.Tag,
    body: @escaping (@escaping (String) -> Continuation<TaggedDelimitations.Block, String>) -> Continuation<TaggedDelimitations.Block, String>
) -> String {
    let capture = TaggedDelimitations.capture(tag: tag, body: body)
    
    let tag2 = TaggedDelimitations.prompt(
        tag: 2,
        continuation: capture.map { x in "Hi \(x)!" }
    )
    
    let tag1 = TaggedDelimitations.prompt(
        tag: 1,
        continuation: tag2.map { x in "<\(x)>" }
    )
    
    return tag1.runPrompts().right!
}
