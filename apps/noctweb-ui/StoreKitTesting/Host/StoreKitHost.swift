import SwiftUI
import NoctwebUI

@main
struct StoreKitHost: App {
    @StateObject private var support = AppSupportStore.shared
    var body: some Scene {
        WindowGroup { AppSupportCard().padding(24).frame(width: 540) }
    }
}
