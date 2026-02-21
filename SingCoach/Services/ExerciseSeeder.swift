import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ExerciseSeeder: ObservableObject {
    // Build 9: Key bumped to v3 — updated YouTube video IDs (Error 152 fix)
    private let seededKey = "SingCoach.ExercisesSeeded.v3"

    /// Call this AFTER the ModelContainer is fully ready, passing the context in.
    func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else {
            print("[SingCoach] Exercises already seeded (v2), skipping")
            return
        }

        // Guard: only seed if no library exercises exist already
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.templateID != nil }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else {
            print("[SingCoach] Library exercises already present (\(existing.count)), skipping seed")
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }

        print("[SingCoach] Seeding \(ExerciseSeeder.seedExercises.count) library exercises...")
        for template in ExerciseSeeder.seedExercises {
            let exercise = template.toExercise()
            context.insert(exercise)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
        print("[SingCoach] Exercise seeding complete.")
    }

    // Exercises are seeded on first fetch in ExerciseStore
    static var seedExercises: [ExerciseTemplate] {
        [
            // BREATH
            ExerciseTemplate(
                templateID: "breath-sustained-hiss",
                name: "Sustained Hiss",
                category: "breath",
                description: "Exhale on a sustained 'sss' sound to build breath control and efficiency.",
                instruction: "Take a deep diaphragmatic breath, then exhale slowly on a sustained 'sss' sound. Aim for 20-30 seconds. Keep airflow steady and even.",
                focusArea: "Breath control and support",
                youtubeURL: "https://www.youtube.com/watch?v=OtxPre6RvaA",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Don't force the air — let it flow naturally",
                    "Your stomach should deflate as you exhale",
                    "Time yourself to track improvement"
                ],
                keywords: ["breath", "support", "airflow", "control", "sustained", "hiss", "diaphragm"]
            ),
            ExerciseTemplate(
                templateID: "breath-478-breathing",
                name: "4-7-8 Diaphragmatic Breathing",
                category: "breath",
                description: "A breathing technique that builds diaphragmatic awareness and capacity.",
                instruction: "Inhale for 4 counts, hold for 7 counts, exhale for 8 counts. Place one hand on your belly to feel diaphragmatic movement.",
                focusArea: "Diaphragm engagement and breath capacity",
                youtubeURL: "https://www.youtube.com/watch?v=GEJ30bnp780",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Feel your belly expand on the inhale",
                    "Don't raise your shoulders",
                    "Practice daily for best results"
                ],
                keywords: ["breath", "diaphragm", "breathing", "capacity", "support", "technique"]
            ),
            ExerciseTemplate(
                templateID: "breath-staccato-pulses",
                name: "Staccato Breath Pulses",
                category: "breath",
                description: "Short, sharp breath pulses to activate the diaphragm and build breath agility.",
                instruction: "Exhale on sharp 'sh' or 'ss' pulses — one per beat at 60-80 BPM. Keep the rest of your body relaxed.",
                focusArea: "Diaphragm agility and breath articulation",
                youtubeURL: "https://www.youtube.com/watch?v=m7wpP_-_-ck",
                durationMinutes: 5,
                difficulty: "intermediate",
                tips: [
                    "Each pulse comes from the diaphragm, not the throat",
                    "Start slow, then increase tempo",
                    "Great for staccato singing passages"
                ],
                keywords: ["breath", "staccato", "diaphragm", "agility", "pulses", "attack"]
            ),
            // PITCH
            ExerciseTemplate(
                templateID: "pitch-siren-glide",
                name: "Siren Glide",
                category: "pitch",
                description: "Slide through your full range on a continuous 'wee' sound like a siren.",
                instruction: "Start at your lowest comfortable note and slide continuously up to your highest, then back down. Use an 'ng' or 'wee' sound.",
                focusArea: "Full range pitch awareness and smooth transitions",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Don't stop or get stuck — keep it continuous",
                    "Listen for any cracks or breaks",
                    "Do this every day to open your range"
                ],
                keywords: ["pitch", "range", "siren", "glide", "slide", "full range", "smooth", "transition"]
            ),
            ExerciseTemplate(
                templateID: "pitch-drone-matching",
                name: "Pitch Matching to Drone",
                category: "pitch",
                description: "Match your voice precisely to a drone note to develop pitch accuracy.",
                instruction: "Play a sustained tone (use a piano, tuner app, or GarageBand drone). Sing the same note. Adjust until they blend perfectly.",
                focusArea: "Pitch accuracy and ear training",
                youtubeURL: "https://www.youtube.com/watch?v=Mtp8qqo3qm8",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Use a tuner app to verify accuracy",
                    "Try different vowels on the same pitch",
                    "Close your eyes to focus on listening"
                ],
                keywords: ["pitch", "accuracy", "matching", "drone", "ear training", "intonation"]
            ),
            ExerciseTemplate(
                templateID: "pitch-interval-jumps",
                name: "Interval Jumps (3rds/5ths)",
                category: "pitch",
                description: "Practice jumping between musical intervals to build pitch memory.",
                instruction: "Starting on any note, jump up a third, then a fifth, landing accurately each time. Sing on 'la' or 'na'. Use a piano or app for reference.",
                focusArea: "Interval recognition and pitch memory",
                youtubeURL: "https://www.youtube.com/watch?v=mYaicBcsUAI",
                durationMinutes: 10,
                difficulty: "intermediate",
                tips: [
                    "Hear the interval in your head before you sing it",
                    "Record yourself and compare to the piano",
                    "Start with thirds before moving to fifths"
                ],
                keywords: ["pitch", "intervals", "thirds", "fifths", "ear training", "accuracy", "jumps"]
            ),
            // RESONANCE
            ExerciseTemplate(
                templateID: "resonance-humming-scale",
                name: "Humming Scale",
                category: "resonance",
                description: "Hum a 5-note scale to build nasal resonance and find forward placement.",
                instruction: "Hum 'mmm' on a 5-note scale (do-re-mi-fa-sol-fa-mi-re-do). Feel vibration in your lips and cheekbones. Keep the sound buzzy and forward.",
                focusArea: "Nasal resonance and forward placement",
                youtubeURL: "https://www.youtube.com/watch?v=VVM9uJ25VbM",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Touch your lips lightly to feel vibration",
                    "Imagine the sound coming from your nose bridge",
                    "Don't close your throat — stay open"
                ],
                keywords: ["resonance", "nasal", "placement", "humming", "forward", "vibration", "placement"]
            ),
            ExerciseTemplate(
                templateID: "resonance-ng-placement",
                name: "'Ng' Placement Exercise",
                category: "resonance",
                description: "Use the 'ng' consonant to anchor resonance in the hard palate.",
                instruction: "Hold an 'ng' sound (as in 'sing') and feel vibration in the back of your hard palate. Then slide onto vowels while maintaining that placement.",
                focusArea: "Hard palate resonance and placement consistency",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "The 'ng' position locks resonance into the right spot",
                    "Transition slowly to 'a', 'e', 'i' from 'ng'",
                    "Used in many vocal coaching schools worldwide"
                ],
                keywords: ["resonance", "ng", "placement", "hard palate", "vowel", "forward", "mask"]
            ),
            ExerciseTemplate(
                templateID: "resonance-forward-buzz",
                name: "Forward Resonance Buzz",
                category: "resonance",
                description: "Create a buzzy forward tone to develop mask resonance.",
                instruction: "Sing on a buzzy 'zee' or 'vvv' sound and direct the vibration to your lips, nose, and forehead. Scales or sustained tones both work.",
                focusArea: "Mask resonance and projection",
                youtubeURL: "https://www.youtube.com/watch?v=Q_CTNsYTkD4",
                durationMinutes: 5,
                difficulty: "intermediate",
                tips: [
                    "More buzz = more projection without strain",
                    "This reduces throat tension",
                    "Singers with 'nasal' voices often need this redirected"
                ],
                keywords: ["resonance", "buzz", "forward", "mask", "projection", "placement", "vibration"]
            ),
            // AGILITY
            ExerciseTemplate(
                templateID: "agility-lip-trill-scales",
                name: "Lip Trill Scales",
                category: "agility",
                description: "Bubble your lips on scales to build vocal agility without strain.",
                instruction: "Blow air through loosely closed lips to create a 'brrr' trill. Maintain this as you sing scales up and down. Keep the trill even.",
                focusArea: "Vocal agility and breath-voice coordination",
                youtubeURL: "https://www.youtube.com/watch?v=VVM9uJ25VbM",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Lips should be relaxed, not forced",
                    "If the trill stops, you're pushing too hard",
                    "Great warm-up that reduces vocal fatigue"
                ],
                keywords: ["agility", "lip trill", "scales", "flexibility", "warm-up", "breath", "coordination"]
            ),
            ExerciseTemplate(
                templateID: "agility-tongue-rolled-scales",
                name: "Tongue-Rolled 'Rrrr' Scales",
                category: "agility",
                description: "Rolled 'r' scales to develop tongue agility and coordinate airflow.",
                instruction: "Roll your tongue ('rrr' as in Spanish) and sustain it through scales. Works breath support and tongue independence simultaneously.",
                focusArea: "Tongue agility and airflow",
                youtubeURL: "https://www.youtube.com/watch?v=VVM9uJ25VbM",
                durationMinutes: 5,
                difficulty: "intermediate",
                tips: [
                    "If you can't roll your r, try 'dr' first",
                    "Steady airflow keeps the roll going",
                    "Great for rapid passages in music"
                ],
                keywords: ["agility", "tongue", "rolled r", "scales", "flexibility", "articulation", "coordination"]
            ),
            ExerciseTemplate(
                templateID: "agility-rapid-5tone-run",
                name: "Rapid 5-Tone Scale Run",
                category: "agility",
                description: "Sing rapid 5-note ascending and descending runs to build speed.",
                instruction: "Sing do-re-mi-fa-sol-fa-mi-re-do quickly on 'la' or 'na'. Start slow, then increase speed while maintaining clarity on each note.",
                focusArea: "Melodic agility and note clarity at speed",
                youtubeURL: "https://www.youtube.com/watch?v=mYaicBcsUAI",
                durationMinutes: 5,
                difficulty: "intermediate",
                tips: [
                    "Clarity matters more than speed — don't rush",
                    "Record and listen back for muddy notes",
                    "Work in short bursts of 3-5 minutes"
                ],
                keywords: ["agility", "runs", "fast", "5-tone", "scale", "melisma", "speed", "flexibility"]
            ),
            // REGISTER
            ExerciseTemplate(
                templateID: "register-chest-head-slide",
                name: "Chest-to-Head Voice Slide",
                category: "register",
                description: "Slide from chest to head voice to explore and smooth the passaggio.",
                instruction: "Start in your comfortable chest voice, then slide upward through your break into head voice. Use 'no' or 'nee' as the vowel.",
                focusArea: "Register transitions and passaggio",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "intermediate",
                tips: [
                    "Don't avoid the break — explore it",
                    "The goal is smooth, not no-break",
                    "This reveals where your passaggio sits"
                ],
                keywords: ["register", "chest voice", "head voice", "passaggio", "break", "transition", "slide"]
            ),
            ExerciseTemplate(
                templateID: "register-mixed-voice-siren",
                name: "Mixed Voice Siren",
                category: "register",
                description: "Find mixed voice by blending chest and head resonance in the middle range.",
                instruction: "Siren through your middle range (the passaggio zone) looking for a 'mixed' tone that's neither pure chest nor pure head. Use 'wee' or 'me'.",
                focusArea: "Mixed voice development",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 10,
                difficulty: "advanced",
                tips: [
                    "Mixed voice feels 'lighter' than chest but fuller than head",
                    "Takes weeks to develop — be patient",
                    "This is the money zone for commercial singing"
                ],
                keywords: ["register", "mixed voice", "chest", "head", "blend", "middle", "passaggio", "belt"]
            ),
            ExerciseTemplate(
                templateID: "register-falsetto-flip",
                name: "Falsetto Flip Exercise",
                category: "register",
                description: "Practice intentional flips to falsetto to develop register control.",
                instruction: "Sing up a scale in chest voice, then intentionally flip into falsetto at your break. Then practice landing softly vs hard. Use 'hoo' or 'hee'.",
                focusArea: "Falsetto access and register control",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "intermediate",
                tips: [
                    "The flip is not a mistake — learn to control it",
                    "Falsetto is a valid artistic choice",
                    "Gentle flip = lighter mass coordination"
                ],
                keywords: ["register", "falsetto", "flip", "control", "head voice", "break", "coordination"]
            ),
            // VOWEL
            ExerciseTemplate(
                templateID: "vowel-ieaou-modification",
                name: "Vowel Modification Scales [i-e-a-o-u]",
                category: "vowel",
                description: "Sing all five vowels on a scale to practice consistent shape and resonance.",
                instruction: "On each note of a 5-tone scale, sing through i-e-a-o-u. Keep your jaw, tongue and soft palate consistent. Focus on resonance continuity.",
                focusArea: "Vowel consistency and resonance across vowels",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 10,
                difficulty: "beginner",
                tips: [
                    "Don't let the jaw clamp shut on 'i' or 'e'",
                    "Keep the back of the throat open on all vowels",
                    "Record and compare vowel quality"
                ],
                keywords: ["vowel", "modification", "i e a o u", "consistency", "resonance", "shape", "placement"]
            ),
            ExerciseTemplate(
                templateID: "vowel-open-high-notes",
                name: "Open Vowel on High Notes",
                category: "vowel",
                description: "Modify vowels toward 'ah' or 'aw' on high notes to reduce tension.",
                instruction: "As you ascend into your upper range, gradually modify closed vowels (i, e) toward more open shapes (ah, aw). This reduces laryngeal tension.",
                focusArea: "Vowel modification for upper range access",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 10,
                difficulty: "intermediate",
                tips: [
                    "High 'ee' becomes closer to 'ih' or 'eh'",
                    "This is classical technique applied to contemporary singing",
                    "Don't over-modify — stay musical"
                ],
                keywords: ["vowel", "modification", "high notes", "open", "upper range", "tension", "ah", "aw"]
            ),
            ExerciseTemplate(
                templateID: "vowel-consistency-drill",
                name: "Vowel Consistency Drill",
                category: "vowel",
                description: "Maintain the same vowel sound through pitch changes for consistent tone.",
                instruction: "Sustain a single vowel (e.g. 'ah') while moving through a 5-note arpeggio. The vowel shape should stay identical regardless of pitch.",
                focusArea: "Vowel stability and consistent resonance",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "intermediate",
                tips: [
                    "Videotape your face — does your mouth change shape?",
                    "The listener should hear one vowel, not a moving target",
                    "Works through arpeggios more than scales"
                ],
                keywords: ["vowel", "consistency", "stability", "resonance", "arpeggio", "sustained", "shape"]
            ),
            // ARTICULATION
            ExerciseTemplate(
                templateID: "articulation-consonant-clarity",
                name: "Consonant Clarity Drill (p-t-k)",
                category: "articulation",
                description: "Work the articulator muscles with explosive consonants for crisp diction.",
                instruction: "Rapidly repeat 'p-t-k-p-t-k' on a breath. Then sing it on a repeated pitch. Focus on snappy, clean release on each consonant.",
                focusArea: "Articulator agility and consonant crispness",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Each consonant should 'pop' cleanly",
                    "Don't tense your jaw — articulation comes from lips/tongue/soft palate",
                    "Great for enunciation in fast passages"
                ],
                keywords: ["articulation", "consonants", "diction", "clarity", "ptk", "crisp", "agility"]
            ),
            ExerciseTemplate(
                templateID: "articulation-diction-phrase",
                name: "Diction Phrase Repetition",
                category: "articulation",
                description: "Sing tongue-twister style phrases to improve clarity at speed.",
                instruction: "Sing 'She sells seashells' or 'Red lorry, yellow lorry' on a single pitch repeatedly, then on a scale. Focus on clear consonants without tension.",
                focusArea: "Diction clarity in musical context",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Slow it down until it's clean, then speed up",
                    "Over-articulate to find the edges",
                    "Used by musical theatre performers"
                ],
                keywords: ["articulation", "diction", "phrase", "tongue twister", "clarity", "enunciation", "words"]
            ),
            ExerciseTemplate(
                templateID: "articulation-staccato-consonants",
                name: "Staccato Consonant Bursts",
                category: "articulation",
                description: "Short punchy syllables on scale steps to build rhythmic precision.",
                instruction: "Sing 'ha-ha-ha' or 'ba-ba-ba' in short staccato bursts on ascending scale degrees. Focus on clean onset and release of each syllable.",
                focusArea: "Rhythmic precision and clean consonant onset",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "intermediate",
                tips: [
                    "Each 'ha' comes from the diaphragm, not the throat",
                    "Keep your jaw relaxed between bursts",
                    "Great for percussive singing styles"
                ],
                keywords: ["articulation", "staccato", "consonants", "burst", "rhythmic", "onset", "precision"]
            ),
            // WARMUP
            ExerciseTemplate(
                templateID: "warmup-yawn-sigh",
                name: "Yawn-Sigh Full Range",
                category: "warmup",
                description: "The gentlest way to open your full vocal range with zero strain.",
                instruction: "Initiate a real yawn to open the throat. As you exhale, let the sigh descend from high to low — include your full range naturally.",
                focusArea: "Gentle range opening and throat relaxation",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Never force the yawn — wait for it to come naturally",
                    "The sigh should feel effortless",
                    "Perfect first exercise of any session"
                ],
                keywords: ["warmup", "yawn", "sigh", "range", "gentle", "opening", "relax", "throat"]
            ),
            ExerciseTemplate(
                templateID: "warmup-5tone-gentle",
                name: "Gentle 5-Tone Warmup Scale",
                category: "warmup",
                description: "A simple 5-note scale on 'mah' to wake up the voice gently.",
                instruction: "Sing do-re-mi-fa-sol-fa-mi-re-do on 'mah' in a comfortable mid-range. No pushing, no tension. Just wake up the voice.",
                focusArea: "General voice activation",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 5,
                difficulty: "beginner",
                tips: [
                    "Start in the middle of your range — not too high, not too low",
                    "This should feel easy and pleasant",
                    "Do this before every practice session"
                ],
                keywords: ["warmup", "5-tone", "scale", "gentle", "mah", "voice activation", "routine"]
            ),
            ExerciseTemplate(
                templateID: "warmup-jaw-tongue-release",
                name: "Jaw and Tongue Release",
                category: "warmup",
                description: "Physical release exercises to remove tension before singing.",
                instruction: "Massage your jaw, let it hang loose. Roll your tongue around, stick it out. Then gently move your jaw side to side. Do 30 seconds of each.",
                focusArea: "Physical tension release in jaw and tongue",
                youtubeURL: "https://www.youtube.com/watch?v=JyfUn0FC5oo",
                durationMinutes: 3,
                difficulty: "beginner",
                tips: [
                    "Tension in the jaw is one of the most common vocal problems",
                    "Do this before any vocal exercise",
                    "If your jaw clicks, see a physiotherapist"
                ],
                keywords: ["warmup", "jaw", "tongue", "release", "tension", "physical", "relax", "pre-warm"]
            )
        ]
    }
}

struct ExerciseTemplate {
    let templateID: String
    let name: String
    let category: String
    let description: String
    let instruction: String
    let focusArea: String
    let youtubeURL: String?
    let durationMinutes: Int
    let difficulty: String
    let tips: [String]
    let keywords: [String]

    func toExercise() -> Exercise {
        Exercise(
            templateID: templateID,
            name: name,
            category: category,
            exerciseDescription: description,
            instruction: instruction,
            focusArea: focusArea,
            isPinned: false,
            youtubeURL: youtubeURL,
            durationMinutes: durationMinutes,
            difficulty: difficulty,
            tips: tips,
            keywords: keywords,
            isUserCreated: false,
            songID: nil  // library exercises have no song
        )
    }
}
