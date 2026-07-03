import Foundation

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedObject = QuartzNotchXPCHelper()
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: (any QuartzNotchXPCHelperProtocol).self)
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
