import CoreGraphics
import Foundation
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l { let n = w["kCGWindowOwnerName"] as? String ?? ""; if n.lowercased().contains("vermintide") || n.lowercased().contains("wine") { print(w["kCGWindowNumber"] ?? 0, n, w["kCGWindowName"] ?? "", w["kCGWindowBounds"] ?? "", "layer", w["kCGWindowLayer"] ?? "") } }
