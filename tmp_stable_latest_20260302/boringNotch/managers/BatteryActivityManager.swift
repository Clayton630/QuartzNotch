import Foundation
import IOKit.ps

/// Manages and monitors battery status changes on the device
/// - Note: This class uses the IOKit framework to monitor battery status
class BatteryActivityManager {

    static let shared = BatteryActivityManager()

    var onBatteryLevelChange: ((Float) -> Void)?
    var onMaxCapacityChange: ((Float) -> Void)?
    var onPowerModeChange: ((Bool) -> Void)?
    var onPowerSourceChange: ((Bool) -> Void)?
    var onChargingChange: ((Bool) -> Void)?
    var onTimeToFullChargeChange: ((Int) -> Void)?

    private var batterySource: CFRunLoopSource?
    private var observers: [(BatteryEvent) -> Void] = []
    private var previousBatteryInfo: BatteryInfo?

  // Coalesce rapid IOKit changes into a single, short burst of events.
  // This keeps UI state fresh without introducing visible 1s-per-event lag.
    private var pendingEvents: [String: BatteryEvent] = [:]
    private var flushWorkItem: DispatchWorkItem?
    private let coalesceInterval: TimeInterval = 0.12

    enum BatteryEvent {
        case powerSourceChanged(isPluggedIn: Bool)
        case batteryLevelChanged(level: Float)
        case lowPowerModeChanged(isEnabled: Bool)
        case isChargingChanged(isCharging: Bool)
        case timeToFullChargeChanged(time: Int)
        case maxCapacityChanged(capacity: Float)
        case error(description: String)
    }

    enum BatteryError: Error {
        case powerSourceUnavailable
        case batteryInfoUnavailable(String)
        case batteryParameterMissing(String)
    }

    private let defaultBatteryInfo = BatteryInfo(
        isPluggedIn: false,
        isCharging: false,
        currentCapacity: 0,
        maxCapacity: 0,
        isInLowPowerMode: false,
        timeToFullCharge: 0
    )

    private init() {
        startMonitoring()
        setupLowPowerModeObserver()
    }
    
  /// Setup observer for low power mode changes
    private func setupLowPowerModeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lowPowerModeChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

  /// Called when low power mode is enabled or disabled
    @objc private func lowPowerModeChanged() {
        notifyBatteryChanges()
    }
    
