import Foundation

// FSRS-6 equations and state transitions follow Open Spaced Repetition's
// published specification and py-fsrs reference implementation (MIT).

enum ReviewRating: Int, CaseIterable, Codable, Identifiable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    var recallDescription: String {
        switch self {
        case .again: return "Forgot"
        case .hard: return "Recalled with effort"
        case .good: return "Recalled"
        case .easy: return "Immediate recall"
        }
    }
}

enum ReviewLearningState: String, Codable, Hashable {
    case learning
    case review
    case relearning
}

struct FSRSReviewCard: Codable, Hashable {
    var state: ReviewLearningState = .learning
    var step: Int? = 0
    var stability: Double?
    var difficulty: Double?
    var due: Date = Date()
    var lastReview: Date?
    var reviewCount = 0
    var lapseCount = 0
}

struct ReviewEvent: Codable, Hashable {
    let reviewedAt: Date
    let rating: ReviewRating
    let elapsedDays: Int
    let scheduledInterval: TimeInterval
}

struct SentenceReviewProgress: Codable, Hashable {
    var card: FSRSReviewCard = FSRSReviewCard()
    var history: [ReviewEvent] = []
}

struct FSRSReviewResult: Hashable {
    let card: FSRSReviewCard
    let event: ReviewEvent
}

