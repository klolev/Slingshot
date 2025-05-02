public protocol OptionalProtocol {
    associatedtype Wrapped
    var value: Wrapped? { get }
}

extension Optional: OptionalProtocol {
    public var value: Wrapped? { self }
}

extension Sequence {
    public func compactCast<T>(as type: T.Type) -> [T] {
        compactMap { $0 as? T }
    }

    public func max<T>(by keyPath: KeyPath<Element, T>) -> Element? where T: Comparable {
        self.max(by: { $0[keyPath: keyPath] < $1[keyPath: keyPath] })
    }

    public func min<T>(by keyPath: KeyPath<Element, T>) -> Element? where T: Comparable {
        self.min(by: { $0[keyPath: keyPath] < $1[keyPath: keyPath] })
    }
}

extension Sequence where Element: OptionalProtocol {
    public var compacted: [Element.Wrapped] {
        compactMap(\.value)
    }
}

public struct PrefixedSequence<Prefix, Tail>: Sequence
where Prefix: Sequence, Tail: Sequence, Prefix.Element == Tail.Element {
    let prefix: Prefix
    let tail: Tail

    public struct PrefixIterator: IteratorProtocol {
        private var prefix: Prefix.Iterator
        private var tail: Tail.Iterator

        init(prefix: Prefix, tail: Tail) {
            self.prefix = prefix.makeIterator()
            self.tail = tail.makeIterator()
        }

        public mutating func next() -> Tail.Element? {
            prefix.next() ?? tail.next()
        }
    }

    public func makeIterator() -> PrefixIterator {
        .init(prefix: prefix, tail: tail)
    }
}

extension Sequence {
    public func prefixed<Head>(by head: Head) -> PrefixedSequence<Head, Self>
    where Head: Sequence, Head.Element == Element {
        .init(prefix: head, tail: self)
    }

    public var erased: AnySequence<Element> {
        .init(makeIterator)
    }
}

extension Sequence where Element: FloatingPoint {
    public var mean: Element? {
        let count = Element(count)
        return count > 0 ? reduce(0, +) / count : nil
    }
}

public struct ChunkedSequence<OriginalSequence> where OriginalSequence: Sequence {
    private let chunkSize: UInt
    private let sequence: OriginalSequence

    public init(chunksOf chunkSize: UInt, from sequence: OriginalSequence) {
        self.chunkSize = chunkSize
        self.sequence = sequence
    }
}

extension ChunkedSequence: Sequence {
    public struct Iterator: IteratorProtocol {
        private let chunkSize: UInt
        private var iterator: OriginalSequence.Iterator

        init(chunksOf chunkSize: UInt, from iterator: OriginalSequence.Iterator) {
            self.chunkSize = chunkSize
            self.iterator = iterator
        }

        public mutating func next() -> [OriginalSequence.Element]? {
            let chunk = (0..<Int(chunkSize))
                .compactMap { _ in
                    iterator.next()
                }

            return chunk.count == chunkSize ? chunk : nil
        }
    }

    public func makeIterator() -> Iterator {
        .init(chunksOf: chunkSize, from: sequence.makeIterator())
    }
}

extension Sequence {
    public func chunked(by chunkSize: UInt) -> ChunkedSequence<Self> {
        .init(chunksOf: chunkSize, from: self)
    }
}

public struct ChunkedCollection<OriginalCollection>
where OriginalCollection: Collection, OriginalCollection.Index == Int {
    private let chunkSize: UInt
    private var collection: OriginalCollection

    init(chunksOf chunkSize: UInt, from collection: OriginalCollection) {
        self.chunkSize = chunkSize
        self.collection = collection
    }
}

extension ChunkedCollection: Sequence {
    public typealias Element = OriginalCollection.SubSequence
}

extension ChunkedCollection: Collection {
    public typealias Index = Int

    public subscript(position: Int) -> OriginalCollection.SubSequence {
        let startPosition = position * Int(chunkSize)
        return collection[startPosition..<(startPosition + Int(chunkSize))]
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int {
        let (quotient, remainder) = collection.count.quotientAndRemainder(
            dividingBy: Int(chunkSize))
        return quotient + Swift.min(remainder, 1)
    }

    public func index(after i: Int) -> Int {
        i + 1
    }
}

extension ChunkedCollection: BidirectionalCollection
where OriginalCollection: BidirectionalCollection {
    public func index(before i: Int) -> Int {
        i - 1
    }
}

extension ChunkedCollection: RandomAccessCollection
where OriginalCollection: RandomAccessCollection {}

public extension Collection where Index == Int {
    func chunked(by chunkSize: UInt) -> ChunkedCollection<Self> {
        .init(chunksOf: chunkSize, from: self)
    }
}
