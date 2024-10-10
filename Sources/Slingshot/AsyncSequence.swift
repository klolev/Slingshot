//
//  AsyncSequence.swift
//
//
//  Created by Chloé Léveillé on 2024-06-05.
//

import Foundation

public struct PrefixedAsyncSequence<Prefix, Tail>: AsyncSequence
where Prefix: AsyncSequence, Tail: AsyncSequence, Prefix.Element == Tail.Element {
    public typealias Element = Tail.Element
    
    let prefix: Prefix
    let tail: Tail
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        private var prefix: Prefix.AsyncIterator
        private var tail: Tail.AsyncIterator
        
        init(prefix: Prefix, tail: Tail) {
            self.prefix = prefix.makeAsyncIterator()
            self.tail = tail.makeAsyncIterator()
        }
        
        public mutating func next() async throws -> Tail.Element? {
            if let prefixValue = try await prefix.next() {
                prefixValue
            } else {
                try await tail.next()
            }
        }
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        .init(prefix: prefix, tail: tail)
    }
}

public extension AsyncSequence {
    func prefixed<Head>(by head: Head) -> PrefixedAsyncSequence<Head, Self>
    where Head: AsyncSequence, Head.Element == Element {
        .init(prefix: head, tail: self)
    }
}

public extension Sequence {
    var asyncStream: AsyncStream<Element> {
        var iterator = makeIterator()
        return AsyncStream {
            iterator.next()
        }
    }
}
