import Testing
@testable import Slingshot

@Suite("Continuation Monad")
struct Continuation_MonadTest {
    @Test func `does the thing`() async {
        #expect(addC(1, 1).flatMap { result in
            addC(result, 1)
        }.evaluate() == 3)
    }
    
    @Test func `maintains order`() async {
        #expect(addC(1, 1).flatMap { result in
            subtractC(result, 3)
        }.flatMap { result in
            addC(result, 1)
        }.evaluate() == 0)
    }
    
    #if Macros
    @Test func `works in do`() async {
        let result: Continuation<Int, Int> = #do { bind in
            let a = bind(addC(1, 1))
            let b = bind(subtractC(a, 1))
            return b
        }
        
        #expect(result.evaluate() == 1)
    }
    #endif
}

fileprivate func addC<Result>(_ a: Int, _ b: Int) -> Continuation<Result, Int> {
    Continuation { k in
        k(a + b)
    }
}

fileprivate func subtractC<Result>(_ a: Int, _ b: Int) -> Continuation<Result, Int> {
    Continuation { k in
        k(a - b)
    }
}
