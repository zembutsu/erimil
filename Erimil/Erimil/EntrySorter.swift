import Foundation

/// Layer 1 (Curator): pure-function entry sorting.
/// Reads no state; produces sorted output from input.
/// Viewer layer must NOT depend on this directly — sort is applied
/// at `listImageEntries()` time, before entries cross the firewall.
enum EntrySorter {

    /// Sort entries by the given mode and direction.
    ///
    /// - Note: `.custom` aliases to `.name` until #268 ships.
    ///   UI gating prevents `.custom` exposure (S129 D005), but this
    ///   defensive fallback runs regardless.
    /// - Note: Entries with `nil` `modifiedDate` always sort last,
    ///   regardless of ascending/descending. (S131 W4-A)
    static func sort(
        _ entries: [ImageEntry],
        by mode: SortMode,
        ascending: Bool
    ) -> [ImageEntry] {
        let effectiveMode: SortMode = (mode == .custom) ? .name : mode

        switch effectiveMode {
        case .name:
            return entries.sorted { a, b in
                ascending
                    ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                    : a.name.localizedStandardCompare(b.name) == .orderedDescending
            }

        case .date:
            return entries.sorted { a, b in
                switch (a.modifiedDate, b.modifiedDate) {
                case let (lhs?, rhs?):
                    return ascending ? lhs < rhs : lhs > rhs
                case (nil, _?):
                    return false  // nil sorts last
                case (_?, nil):
                    return true   // nil sorts last
                case (nil, nil):
                    // tiebreak by name to keep stable ordering
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }

        case .size:
            return entries.sorted { a, b in
                ascending ? a.size < b.size : a.size > b.size
            }

        case .custom:
            // unreachable due to effectiveMode mapping above, but
            // exhaustive switch requires it
            return entries
        }

        // Note: name uses `localizedStandardCompare` for natural sort
        // ("img2" < "img10"). size is byte-count compare. date uses
        // Date's native ordering.
    }
}
