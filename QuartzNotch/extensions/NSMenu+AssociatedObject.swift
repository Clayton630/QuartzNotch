
import AppKit

private final class MenuActionBox: NSObject {
    let target: AnyObject
    init(target: AnyObject) { self.target = target }
}

extension NSMenu {
    private static let retainedAction = AssociatedObject<MenuActionBox>()

    func retainActionTarget(_ target: AnyObject) {
        NSMenu.retainedAction[self] = MenuActionBox(target: target)
    }
}
