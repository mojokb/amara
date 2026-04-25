import Foundation

extension Amara {
    /// This is a delegate that should be applied to your global app delegate for AmaraKit
    /// to perform app-global operations.
    protocol Delegate {
        /// Look up a surface within the application by ID.
        func ghosttySurface(id: UUID) -> SurfaceView?
    }
}