  /// Starts monitoring battery changes
    private func startMonitoring() {
        guard let powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let manager = Unmanaged<BatteryActivityManager>.fromOpaque(context).takeUnretainedValue()
            manager.notifyBatteryChanges()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() else {
            return
        }
        batterySource = powerSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), powerSource, .defaultMode)
    }

  /// Stops monitoring battery changes
    private func stopMonitoring() {
        if let powerSource = batterySource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), powerSource, .defaultMode)
            batterySource = nil
        }
    }

  /// Checks for changes in a property and notifies observers
    private func checkAndNotify<T: Equatable>(
        previous: T, 
        current: T, 
        eventGenerator: (T) -> BatteryEvent
    ) {
        if previous != current {
            enqueueNotification(eventGenerator(current))
        }
    }
    
  /// Notifies the observers of battery changes
  /// Checks for changes in battery status and notifies observers
    private func notifyBatteryChanges() {
        let batteryInfo = getBatteryInfo()
        
    // Check for changes
        if let previousInfo = previousBatteryInfo {
      // Use the helper function for each property.
            checkAndNotify(
                previous: previousInfo.isPluggedIn,
                current: batteryInfo.isPluggedIn,
                eventGenerator: { .powerSourceChanged(isPluggedIn: $0) }
            )
            
            checkAndNotify(
                previous: previousInfo.currentCapacity,
                current: batteryInfo.currentCapacity,
                eventGenerator: { .batteryLevelChanged(level: $0) }
            )
            
            checkAndNotify(
                previous: previousInfo.isCharging,
                current: batteryInfo.isCharging,
                eventGenerator: { .isChargingChanged(isCharging: $0) }
            )
            
            checkAndNotify(
                previous: previousInfo.isInLowPowerMode,
                current: batteryInfo.isInLowPowerMode,
                eventGenerator: { .lowPowerModeChanged(isEnabled: $0) }
            )
            
            checkAndNotify(
                previous: previousInfo.timeToFullCharge,
                current: batteryInfo.timeToFullCharge,
                eventGenerator: { .timeToFullChargeChanged(time: $0) }
            )
            
            checkAndNotify(
                previous: previousInfo.maxCapacity,
                current: batteryInfo.maxCapacity,
                eventGenerator: { .maxCapacityChanged(capacity: $0) }
            )
        } else {
      // First time notification
            enqueueNotification(.powerSourceChanged(isPluggedIn: batteryInfo.isPluggedIn))
            enqueueNotification(.batteryLevelChanged(level: batteryInfo.currentCapacity))
            enqueueNotification(.isChargingChanged(isCharging: batteryInfo.isCharging))
            enqueueNotification(.lowPowerModeChanged(isEnabled: batteryInfo.isInLowPowerMode))
            enqueueNotification(.timeToFullChargeChanged(time: batteryInfo.timeToFullCharge))
            enqueueNotification(.maxCapacityChanged(capacity: batteryInfo.maxCapacity))
        }

    // Update previous battery info
        previousBatteryInfo = batteryInfo

    // Trigger optional callbacks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onBatteryLevelChange?(batteryInfo.currentCapacity)
            self.onPowerSourceChange?(batteryInfo.isPluggedIn)
            self.onChargingChange?(batteryInfo.isCharging)
            self.onPowerModeChange?(batteryInfo.isInLowPowerMode)
            self.onTimeToFullChargeChange?(batteryInfo.timeToFullCharge)
            self.onMaxCapacityChange?(batteryInfo.maxCapacity)
        }
    }

  /// Enqueues a battery event.
  ///
  /// Historically this used a 1s-per-event serial queue, which made the battery live activity
  /// feel "late" (content arriving after the notch animation) and caused extra layout reflows.
  ///
  /// We now coalesce events over a short window and then flush them in a deterministic order.
    private func enqueueNotification(_ event: BatteryEvent) {
    // Power source changes should be delivered immediately (they drive the live activity trigger).
        if case .powerSourceChanged = event {
            notifyObservers(event: event)
            return
        }

    // Errors should not be delayed/coalesced.
        if case .error = event {
            notifyObservers(event: event)
            return
        }

        pendingEvents[eventKey(for: event)] = event
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushWorkItem == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            self?.flushPendingEvents()
        }
        flushWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + coalesceInterval, execute: item)
    }

    private func flushPendingEvents() {
        flushWorkItem?.cancel()
        flushWorkItem = nil

        let events = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)

    // Deterministic order: state first, then derived values.
        let order: [String] = [
            "isCharging",
            "batteryLevel",
            "maxCapacity",
            "timeToFullCharge",
            "lowPower"
        ]

        for key in order {
            if let e = events[key] {
                notifyObservers(event: e)
            }
        }
    }

    private func eventKey(for event: BatteryEvent) -> String {
        switch event {
        case .powerSourceChanged:
            return "powerSource"
        case .batteryLevelChanged:
            return "batteryLevel"
        case .lowPowerModeChanged:
            return "lowPower"
        case .isChargingChanged:
            return "isCharging"
        case .timeToFullChargeChanged:
            return "timeToFullCharge"
        case .maxCapacityChanged:
            return "maxCapacity"
        case .error:
            return "error"
        }
    }

  /// Initializes the battery information when the manager starts
  /// - Returns: Current battery information
    func initializeBatteryInfo() -> BatteryInfo {
        previousBatteryInfo = getBatteryInfo()
        guard let batteryInfo = previousBatteryInfo else {
            return BatteryInfo(
                isPluggedIn: false,
                isCharging: false,
                currentCapacity: 0,
                maxCapacity: 0,
                isInLowPowerMode: false,
                timeToFullCharge: 0
            )
        }
        return batteryInfo
    }

  /// Returns a fresh snapshot of the current battery information.
  ///
  /// Use this when you need the *current* values immediately (e.g. right before
  /// triggering a live activity animation), rather than waiting for coalesced events.
    func currentBatteryInfo() -> BatteryInfo {
        getBatteryInfo()
    }

  /// Get the current battery information
  /// - Returns: The current battery information
    private func getBatteryInfo() -> BatteryInfo {
        do {
      // Get power source information
            guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
                throw BatteryError.powerSourceUnavailable
            }
            
            guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
                !sources.isEmpty else {
                throw BatteryError.batteryInfoUnavailable("No power sources available")
            }
            
            let source = sources.first!
            
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                throw BatteryError.batteryInfoUnavailable("Could not get power source description")
            }
            
      // Extract required battery parameters with error handling
            guard let currentCapacity = description[kIOPSCurrentCapacityKey] as? Float else {
                throw BatteryError.batteryParameterMissing("Current capacity")
            }
            
            guard let maxCapacity = description[kIOPSMaxCapacityKey] as? Float else {
                throw BatteryError.batteryParameterMissing("Max capacity")
            }
            
            guard let isCharging = description["Is Charging"] as? Bool else {
                throw BatteryError.batteryParameterMissing("Charging state")
            }
            
            guard let powerSource = description[kIOPSPowerSourceStateKey] as? String else {
                throw BatteryError.batteryParameterMissing("Power source state")
            }
            
      // Create battery info with the extracted parameters
            var batteryInfo = BatteryInfo(
                isPluggedIn: powerSource == kIOPSACPowerValue,
                isCharging: isCharging,
                currentCapacity: currentCapacity,
                maxCapacity: maxCapacity,
                isInLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                timeToFullCharge: 0
            )
            
      // Optional parameters
            if let timeToFullCharge = description[kIOPSTimeToFullChargeKey] as? Int {
                batteryInfo.timeToFullCharge = timeToFullCharge
            }
            
            return batteryInfo
            
        } catch BatteryError.powerSourceUnavailable {
            print("[WARN] Error: Power source information unavailable")
            return defaultBatteryInfo
        } catch BatteryError.batteryInfoUnavailable(let reason) {
            print("[WARN] Error: Battery information unavailable - \(reason)")
            return defaultBatteryInfo
        } catch BatteryError.batteryParameterMissing(let parameter) {
            print("[WARN] Error: Battery parameter missing - \(parameter)")
            return defaultBatteryInfo
        } catch {
            print("[WARN] Error: Unexpected error getting battery info - \(error.localizedDescription)")
            return defaultBatteryInfo
        }
    }
    
  /// Adds an observer to listen to battery changes
  /// - Parameter observer: The observer closure to be called on battery events
  /// - Returns: The ID of the observer for later removal
    func addObserver(_ observer: @escaping (BatteryEvent) -> Void) -> Int {
        observers.append(observer)
        return observers.count - 1
    }

  /// Removes an observer by its ID
  /// - Parameter id: The ID of the observer to be removed
    func removeObserver(byId id: Int) {
        guard id >= 0 && id < observers.count else { return }
        observers.remove(at: id)
    }
    
  /// Notifies all observers of a battery event
  /// - Parameter event: The battery event to notify
    private func notifyObservers(event: BatteryEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for observer in self.observers {
                observer(event)
            }
        }
    }
    
    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
}

/// Struct to hold battery information
struct BatteryInfo {
    var isPluggedIn: Bool
    var isCharging: Bool
    var currentCapacity: Float
    var maxCapacity: Float
    var isInLowPowerMode: Bool
    var timeToFullCharge: Int
}
