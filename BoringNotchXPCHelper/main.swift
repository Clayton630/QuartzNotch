import Foundation

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedObject = BoringNotchXPCHelper()
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: (any BoringNotchXPCHelperProtocol).self)
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
