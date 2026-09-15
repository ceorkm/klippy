import Foundation

/// Swallows `print` in release builds.
///
/// Klippy polls the pasteboard ten times a second and the capture path is
/// chatty, so shipping those calls means constant writes to the system log for
/// no one's benefit. Overloading `print` at module scope turns every existing
/// call into a no-op when DEBUG is off, which beats editing a hundred call
/// sites and beats hoping nobody adds a bare `print` later.
///
/// Swift prefers a module's own overload over the standard library's, so this
/// applies to the whole target automatically.
@inlinable
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    Swift.print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
    #endif
}