struct FSRS6Scheduler {
    // Official FSRS-6 defaults. Custom weights should come from enough review data.
    static let defaultParameters: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194,
        0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629,
        1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542
    ]

    let desiredRetention: Double
    let maximumIntervalDays: Int
    let learningSteps: [TimeInterval]
    let relearningSteps: [TimeInterval]
    let parameters: [Double]

    init(
        desiredRetention: Double = 0.9,
        maximumIntervalDays: Int = 36_500,
        learningSteps: [TimeInterval] = [60, 600],
        relearningSteps: [TimeInterval] = [600],
        parameters: [Double] = FSRS6Scheduler.defaultParameters
    ) {
        self.desiredRetention = min(max(desiredRetention, 0.7), 0.99)
        self.maximumIntervalDays = max(1, maximumIntervalDays)
        self.learningSteps = learningSteps.filter { $0 > 0 }
        self.relearningSteps = relearningSteps.filter { $0 > 0 }
        self.parameters = parameters.count == 21 ? parameters : Self.defaultParameters
    }

    func schedule(
        card originalCard: FSRSReviewCard,
        rating: ReviewRating,
        at reviewDate: Date = Date()
    ) -> FSRSReviewResult {
        var card = originalCard
        let previousState = card.state
        let elapsedDays = wholeDays(from: card.lastReview, to: reviewDate)
        let nextInterval: TimeInterval

        switch card.state {
        case .learning:
            updateMemory(card: &card, rating: rating, elapsedDays: elapsedDays, at: reviewDate)
            nextInterval = scheduleLearning(card: &card, rating: rating)
        case .review:
            updateMemory(card: &card, rating: rating, elapsedDays: elapsedDays, at: reviewDate)
            if rating == .again, let firstStep = relearningSteps.first {
                card.state = .relearning
                card.step = 0
                nextInterval = firstStep
            } else {
                card.state = .review
                card.step = nil
                nextInterval = dayInterval(for: card.stability)
            }
        case .relearning:
            updateMemory(card: &card, rating: rating, elapsedDays: elapsedDays, at: reviewDate)
            nextInterval = scheduleRelearning(card: &card, rating: rating)
        }

        card.due = reviewDate.addingTimeInterval(nextInterval)
        card.lastReview = reviewDate
        card.reviewCount += 1
        if previousState == .review, rating == .again {
            card.lapseCount += 1
        }

        return FSRSReviewResult(
            card: card,
            event: ReviewEvent(
                reviewedAt: reviewDate,
                rating: rating,
                elapsedDays: elapsedDays ?? 0,
                scheduledInterval: nextInterval
            )
        )
    }

    func retrievability(of card: FSRSReviewCard, at date: Date = Date()) -> Double? {
        guard let stability = card.stability, stability > 0, card.lastReview != nil else {
            return nil
        }
        let elapsedDays = Double(wholeDays(from: card.lastReview, to: date) ?? 0)
        return pow(1 + factor * elapsedDays / stability, decay)
    }

    private var decay: Double { -parameters[20] }

    private var factor: Double {
        pow(0.9, 1 / decay) - 1
    }

    private func updateMemory(
        card: inout FSRSReviewCard,
        rating: ReviewRating,
        elapsedDays: Int?,
        at reviewDate: Date
    ) {
        guard let stability = card.stability, let difficulty = card.difficulty else {
            card.stability = initialStability(for: rating)
            card.difficulty = initialDifficulty(for: rating, clamp: true)
            return
        }

        if let elapsedDays, elapsedDays < 1 {
            card.stability = shortTermStability(stability: stability, rating: rating)
        } else {
            let retrievability = retrievability(of: card, at: reviewDate) ?? 0
            card.stability = nextStability(
                difficulty: difficulty,
                stability: stability,
                retrievability: retrievability,
                rating: rating
            )
        }
        card.difficulty = nextDifficulty(difficulty: difficulty, rating: rating)
    }

    private func scheduleLearning(card: inout FSRSReviewCard, rating: ReviewRating) -> TimeInterval {
        let step = card.step ?? 0
        if learningSteps.isEmpty || (step >= learningSteps.count && rating != .again) {
            card.state = .review
            card.step = nil
            return dayInterval(for: card.stability)
        }

        switch rating {
        case .again:
            card.step = 0
            return learningSteps[0]
        case .hard:
            if step == 0, learningSteps.count == 1 {
                return learningSteps[0] * 1.5
            }
            if step == 0, learningSteps.count >= 2 {
                return (learningSteps[0] + learningSteps[1]) / 2
            }
            return learningSteps[step]
        case .good:
            if step + 1 == learningSteps.count {
                card.state = .review
                card.step = nil
                return dayInterval(for: card.stability)
            }
            card.step = step + 1
            return learningSteps[step + 1]
        case .easy:
            card.state = .review
            card.step = nil
            return dayInterval(for: card.stability)
        }
    }

    private func scheduleRelearning(card: inout FSRSReviewCard, rating: ReviewRating) -> TimeInterval {
        let step = card.step ?? 0
        if relearningSteps.isEmpty || (step >= relearningSteps.count && rating != .again) {
            card.state = .review
            card.step = nil
            return dayInterval(for: card.stability)
        }

        switch rating {
        case .again:
            card.step = 0
            return relearningSteps[0]
        case .hard:
            if step == 0, relearningSteps.count == 1 {
                return relearningSteps[0] * 1.5
            }
            if step == 0, relearningSteps.count >= 2 {
                return (relearningSteps[0] + relearningSteps[1]) / 2
            }
            return relearningSteps[step]
        case .good:
            if step + 1 == relearningSteps.count {
                card.state = .review
                card.step = nil
                return dayInterval(for: card.stability)
            }
            card.step = step + 1
            return relearningSteps[step + 1]
        case .easy:
            card.state = .review
            card.step = nil
            return dayInterval(for: card.stability)
        }
    }

    private func initialStability(for rating: ReviewRating) -> Double {
        max(parameters[rating.rawValue - 1], 0.001)
    }

    private func initialDifficulty(for rating: ReviewRating, clamp: Bool) -> Double {
        let value = parameters[4] - exp(parameters[5] * Double(rating.rawValue - 1)) + 1
        return clamp ? clampDifficulty(value) : value
    }

    private func nextDifficulty(difficulty: Double, rating: ReviewRating) -> Double {
        let target = initialDifficulty(for: .easy, clamp: false)
        let delta = -parameters[6] * Double(rating.rawValue - 3)
        let damped = difficulty + (10 - difficulty) * delta / 9
        return clampDifficulty(parameters[7] * target + (1 - parameters[7]) * damped)
    }

    private func shortTermStability(stability: Double, rating: ReviewRating) -> Double {
        var increase = exp(parameters[17] * Double(rating.rawValue - 3) + parameters[17] * parameters[18])
            * pow(stability, -parameters[19])
        if rating == .good || rating == .easy {
            increase = max(increase, 1)
        }
        return max(stability * increase, 0.001)
    }

    private func nextStability(
        difficulty: Double,
        stability: Double,
        retrievability: Double,
        rating: ReviewRating
    ) -> Double {
        if rating == .again {
            let longTerm = parameters[11]
                * pow(difficulty, -parameters[12])
                * (pow(stability + 1, parameters[13]) - 1)
                * exp((1 - retrievability) * parameters[14])
            let shortTerm = stability / exp(parameters[17] * parameters[18])
            return max(min(longTerm, shortTerm), 0.001)
        }

        let hardPenalty = rating == .hard ? parameters[15] : 1
        let easyBonus = rating == .easy ? parameters[16] : 1
        let increase = exp(parameters[8])
            * (11 - difficulty)
            * pow(stability, -parameters[9])
            * (exp((1 - retrievability) * parameters[10]) - 1)
            * hardPenalty
            * easyBonus
        return max(stability * (1 + increase), 0.001)
    }

    private func dayInterval(for stability: Double?) -> TimeInterval {
        let stability = max(stability ?? 0.001, 0.001)
        let rawDays = stability / factor * (pow(desiredRetention, 1 / decay) - 1)
        let days = min(max(Int(rawDays.rounded()), 1), maximumIntervalDays)
        return TimeInterval(days) * 86_400
    }

    private func wholeDays(from start: Date?, to end: Date) -> Int? {
        guard let start else { return nil }
        return max(0, Int(floor(end.timeIntervalSince(start) / 86_400)))
    }

    private func clampDifficulty(_ value: Double) -> Double {
        min(max(value, 1), 10)
    }
}
