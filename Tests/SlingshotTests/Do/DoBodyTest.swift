#if Macros
import Testing
@testable import Slingshot

// @Do rewrites a function's body like #do, with `await` marking the binds and the return type giving them their type.

@Do
fileprivate func sum(_ a: Int?, _ b: Int?) -> Int? {
    let x = await a
    let y = await b
    return x + y
}

@Do
fileprivate func parsedTwice(_ text: String) -> Int? {
    let n = await Int(text)
    let doubled = n * 2
    let m = await Int("\(doubled)")
    return m + 1
}

@Do
fileprivate func endsWithABind(_ text: String) -> Int? {
    let n = await Int(text)
    return await Optional(n * 10)
}

@Do
fileprivate func noBinds() -> Int? {
    let n = 2
    return n + 1
}

/// The ticket can't be copied: it's carried past `peek`, which runs before `redeem` because redeem uses its label
@Do
fileprivate func redeemedTicket() -> Freer<Tickets.Family, String> {
    let ticket = await Tickets.issue()
    let label = await Tickets.peek("ticket")
    let number = await Tickets.redeem(consume ticket, note: label)
    return "\(label) \(number)"
}

/// `Tickets.issue()` and `peek` are generic over the stack: only the return type says it's Tickets.Family
@Do
fileprivate func independentSteps() -> Freer<Tickets.Family, String> {
    let first = await Tickets.peek("a")
    let second = await Tickets.peek("b")
    return first + second
}

@Do
fileprivate func branching(_ text: String) -> Int? {
    let n = await Int(text)
    if n > 10 {
        let m = await Optional(n * 2)
        return m + 1
    } else {
        return n
    }
}

@Do
fileprivate func switching(_ text: String) -> String? {
    let n = await Int(text)
    switch n {
    case 0:
        return "zero"
    case let k where k < 0:
        let doubled = await Optional(k * 2)
        return "negative \(doubled)"
    default:
        return await Optional("positive")
    }
}

/// The ticket is used up in one branch and dropped in the other: branches are plain blocks, so they can consume it
@Do
fileprivate func redeemIfLabelled(_ wanted: String) -> Freer<Tickets.Family, String> {
    let ticket = await Tickets.issue()
    let label = await Tickets.peek(wanted)
    if label.isEmpty {
        return "kept"
    } else {
        let number = await Tickets.redeem(consume ticket, note: label)
        return "\(label) \(number)"
    }
}

/// A branch's last line is its value; what follows runs after whichever branch was taken
@Do
fileprivate func withBonus(_ text: String) -> Int? {
    let n = await Int(text)
    let bonus = if n > 10 {
        let doubled = await Optional(n * 2)
        doubled + 1
    } else {
        0
    }
    return n + bonus
}

/// The ticket is carried into whichever case runs, then on to the step that consumes it
@Do
fileprivate func noteFor(_ wanted: String) -> Freer<Tickets.Family, String> {
    let ticket = await Tickets.issue()
    let note = switch wanted {
    case "":
        "blank"
    default:
        await Tickets.peek(wanted)
    }
    let number = await Tickets.redeem(consume ticket, note: note)
    return "\(note) \(number)"
}

/// A condition can be a bind: its value is tested once the program gives it
@Do
fileprivate func described(_ text: String) -> String? {
    if let n = await Optional(Int(text)) {
        return "number \(n)"
    } else {
        return "text"
    }
}

@Do
fileprivate func sign(_ text: String) -> String? {
    let n = await Int(text)
    if await Optional(n < 0) {
        return "negative"
    } else if n == 0 {
        return "zero"
    } else {
        let doubled = await Optional(n * 2)
        return "positive \(doubled)"
    }
}

fileprivate enum Reply {
    case accepted(Int)
    case refused
}

fileprivate func reply(_ text: String) -> Reply? {
    Int(text).map(Reply.accepted) ?? .refused
}

@Do
fileprivate func outcome(_ text: String) -> String? {
    if case .accepted(let n) = await reply(text) {
        return "accepted \(n)"
    } else {
        return "refused"
    }
}

/// Each condition runs only if the ones before it held, and the else runs wherever one fails
@Do
fileprivate func ordered(_ a: String, _ b: String) -> Int? {
    if !a.isEmpty, let x = await Optional(Int(a)), let y = await Optional(Int(b)), x < y {
        return x + y
    } else {
        return 0
    }
}

@Do
fileprivate func halved(_ text: String) -> Int? {
    guard let n = await Optional(Int(text)), n % 2 == 0 else {
        return -1
    }
    return n / 2
}

@Do
fileprivate func scored(_ text: String) -> Int? {
    let score = if let n = await Optional(Int(text)) { n * 10 } else { 0 }
    return score + 1
}

/// The ticket is carried past the guard's bind, into the rest of the block, or dropped by its else
@Do
fileprivate func redeemUnlessBlank(_ wanted: String) -> Freer<Tickets.Family, String> {
    let ticket = await Tickets.issue()
    guard let note = await Tickets.peek(wanted).map({ label -> String? in label.isEmpty ? nil : label }) else {
        return "kept"
    }
    let number = await Tickets.redeem(consume ticket, note: note)
    return "\(note) \(number)"
}

