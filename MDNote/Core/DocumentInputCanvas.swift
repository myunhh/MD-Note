import UIKit
import PencilKit

/// In text mode the sibling web view receives selection/IME touches. The same
/// canvas retains its drawing, content offset and zoom throughout mode changes.
final class DocumentInputCanvas: PKCanvasView {
    var textInputActive = false

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !textInputActive && super.point(inside: point, with: event)
    }
}
