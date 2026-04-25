import AppKit

// MARK: Amara Delegate

/// This implements the Amara app delegate protocol which is used by the Amara
/// APIs for app-global information.
extension AppDelegate: Amara.Delegate {
    func ghosttySurface(id: UUID) -> Amara.SurfaceView? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            for surface in controller.surfaceTree where surface.id == id {
                return surface
            }
        }

        return nil
    }
}
