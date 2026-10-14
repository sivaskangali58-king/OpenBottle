#if os(macOS)
import SwiftUI

@main
struct OpenBottleApp: App {
    var body: some Scene {
        WindowGroup("OpenBottle") {
            MainView()
                .frame(minWidth: 1050, minHeight: 690)
        }
        .windowStyle(.titleBar)
    }
}
#else
@main
enum UnsupportedPlatform {
    static func main() { print("OpenBottle arayüzü yalnızca macOS üzerinde çalışır.") }
}
#endif
