import SwiftUI
import AppKit

public struct MainView: View {
    @ObservedObject var sessionManager = SessionManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    public var body: some View {
        Group {
            if sessionManager.isShowingStartupSplash {
                // 1. 独立 Xcode 启动欢迎页面 (严格锁死 780x480)
                XcodeStartupWindowView()
                    .frame(width: 780, height: 480)
            } else {
                // 2. 正式运维主工作区 (放大版宽阔大视野 1180x720)
                NavigationSplitView(columnVisibility: $sessionManager.columnVisibility) {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
                        .background(.ultraThinMaterial)
                } detail: {
                    WorkspaceView()
                }
                .frame(minWidth: 960, minHeight: 600)
            }
        }
        .background(
            WindowAccessor { window in
                if window.delegate !== FullScreenWindowDelegate.shared {
                    window.delegate = FullScreenWindowDelegate.shared
                }

                if sessionManager.isShowingStartupSplash {
                    // 彻底禁止全屏与缩放
                    window.collectionBehavior.remove(.fullScreenPrimary)
                    window.collectionBehavior.remove(.fullScreenAuxiliary)
                    window.collectionBehavior.insert(.fullScreenNone)
                    window.collectionBehavior.insert(.fullScreenDisallowsTiling)
                    
                    window.styleMask.remove(.resizable)
                    window.styleMask.remove(.miniaturizable)
                    window.styleMask.insert(.closable)
                    window.styleMask.insert(.titled)
                    window.styleMask.insert(.fullSizeContentView)
                    
                    window.titleVisibility = .hidden
                    window.titlebarAppearsTransparent = true
                    window.showsToolbarButton = false
                    window.toolbar?.isVisible = false
                    window.showsResizeIndicator = false
                    
                    window.standardWindowButton(.closeButton)?.isHidden = false
                    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                    window.standardWindowButton(.zoomButton)?.isHidden = true
                    
                    window.minSize = NSSize(width: 780, height: 480)
                    window.maxSize = NSSize(width: 780, height: 480)
                    window.setContentSize(NSSize(width: 780, height: 480))
                    
                    window.isMovableByWindowBackground = true
                } else {
                    // 主页面：放大尺寸并恢复完整全屏和拉伸能力
                    window.collectionBehavior.remove(.fullScreenNone)
                    window.collectionBehavior.remove(.fullScreenDisallowsTiling)
                    window.collectionBehavior.insert(.fullScreenPrimary)
                    
                    window.standardWindowButton(.closeButton)?.isHidden = false
                    window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                    window.standardWindowButton(.zoomButton)?.isHidden = false
                    
                    window.styleMask.insert(.resizable)
                    window.styleMask.insert(.miniaturizable)
                    window.styleMask.insert(.closable)
                    window.showsResizeIndicator = true
                    
                    window.minSize = NSSize(width: 960, height: 600)
                    window.maxSize = NSSize(width: 10000, height: 10000)
                    
                    // 如果当前窗口尺寸还是小启动页的尺寸，平滑放大至宽广工作台
                    if window.frame.width < 960 || window.frame.height < 600 {
                        window.setContentSize(NSSize(width: 1180, height: 720))
                        window.center()
                    }
                    
                    window.titleVisibility = .visible
                    window.titlebarAppearsTransparent = false
                    window.showsToolbarButton = true
                    
                    if sessionManager.isFullScreen {
                        window.toolbar?.isVisible = false
                    } else {
                        window.toolbar?.isVisible = true
                    }
                }
            }
        )
        .animation(.easeInOut(duration: 0.20), value: sessionManager.isShowingStartupSplash)
        .sheet(isPresented: $settingsManager.isShowingSettingsSheet) {
            SettingsView()
        }
        .alert(
            loc.text("alert_title"),
            isPresented: Binding<Bool>(
                get: { sessionManager.alertMessage != nil },
                set: { if !$0 { sessionManager.alertMessage = nil } }
            ),
            actions: {
                Button(loc.text("ok"), role: .cancel) {
                    sessionManager.alertMessage = nil
                }
            },
            message: {
                Text(sessionManager.alertMessage ?? "")
            }
        )
    }
}
