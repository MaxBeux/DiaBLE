import Foundation
import CoreBluetooth


struct BLE {

    static let knownDevices: [Device.Type] = DeviceType.allCases.filter{ $0.id != "none" }.map{ ($0.type as! Device.Type) }
    static let knownDevicesIds: [String]   = DeviceType.allCases.filter{ $0.id != "none" }.map{ $0.id }

    enum UUID: String, CustomStringConvertible, CaseIterable {

        case device         = "180A"
        case systemID       = "2A23"
        case model          = "2A24"
        case serial         = "2A25"
        case firmware       = "2A26"
        case hardware       = "2A27"
        case software       = "2A28"
        case manufacturer   = "2A29"
        // Libre 2
        case regulatory     = "2A2A"
        case pnpID          = "2A50"

        case battery        = "180F"
        case batteryLevel   = "2A19"

        case time           = "1805"
        case currentTime    = "2A2B"
        case localTime      = "2A0F"

        case configuration  = "2902"
        case dfu            = "FE59"

        // Mi Band
        case immediateAlert = "1802"
        case alert          = "1811"
        case heartRate      = "180D"

        // Apple
        case nearby         = "9FA480E0-4967-4542-9390-D343DC5D04AE"
        case nearby1        = "AF0BADB1-5B99-43CD-917A-A77BC549E3CC"

        case continuity     = "D0611E78-BBB4-4591-A5F8-487910AE4366"
        case continuity1    = "8667556C-9A37-4C91-84ED-54EE27D90049"


        var description: String {
            switch self {
            case .device:         return "device information"
            case .systemID:       return "system id"
            case .model:          return "model number"
            case .serial:         return "serial number"
            case .firmware:       return "firmware version"
            case .hardware:       return "hardware revision"
            case .software:       return "software revision"
            case .manufacturer:   return "manufacturer"
            case .regulatory:     return "regulatory certification data list"
            case .pnpID:          return "pnp id"
            case .battery:        return "battery"
            case .batteryLevel:   return "battery level"
            case .time:           return "time"
            case .currentTime:    return "current time"
            case .localTime:      return "local time information"
            case .dfu:            return "device firmware update"
            case .configuration:  return "configuration descriptor"
            case .immediateAlert: return "immediate alert"
            case .alert:          return "alert notification"
            case .heartRate:      return "heart rate"
            case .nearby:         return "nearby"
            case .nearby1:        return "nearby"
            case .continuity:     return "continuity"
            case .continuity1:    return "continuity"
            }
        }
    }


    struct Company: Codable {
        let code: Int
        let name: String
    }

    static let companies = try! JSONDecoder().decode(Array<BLE.Company>.self, from: Data(contentsOf: Bundle.main.url(forResource: "company_ids", withExtension: "json")!))
}


extension CBCharacteristicProperties: CustomStringConvertible {
    public var description: String {
        var d = [String: Bool]()
        d["Broadcast"]                  = self.contains(.broadcast)
        d["Read"]                       = self.contains(.read)
        d["WriteWithoutResponse"]       = self.contains(.writeWithoutResponse)
        d["Write"]                      = self.contains(.write)
        d["Notify"]                     = self.contains(.notify)
        d["Indicate"]                   = self.contains(.indicate)
        d["AuthenticatedSignedWrites"]  = self.contains(.authenticatedSignedWrites)
        d["ExtendedProperties"]         = self.contains(.extendedProperties)
        d["NotifyEncryptionRequired"]   = self.contains(.notifyEncryptionRequired)
        d["IndicateEncryptionRequired"] = self.contains(.indicateEncryptionRequired)
        return "\(d.filter{$1}.keys)"
    }
}
