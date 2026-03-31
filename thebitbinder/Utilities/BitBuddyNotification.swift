import Foundation

extension Notification.Name {
    static let jokeDatabaseDidChange = Notification.Name("JokeDatabaseDidChange")
    /// Published by BitBuddyService when an add_joke action is dispatched.
    /// userInfo keys: "jokeText" (String), "folder" (String?, optional).
    static let bitBuddyAddJoke = Notification.Name("BitBuddyAddJoke")
}
