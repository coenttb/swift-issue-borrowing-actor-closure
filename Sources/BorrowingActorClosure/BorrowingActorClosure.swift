// Minimal reproduction: Swift compiler crashes when a `borrowing` parameter
// on an actor method is used inside a closure.

public actor State {
    public var subscriptions: [Subscription] = []

    public init() {}

    // CRASHES: borrowing parameter used in closure predicate
    public func unsubscribe(_ subscription: borrowing Subscription) {
        subscriptions.removeAll { $0 === subscription }
    }
}

public final class Subscription: Sendable {}
