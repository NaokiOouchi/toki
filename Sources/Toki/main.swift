import Foundation

// Task 6 暫定エントリポイント。
// Task 10 で `@main` AppDelegate に差し替える。
let gw = EventKitGateway()

Task {
    let result = await gw.requestAccess()
    print("Access: \(result)")
    let tl = await gw.fetchTodayTimeline()
    print("Timeline events: \(tl.events.count)")
    exit(0)
}

RunLoop.main.run()
