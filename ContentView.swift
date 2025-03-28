//final completed code
//by Lee Zhen Yu Lee
//4 Techno Class Varee Chiang Mai School (Thailand)
import SwiftUI
import ARKit
import RealityKit
import Speech
import AVFoundation

// App Theme and Constants

struct AppTheme {
static let primaryColor = Color.blue
static let backgroundColor = Color(.systemBackground)
static let secondaryBackgroundColor = Color(.secondarySystemBackground)
static let textColor = Color(.label)
static let secondaryTextColor = Color(.secondaryLabel)

static let cornerRadius: CGFloat = 20
static let padding: CGFloat = 16
static let smallPadding: CGFloat = 8

static let shadowRadius: CGFloat = 12
static let shadowOpacity: Float = 0.15
static let shadowOffset = CGSize(width: 0, height: 6)
}

// Custom Views

struct StyledCard<Content: View>: View {
let content: Content

init(@ViewBuilder content: () -> Content) {
self.content = content()
}

var body: some View {
content
.padding(AppTheme.padding)
.background(AppTheme.backgroundColor)
.cornerRadius(AppTheme.cornerRadius)
.shadow(radius: AppTheme.shadowRadius, x: AppTheme.shadowOffset.width, y: AppTheme.shadowOffset.height)
}
}

struct ActionButton: View {
let icon: String
let color: Color
let action: () -> Void

var body: some View {
Button(action: action) {
Image(systemName: icon)
.font(.system(size: 24, weight: .semibold))
.frame(width: 60, height: 60)
.foregroundColor(.white)
.background(color)
.clipShape(Circle())
.shadow(radius: AppTheme.shadowRadius, x: AppTheme.shadowOffset.width, y: AppTheme.shadowOffset.height)
}
.padding()
}
}
struct TranscriptionLog: Identifiable, Codable {
let id = UUID()
let text: String
let timestamp: Date

init(text: String) {
self.text = text
self.timestamp = Date()
}
}

// Helper Functions

func wrapText(_ text: String, every n: Int) -> String {
var wrappedText = ""
for (index, char) in text.enumerated() {
if index % n == 0 && index != 0 {
wrappedText += "\n"
}
wrappedText.append(char)
}
return wrappedText
}

func createTextEntity(text: String) -> ModelEntity {
let mesh = MeshResource.generateText(
text,
extrusionDepth: 0.01,
font: .systemFont(ofSize: 0.1),
containerFrame: .zero,
alignment: .center,
lineBreakMode: .byWordWrapping
)

let material = SimpleMaterial(color: .white, isMetallic: false)
let entity = ModelEntity(mesh: mesh, materials: [material])

entity.position.z = 0
entity.position.y = 0.1
entity.position.x = -0.1

return entity
}

class LogManager: ObservableObject {
@Published var logs: [TranscriptionLog] = []
private let saveKey = "TranscriptionLogs"

init() { loadLogs() }

func addLog(_ text: String) {
let log = TranscriptionLog(text: text)
logs.append(log)
saveLogs()
}

func deleteLogs(at offsets: IndexSet) {
logs.remove(atOffsets: offsets)
saveLogs()
}

private func saveLogs() {
if let encoded = try? JSONEncoder().encode(logs) {
UserDefaults.standard.set(encoded, forKey: saveKey)
}
}

private func loadLogs() {
if let data = UserDefaults.standard.data(forKey: saveKey),
let decoded = try? JSONDecoder().decode([TranscriptionLog].self, from: data) {
logs = decoded
}
}
}

// Speech Recognition Manager
class SpeechRecognizer: ObservableObject {
@Published var transcribedText = ""
@Published var currentWord = ""
@Published var isRecording = false

private let speechRecognizer = SFSpeechRecognizer()
private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
private var recognitionTask: SFSpeechRecognitionTask?
private let audioEngine = AVAudioEngine()

init() {
requestPermissions()
}

private func requestPermissions() {
SFSpeechRecognizer.requestAuthorization { status in
DispatchQueue.main.async {
switch status {
case .authorized: self.transcribedText = "Ready to transcribe"
case .denied: self.transcribedText = "Permission denied"
case .restricted, .notDetermined: self.transcribedText = "Not authorized"
@unknown default: self.transcribedText = "Unknown error"
}
}
}

AVAudioSession.sharedInstance().requestRecordPermission { granted in
if !granted {
DispatchQueue.main.async { self.transcribedText = "Microphone permission denied" }
}
}
}

func startTranscription() {
guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
transcribedText = "Speech recognizer not available."
return
}

do {
try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
recognitionRequest?.shouldReportPartialResults = true

let inputNode = audioEngine.inputNode
let format = inputNode.outputFormat(forBus: 0)

inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
self.recognitionRequest?.append(buffer)
}

recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { result, error in

if let result = result {
DispatchQueue.main.async {
self.transcribedText = result.bestTranscription.formattedString

let words = result.bestTranscription.formattedString.components(separatedBy: " ")

if let lastWord = words.last, lastWord != self.currentWord {
self.currentWord = lastWord
}
}
}


if error != nil || result?.isFinal == true {
self.stopTranscription()
}
}

audioEngine.prepare()
try audioEngine.start()
isRecording = true
} catch {
transcribedText = "Failed to start recording."
}
}

