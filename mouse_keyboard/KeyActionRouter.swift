import CoreGraphics

final class KeyActionRouter {
    enum QuickRegion {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    enum KeyDownAction {
        case toggleMode
        case exitMode
        case startMove(MouseMovementEngine.Direction)
        case setBoost(Bool)
        case setFineTune(Bool)
        case scrollDown
        case scrollUp
        case leftClick
        case rightClick
        case quickRegion(QuickRegion)
        case displaySlot(Int)
    }

    enum KeyUpAction {
        case consumeGlobal
        case stopMove(MouseMovementEngine.Direction)
        case setBoost(Bool)
        case setFineTune(Bool)
        case consumeInControlMode
    }

    func keyDownAction(for keyCode: CGKeyCode) -> KeyDownAction? {
        switch keyCode {
        case 100: return .toggleMode                           // F8
        case 53: return .exitMode                             // Esc
        case 13: return .startMove(.up)                       // W
        case 1: return .startMove(.down)                      // S
        case 0: return .startMove(.left)                      // A
        case 2: return .startMove(.right)                     // D
        case 16: return .setBoost(true)                       // Y
        case 4: return .setFineTune(true)                     // H
        case 38: return .scrollDown                           // J
        case 40: return .scrollUp                             // K
        case 34: return .leftClick                            // I
        case 31: return .rightClick                           // O
        case 27: return .quickRegion(.topLeft)               // -
        case 24: return .quickRegion(.topRight)              // =
        case 33: return .quickRegion(.bottomLeft)            // [
        case 30: return .quickRegion(.bottomRight)           // ]
        case 18: return .displaySlot(1)                      // 1
        case 19: return .displaySlot(2)                      // 2
        case 20: return .displaySlot(3)                      // 3
        default: return nil
        }
    }

    func keyUpAction(for keyCode: CGKeyCode) -> KeyUpAction? {
        switch keyCode {
        case 100: return .consumeGlobal                       // F8
        case 13: return .stopMove(.up)                        // W
        case 1: return .stopMove(.down)                       // S
        case 0: return .stopMove(.left)                       // A
        case 2: return .stopMove(.right)                      // D
        case 16: return .setBoost(false)                      // Y
        case 4: return .setFineTune(false)                    // H
        case 38, 40, 27, 24, 33, 30, 18, 19, 20, 34, 31, 53:
            return .consumeInControlMode
        default:
            return nil
        }
    }
}
