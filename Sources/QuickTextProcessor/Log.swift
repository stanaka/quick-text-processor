import os

/// Capture diagnostics. Subsystem matches CFBundleIdentifier in
/// Support/Info.plist.
///
/// Every capture site logs at `notice` on purpose. `debug` and `info` are
/// memory-only and suppressed unless the stream is coaxed into showing them,
/// which made these lines effectively invisible in the field; `notice` is the
/// default level, so it needs no flags and is persisted to disk — meaning a
/// press that already happened can still be diagnosed after the fact:
///
///   log show --last 5m --predicate 'subsystem == "com.stanaka.QuickTextProcessor"'
///
/// or, to follow along live:
///
///   log stream --predicate 'subsystem == "com.stanaka.QuickTextProcessor"'
///
/// One line per hotkey press, so the volume does not justify a quieter level.
/// Never log captured text itself — lengths and bundle ids only.
enum Log {
    static let capture = Logger(subsystem: "com.stanaka.QuickTextProcessor",
                                category: "capture")
}
