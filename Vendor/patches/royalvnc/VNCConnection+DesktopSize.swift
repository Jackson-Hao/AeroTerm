#if canImport(FoundationEssentials)
import FoundationEssentials
#endif
import Foundation

extension VNCProtocol {
	struct SetDesktopSize: VNCSendableMessage {
		let messageType: UInt8 = 251

		let width: UInt16
		let height: UInt16
		let screens: [ScreenLayout]
	}

	struct ScreenLayout {
		let id: UInt32
		let xPosition: UInt16
		let yPosition: UInt16
		let width: UInt16
		let height: UInt16
		let flags: UInt32
	}
}

extension VNCProtocol.SetDesktopSize {
	var data: Data {
		var data = Data(capacity: 8 + screens.count * 16)

		data.append(messageType)
		data.appendPadding()
		data.append(width, bigEndian: true)
		data.append(height, bigEndian: true)
		data.append(UInt8(clamping: screens.count))
		data.appendPadding()

		for screen in screens {
			data.append(screen.id, bigEndian: true)
			data.append(screen.xPosition, bigEndian: true)
			data.append(screen.yPosition, bigEndian: true)
			data.append(screen.width, bigEndian: true)
			data.append(screen.height, bigEndian: true)
			data.append(screen.flags, bigEndian: true)
		}

		return data
	}

	func send(connection: NetworkConnectionWriting) async throws {
		try await connection.write(data: data)
	}
}

public extension VNCConnection {
	/// Ask the server to match this framebuffer size (Extended Desktop Size).
	@objc(vnc_requestDesktopSizeWithWidth:height:)
	func requestDesktopSize(width: UInt16, height: UInt16) {
		guard width > 0,
			  height > 0,
			  let framebuffer
		else {
			return
		}

		if framebuffer.size.width == width,
		   framebuffer.size.height == height {
			return
		}

		let primary = framebuffer.screens.first
		let screen = VNCProtocol.ScreenLayout(
			id: primary?.id ?? 0,
			xPosition: 0,
			yPosition: 0,
			width: width,
			height: height,
			flags: 0
		)

		enqueueClientToServerMessage(
			VNCProtocol.SetDesktopSize(
				width: width,
				height: height,
				screens: [screen]
			)
		)
	}
}

enum AeroVNCTune {
	static func compressionEncoding(for connection: VNCConnection) -> VNCEncodingType {
		let level = min(10, max(1, intValue(connection, key: "compressionLevel", fallback: 6)))
		return VNCEncodingType(rawValue: Int64(-256 + (level - 1)))
			?? VNCPseudoEncodingType.compressionLevel6.rawValue
	}

	static func jpegEncoding(for connection: VNCConnection) -> VNCEncodingType {
		let level = min(9, max(0, intValue(connection, key: "jpegQualityLevel", fallback: 6)))
		return VNCEncodingType(rawValue: Int64(-32 + level))
			?? VNCPseudoEncodingType.jpegQualityLevel6.rawValue
	}

	private static func intValue(_ connection: VNCConnection, key: String, fallback: Int) -> Int {
		guard let context = connection.context else { return fallback }
		let object = Unmanaged<AnyObject>.fromOpaque(context).takeUnretainedValue() as? NSObject
		if let value = object?.value(forKey: key) as? Int {
			return value
		}
		return fallback
	}
}

#if os(macOS)
import AppKit
import ObjectiveC

public extension VNCCAFramebufferView {
	private static var aeroIntervalKey: UInt8 = 0
	private static var aeroLastRenderKey: UInt8 = 0

	@objc(aeroSetMinimumFrameInterval:)
	func aeroSetMinimumFrameInterval(_ interval: TimeInterval) {
		objc_setAssociatedObject(
			self,
			&Self.aeroIntervalKey,
			interval,
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		)
	}

	func aeroShouldSkipRender() -> Bool {
		let interval = objc_getAssociatedObject(self, &Self.aeroIntervalKey) as? TimeInterval ?? 0
		guard interval > 0.001 else { return false }
		let now = ProcessInfo.processInfo.systemUptime
		let last = objc_getAssociatedObject(self, &Self.aeroLastRenderKey) as? TimeInterval ?? 0
		if now - last < interval {
			return true
		}
		objc_setAssociatedObject(
			self,
			&Self.aeroLastRenderKey,
			now,
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		)
		return false
	}
}
#endif
