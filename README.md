# Swift Compiler Crash: `borrowing` Parameter in Actor Method Used in Closure

## Description

The Swift compiler crashes with signal 5 during SIL processing when a `borrowing` parameter on an actor method is used inside a closure (e.g., as a predicate for `removeAll`).

## Environment

- **Swift version**: 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
- **Target**: arm64-apple-macosx26.0
- **Crash location**: `MoveOnlyTypeEliminator` SIL pass

## Minimal Reproduction

```swift
public actor State {
    public var subscriptions: [Subscription] = []

    // CRASHES: borrowing parameter used in closure predicate
    public func unsubscribe(_ subscription: borrowing Subscription) {
        subscriptions.removeAll { $0 === subscription }
    }
}

public final class Subscription: Sendable {}
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-borrowing-actor-closure
cd swift-issue-borrowing-actor-closure
swift build
```

Or directly:

```bash
echo '
public actor State {
    public var items: [Item] = []
    public func remove(_ item: borrowing Item) {
        items.removeAll { $0 === item }
    }
}
public final class Item: Sendable {}
' > /tmp/crash.swift
swiftc -parse-as-library /tmp/crash.swift
```

## Crash Output

```
error: compile command failed due to signal 5 (use -v to see invocation)
Unhandled SIL Instruction:   %11 = init_existential_ref %6 : $Subscription : $Subscription, $AnyObject
Please submit a bug report (https://swift.org/contributing/#reporting-bugs) and include the crash backtrace.
Stack dump:
0.  Program arguments: swift-frontend ...
1.  Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
2.  Compiling with the current language version
3.  While evaluating request ExecuteSILPipelineRequest(...)
4.  While running pass #301 SILFunctionTransform "MoveOnlyTypeEliminator" on SILFunction "@$s...unsubscribe...".
 for expression at [...:11:33 - line:11:55] RangeText="{ $0 === subscription "
```

## Conditions Required

All three conditions must be present to trigger the crash:

| Condition | Description |
|-----------|-------------|
| 1. Actor method | Method declared on an actor type |
| 2. `borrowing` parameter | Parameter annotated with `borrowing` |
| 3. Closure capture | Parameter used inside a closure |

## Verified Test Results

| Test | Description | Result |
|------|-------------|--------|
| Without `borrowing` | Regular parameter in closure | Compiles |
| Without closure | `borrowing` parameter used directly | Compiles |
| Non-actor type | `borrowing` in struct method | Compiles |
| Actor + borrowing + closure | All three conditions | Crashes |

## Workaround

Remove the `borrowing` annotation:

```swift
public actor State {
    public var subscriptions: [Subscription] = []

    // Works without `borrowing`
    public func unsubscribe(_ subscription: Subscription) {
        subscriptions.removeAll { $0 === subscription }
    }
}
```

## Impact

This blocks adoption of Swift 6 ownership annotations in actor-based concurrent code where:
- Parameters are only read (ideal for `borrowing`)
- The parameter is used in a collection operation predicate (very common pattern)

This is a common pattern in reactive/async libraries managing subscriptions, observers, or callbacks.

## Analysis

The crash occurs in the `MoveOnlyTypeEliminator` SIL pass, suggesting the issue is related to how the compiler handles the combination of:
1. Actor isolation semantics
2. `borrowing` ownership semantics
3. Closure capture semantics

The compiler fails to handle `init_existential_ref` when the borrowed reference is captured by the closure predicate.