func stopTranscription() {
audioEngine.stop()
recognitionRequest?.endAudio()
recognitionTask?.cancel()
recognitionTask = nil
isRecording = false

do { try AVAudioSession.sharedInstance().setActive(false) }
catch { print("Failed to deactivate audio session") }
}
}

struct ARViewContainer: UIViewRepresentable {
@ObservedObject var speechRecognizer: SpeechRecognizer

func makeUIView(context: Context) -> ARView {
let arView = ARView(frame: .zero)
configureARSession(for: arView, context: context)
return arView
}

func updateUIView(_ uiView: ARView, context: Context) {
configureARSession(for: uiView, context: context)

// Remove old text
context.coordinator.faceAnchor.children.forEach { $0.removeFromParent() }

// Add new text
let newTextEntity = createTextEntity(
text: speechRecognizer.currentWord.isEmpty ? "Say something..." : speechRecognizer.currentWord
)
context.coordinator.faceAnchor.addChild(newTextEntity)
}

private func configureARSession(for arView: ARView, context: Context) {
let configuration = ARFaceTrackingConfiguration()
arView.session.run(configuration)
arView.scene.anchors.append(context.coordinator.faceAnchor)
}

func makeCoordinator() -> Coordinator {
return Coordinator()
}

class Coordinator {
var faceAnchor = AnchorEntity(.face)
}
}

// ContentView

struct ContentView: View {
@StateObject private var speechRecognizer = SpeechRecognizer()
@StateObject private var logManager = LogManager()
@State private var isRecording = false
@State private var showingLogs = false

var body: some View {
ZStack {
AppTheme.backgroundColor.ignoresSafeArea()

VStack(spacing: AppTheme.padding) {
Text("HearMeOut")
.font(.system(size: 32, weight: .bold))
.foregroundColor(AppTheme.primaryColor)

StyledCard {
ZStack {
ARViewContainer(speechRecognizer: speechRecognizer)
.frame(width: UIScreen.main.bounds.width * 0.8, height: UIScreen.main.bounds.width * 0.6)
.clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

VStack {
Spacer()
HStack {
Text(isRecording ? "Recording..." : "Ready")
.font(.caption)
.foregroundColor(.white)
.padding(.horizontal, 12)
.padding(.vertical, 6)
.background(isRecording ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
.cornerRadius(12)
}
.padding(.bottom, 12)
}
}
}

Spacer()

HStack(spacing: AppTheme.padding * 2) {
ActionButton(icon: isRecording ? "pause.fill" : "mic.fill", color: isRecording ? .red : .green) {
if isRecording {
speechRecognizer.stopTranscription()
logManager.addLog(speechRecognizer.transcribedText)
} else {
speechRecognizer.startTranscription()
}
isRecording.toggle()
}

ActionButton(icon: "list.bullet", color: .gray) {
showingLogs.toggle()
}
}
.frame(maxWidth: .infinity)
.padding(.bottom, 30)
}
.padding()
.sheet(isPresented: $showingLogs) {
LogView(logManager: logManager)
}
}
}
}

struct LogView: View {
@ObservedObject var logManager: LogManager

var body: some View {
NavigationView {
List {
ForEach(logManager.logs) { log in
VStack(alignment: .leading) {
Text(log.text)
.font(.headline)
Text(log.timestamp, style: .date)
.font(.subheadline)
.foregroundColor(.gray)
}
}
.onDelete(perform: logManager.deleteLogs)
}
.navigationTitle("Transcription Logs")
.toolbar {
EditButton()
}
}
}
}
//The APP!!!! :)
struct HearMeOutApp: SwiftUI.App {
var body: some SwiftUI.Scene {
WindowGroup {
ContentView()
}
}
}