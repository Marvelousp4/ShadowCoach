import SwiftUI

@main
struct ShadowCoachMobileApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var audio = AudioCoach()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(audio)
                .onAppear {
                    store.load()
                    audio.configureAudioSession()
                }
        }
    }
}
