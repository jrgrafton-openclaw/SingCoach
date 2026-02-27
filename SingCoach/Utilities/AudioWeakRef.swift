/// A nonisolated weak-reference box for use in audio thread callbacks.
///
/// **Why this exists:**
/// On iOS 26+ with Swift 6, the compiler injects actor-isolation assertions at the point
/// a closure *captures* a `@MainActor`-isolated type — even as `[weak self]`. When that
/// closure is created or invoked on an audio thread (AVAudioTap, AVAudioSourceNode render
/// block, AURemoteIO IOThread), `_swift_task_checkIsolatedSwift` fires, which calls
/// `dispatch_assert_queue_fail` → `EXC_BREAKPOINT` crash.
///
/// **Fix:** wrap `self` (a `@MainActor` type) in `AudioWeakRef(self)` *before* the closure.
/// The closure captures only the plain nonisolated `AudioWeakRef`, which carries no actor
/// annotation. Then hop to `DispatchQueue.main.async` (never `Task { @MainActor }`) for
/// any work that must run on the main actor.
///
/// **Usage:**
/// ```swift
/// let ref = AudioWeakRef(self)
/// audioInput.installTap(...) { buffer, _ in
///     // Safe: no @MainActor type captured here
///     let samples = ...
///     DispatchQueue.main.async { ref.value?.handleSamples(samples) }
/// }
/// ```
// @unchecked Sendable: this type is deliberately designed to cross thread boundaries safely.
// `value` is weak — the referent is never mutated via this box; all mutations happen on
// @MainActor after the DispatchQueue.main.async hop.
final class AudioWeakRef<T: AnyObject>: @unchecked Sendable {
    private(set) weak var value: T?

    init(_ value: T) {
        self.value = value
    }
}
