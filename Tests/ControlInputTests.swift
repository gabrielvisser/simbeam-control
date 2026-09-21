// Standalone stdin contract test: no CoreSimulator, display, or input injection.
// swiftc Sources/ControlInput.swift Tests/ControlInputTests.swift -o /tmp/simbeam-input-tests
import Foundation

final class VideoEncoder {
  func requestKeyframe() {}
  func setBitrate(_ value: Int) {}
  func setFPS(_ value: Int) {}
}

final class HIDController {
  let results = Results()
  func toggleSoftwareKeyboard() { results.append("toggle") }
  func key(usage: UInt32, shift: Bool) { results.append("key:\(usage):\(shift)") }
  func tap(x: Double, y: Double) {}
  func touchDown(x: Double, y: Double) {}
  func touchMove(x: Double, y: Double) {}
  func touchUp(x: Double, y: Double) {}
  func swipe(x1: Double, y1: Double, x2: Double, y2: Double, durationMilliseconds: Int) {}
  func shake() {}
  func home() {}
  func appSwitcher() {}
}

enum Log {
  static let results = Results()
  static func message(_ text: String) { results.append(text) }
}

final class Results {
  private let lock = NSLock()
  private var values: [String] = []
  func append(_ value: String) {
    lock.lock()
    defer { lock.unlock() }
    values.append(value)
  }
  var snapshot: [String] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }
}

@main enum ControlInputTests {
  static func main() throws {
    let pipe = Pipe()
    precondition(dup2(pipe.fileHandleForReading.fileDescriptor, STDIN_FILENO) >= 0)
    let hid = HIDController()
    let finished = DispatchSemaphore(value: 0)
    let input = ControlInput(encoder: VideoEncoder(), hid: hid) { finished.signal() }
    input.start()
    try pipe.fileHandleForWriting.write(contentsOf: Data("{\"type\":\"toggle_software_".utf8))
    try pipe.fileHandleForWriting.write(contentsOf: Data("""
    keyboard"}
    {"type":"toggle_software_keyboard"}
    {"type":"hardware_keyboard","enabled":false}
    {"type":"unknown"}
    {"type":null}
    {"type":"key","usage":40,"shift":false}

    """.utf8))
    try pipe.fileHandleForWriting.close()
    precondition(finished.wait(timeout: .now() + 5) == .success, "stdin EOF timed out")
    withExtendedLifetime(input) {
      precondition(hid.results.snapshot == [
        "toggle", "toggle", "key:40:false",
      ], "wrong dispatch or implicit keyboard change at EOF: \(hid.results.snapshot)")
      precondition(Log.results.snapshot.count == 3, "unsupported commands must be rejected")
    }
    print("ControlInput: toggle dispatch, unsupported commands, framing, key regression, EOF passed")
  }
}