/// `return if` returns whichever branch's value, binds and all
@Do
fileprivate func tripled(_ text: String) -> Int? {
    return if let n = await Optional(Int(text)) {
        await Optional(n * 3)
    } else {
        -1
    }
}

@Do
fileprivate func named(_ text: String) -> String? {
    let n = await Int(text)
    return switch n {
    case 0:
        "zero"
    default:
        await Optional("n\(n)")
    }
}

/// A step whose value isn't needed is awaited on its own
@Do
fileprivate func peekedFirst() -> Freer<Tickets.Family, String> {
    await Tickets.peek("a")
    let b = await Tickets.peek("b")
    return b
}

@Suite("@Do")
struct DoBodyTest {
    @Test("a bare await runs its step and drops the value")
    func bareAwait() async throws {
        let result = try await peekedFirst().run(with: Office())
        #expect(result == "b")
    }

    @Test("return if returns the taken branch's value")
    func returnIf() {
        #expect(tripled("2") == 6)
        #expect(tripled("x") == -1)
    }

    @Test("return switch returns the taken case's value")
    func returnSwitch() {
        #expect(named("0") == "zero")
        #expect(named("4") == "n4")
        #expect(named("x") == nil)
    }

    @Test("if let binds its condition")
    func ifLetBinds() {
        #expect(described("4") == "number 4")
        #expect(described("x") == "text")
    }

    @Test("a Bool condition can bind, and an else if after it")
    func boolConditionBinds() {
        #expect(sign("-1") == "negative")
        #expect(sign("0") == "zero")
        #expect(sign("3") == "positive 6")
        #expect(sign("x") == nil)
    }

    @Test("if case binds its condition")
    func ifCaseBinds() {
        #expect(outcome("7") == "accepted 7")
        #expect(outcome("x") == "refused")
    }

    @Test("conditions bind in order, with plain ones around them")
    func conditionsBindInOrder() {
        #expect(ordered("1", "2") == 3)
        #expect(ordered("", "2") == 0)
        #expect(ordered("x", "2") == 0)
        #expect(ordered("1", "x") == 0)
        #expect(ordered("3", "2") == 0)
    }

    @Test("guard let binds its condition for the rest of the block")
    func guardLetBinds() {
        #expect(halved("8") == 4)
        #expect(halved("3") == -1)
        #expect(halved("x") == -1)
    }

    @Test("let x = if can bind its condition")
    func letIfBindsItsCondition() {
        #expect(scored("2") == 21)
        #expect(scored("x") == 1)
    }

    @Test("a guard's bind carries a noncopyable value to the rest of the block")
    func guardCarriesNoncopyableValues() async throws {
        let redeemed = try await redeemUnlessBlank("x").run(with: Office())
        #expect(redeemed == "x 8")
        let kept = try await redeemUnlessBlank("").run(with: Office())
        #expect(kept == "kept")
    }

    @Test("let x = if gives the taken branch's value to what follows")
    func letIf() {
        #expect(withBonus("20") == 61)
        #expect(withBonus("3") == 3)
        #expect(withBonus("x") == nil)
    }

    @Test("let x = switch carries a noncopyable value through its cases")
    func letSwitch() async throws {
        let blank = try await noteFor("").run(with: Office())
        #expect(blank == "blank 12")
        let peeked = try await noteFor("x").run(with: Office())
        #expect(peeked == "x 8")
    }

    @Test("an if's branches can bind")
    func ifBranchesBind() {
        #expect(branching("20") == 41)
        #expect(branching("3") == 3)
        #expect(branching("x") == nil)
    }

    @Test("a switch's cases can bind")
    func switchCasesBind() {
        #expect(switching("0") == "zero")
        #expect(switching("-2") == "negative -4")
        #expect(switching("5") == "positive")
    }

    @Test("a branch can consume a noncopyable value, and another can leave it")
    func branchesConsumeOrLeave() async throws {
        let redeemed = try await redeemIfLabelled("x").run(with: Office())
        #expect(redeemed == "x 8")
        let kept = try await redeemIfLabelled("").run(with: Office())
        #expect(kept == "kept")
    }

    @Test("independent binds combine, and nil stops the function")
    func independentBinds() {
        #expect(sum(1, 2) == 3)
        #expect(sum(nil, 2) == nil)
    }

    @Test("plain statements between dependent binds are kept")
    func dependentBinds() {
        #expect(parsedTwice("4") == 9)
        #expect(parsedTwice("x") == nil)
    }

    @Test("return await ends with a bind")
    func returnAwait() {
        #expect(endsWithABind("3") == 30)
    }

    @Test("a body with no binds is pure")
    func noBindsIsPure() {
        #expect(noBinds() == 3)
    }

    @Test("a noncopyable value is carried to where it's consumed")
    func carriesNoncopyableValues() async throws {
        // run outside #expect, whose expansion could try to copy the noncopyable program
        let result = try await redeemedTicket().run(with: Office())
        #expect(result == "ticket 13")
    }

    @Test("the return type gives every step its stack")
    func returnTypeGivesTheStack() async throws {
        let program = independentSteps()
        let isBoth = program.isBoth
        #expect(isBoth)
        let result = try await program.run(with: Office())
        #expect(result == "ab")
    }
}
#endif
