import ApplicationServices

/// Reading an app's accessibility tree. Every attribute read is an IPC call to the
/// target app, so walks are budgeted and belong off the main actor.
enum AccessibilityTree {
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
            let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    /// Depth-first walk from `root` that visits at most `budget` elements, no deeper
    /// than `maxDepth`. `visit` returns `true` to stop early; so does this.
    @discardableResult
    static func walk(
        from root: AXUIElement,
        maxDepth: Int,
        budget: Int,
        visit: (AXUIElement) -> Bool
    ) -> Bool {
        var remaining = budget
        return walk(root, depth: 0, maxDepth: maxDepth, remaining: &remaining, visit: visit)
    }

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        remaining: inout Int,
        visit: (AXUIElement) -> Bool
    ) -> Bool {
        guard depth < maxDepth, remaining > 0 else { return false }
        remaining -= 1

        if visit(element) { return true }
        for child in children(element) {
            if walk(child, depth: depth + 1, maxDepth: maxDepth, remaining: &remaining, visit: visit) {
                return true
            }
        }
        return false
    }
}
