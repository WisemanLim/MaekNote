import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // VOX 미니 플레이어 창과 같은 크기(322×574pt, 제목줄 포함)로 시작
    let voxSize = NSSize(width: 322, height: 574)
    var windowFrame = self.frame
    windowFrame.origin.y += windowFrame.size.height - voxSize.height
    windowFrame.size = voxSize
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 322, height: 480)
    // 이전 실행의 창 크기를 macOS 가 복원하지 않도록 (항상 VOX 크기로 시작)
    self.isRestorable = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
