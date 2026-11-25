import Testing
@testable import Slingshot

@Suite("Continuation Shift")
struct Continuation_ShiftTest {
    @Test func `does the thing`() async {
        #expect(greeting(body: once).evaluate() == "Hello world!")
        #expect(greeting(body: abort).evaluate() == "skipped")
        #expect(greeting(body: twice).evaluate() == "Hello A!/Hello B!")
    }
    
    @Test func `does the thing in Do macro`() async {
        #expect(greetingDo(body: once).reset().evaluate() == "Hello world!")
        #expect(greetingDo(body: abort).reset().evaluate() == "skipped")
        #expect(greetingDo(body: twice).reset().evaluate() == "Hello A!/Hello B!")
    }
}

fileprivate func greeting<Result>(body: @escaping (@escaping (String) -> String) -> Continuation<String, String>) -> Continuation<Result, String> {
    .shift(body).flatMap { result in
        .pure("Hello " + result + "!")
    }.reset()
}

@Do
fileprivate func greetingDo(body: @escaping (@escaping (String) -> String) -> Continuation<String, String>) -> Continuation<String, String> {
    let result = await Continuation<String, String>.shift(body)
    return "Hello \(result)!"
}

fileprivate func once(k: @escaping (String) -> String) -> Continuation<String, String> {
    .pure(k("world"))
}

fileprivate func abort(k: @escaping (String) -> String) -> Continuation<String, String> {
    .pure("skipped")
}

fileprivate func twice(k: @escaping (String) -> String) -> Continuation<String, String> {
    .pure(k("A") + "/" + k("B"))
}
