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

### Why This Code Should Compile

The code is semantically valid and should be accepted by the compiler:

1. **`borrowing` on reference types is valid**: `Subscription` is a class (reference type). A `borrowing Subscription` parameter means "this function may read the reference; it will not consume/move it." This is a valid and common ownership annotation for read-only parameters.

2. **Non-escaping closure capture is allowed**: The closure passed to `removeAll` is non-escaping (evaluated synchronously during the call). Capturing a borrowed parameter in a non-escaping closure is semantically straightforward: the compiler can keep the borrow alive for the duration of the call, or materialize an owned copy of the reference if needed.

3. **Actor isolation doesn't change validity**: `unsubscribe` runs on the actor, and the `removeAll` predicate closure executes within that synchronous call on the actor as well.

There is no language-level rule that makes this pattern invalid.

### Why This Is a Compiler Bug

- A compiler crash (signal 5) during SIL processing is always a bug. A valid compiler must either emit an error or accept the program — it must not crash.
- The minimal reproducer isolates the trigger to the combination of: actor method + `borrowing` parameter + closure capture. Removing any one condition avoids the crash, which is the signature of a compiler defect.

### Technical Details

The crash occurs in the `MoveOnlyTypeEliminator` SIL pass when the compiler attempts to handle `init_existential_ref` for the borrowed reference captured by the closure predicate.

## Related Issues

This issue appears to be novel. Related but distinct issues:

| Issue | Description | Difference |
|-------|-------------|------------|
| [#85275](https://github.com/swiftlang/swift/issues/85275) | `~Copyable`/`~Escapable` crash with `borrowing` and closure capture | Involves noncopyable types; this bug uses regular `Sendable` class |
| [#69252](https://github.com/swiftlang/swift/issues/69252) | `borrowing` on String causes "Copy of noncopyable typed value" error | Different error message; closed |
| [#84568](https://github.com/swiftlang/swift/issues/84568) | Crash with `borrowing` in variadic generic closures | Different context (pack expansion crash) |
| [#76804](https://github.com/swiftlang/swift/issues/76804) | Actor executor assumption crash with closures | Actor + closure, but no `borrowing` keyword |

**Key differentiators of this bug:**
1. Crashes specifically in `MoveOnlyTypeEliminator` SIL pass
2. Involves `init_existential_ref` instruction failure
3. Triggered by `borrowing` on a **reference type** (class) parameter
4. Occurs in actor method context with closure predicate capture
