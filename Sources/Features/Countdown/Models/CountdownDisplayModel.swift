import Foundation

/// A value snapshot for rendering; it does not retain the shared application model.
struct CountdownDisplayModel {
    var title = "Новых предсказаний пока нет"
    var counter = "00:00:00"
    var information = "Все назначенные даты прошли. Планета продолжает работу."
    var usesCountdown = true
}
