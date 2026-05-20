import Foundation
import Combine

// Task 8 暫定エントリポイント。
// timelineUpdates を購読して変更通知の挙動を観察できるようにする。
// Task 10 で `@main` AppDelegate に差し替える。
let gw = EventKitGateway()
var cancellables = Set<AnyCancellable>()

gw.timelineUpdates
    .sink { tl in
        print("Update: \(tl.events.count) events at \(tl.date)")
    }
    .store(in: &cancellables)

Task {
    let result = await gw.requestAccess()
    print("Access: \(result)")
    gw.start()
    // しばらく走らせて変更通知の挙動を観察できるようにする
}

RunLoop.main.run()
