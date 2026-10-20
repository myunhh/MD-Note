import PencilKit
import CryptoKit

enum InkStrokeIdentity {
    static func fingerprint(_ stroke: PKStroke) -> Data {
        var bytes = Data(stroke.ink.inkType.rawValue.utf8)
        func append(_ number: Double) {
            var value = number.bitPattern.bigEndian
            withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
        }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        [red, green, blue, alpha].forEach { append(Double($0)) }
        append(stroke.path.creationDate.timeIntervalSinceReferenceDate)
        let transform = stroke.transform
        [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].forEach { append(Double($0)) }
        for point in stroke.path {
            append(Double(point.location.x)); append(Double(point.location.y))
            append(point.timeOffset)
            append(Double(point.size.width)); append(Double(point.size.height))
            append(Double(point.opacity)); append(Double(point.force))
            append(Double(point.azimuth)); append(Double(point.altitude))
        }
        stroke.mask?.cgPath.applyWithBlock { pointer in
            let element = pointer.pointee
            append(Double(element.type.rawValue))
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            for index in 0..<count {
                append(Double(element.points[index].x))
                append(Double(element.points[index].y))
            }
        }
        return Data(SHA256.hash(data: bytes))
    }
}
