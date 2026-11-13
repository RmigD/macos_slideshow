import XCTest
@testable import SlideshowGenerator

final class FFmpegCommandBuilderTests: XCTestCase {

    private func plan(count: Int, settings: SlideshowSettings, audio: AudioTrackSettings = AudioTrackSettings()) -> ExportPlan {
        ExportPlan(
            imageFiles: (0..<count).map { URL(fileURLWithPath: "/tmp/frame_\($0).png") },
            settings: settings,
            audio: audio,
            outputURL: URL(fileURLWithPath: "/tmp/out.mp4")
        )
    }

    func testTotalDurationCountsEachTransitionOnce() {
        var s = SlideshowSettings()
        s.imageDuration = 4
        s.transitionDuration = 1
        s.transition = .fade
        XCTAssertEqual(FFmpegCommandBuilder.totalDuration(imageCount: 3, settings: s), 13, accuracy: 0.001)
    }

    func testHardCutHasNoOverlap() {
        var s = SlideshowSettings()
        s.imageDuration = 4
        s.transition = .cut
        XCTAssertEqual(FFmpegCommandBuilder.totalDuration(imageCount: 3, settings: s), 12, accuracy: 0.001)
    }

    func testTransitionOffsetsFollowImageDuration() throws {
        var s = SlideshowSettings()
        s.imageDuration = 4
        s.transitionDuration = 1
        let args = try FFmpegCommandBuilder.arguments(for: plan(count: 3, settings: s)).joined(separator: " ")
        XCTAssertTrue(args.contains("offset=4.000"))
        XCTAssertTrue(args.contains("offset=8.000"))
    }

    func testTransitionLongerThanImageIsRejected() {
        var s = SlideshowSettings()
        s.imageDuration = 2
        s.transitionDuration = 2
        XCTAssertThrowsError(try FFmpegCommandBuilder.arguments(for: plan(count: 3, settings: s)))
    }

    func testMusicIsFadedAndTrimmedToVideoLength() throws {
        var s = SlideshowSettings()
        s.imageDuration = 4
        s.transitionDuration = 1
        var audio = AudioTrackSettings()
        audio.url = URL(fileURLWithPath: "/tmp/song.mp3")
        audio.fadeOutSeconds = 2
        let args = try FFmpegCommandBuilder.arguments(for: plan(count: 3, settings: s, audio: audio)).joined(separator: " ")
        // Total is 13 s, so the fade starts at 11 s.
        XCTAssertTrue(args.contains("afade=t=out:st=11.000:d=2.000"))
        XCTAssertTrue(args.contains("atrim=0:13.000"))
    }

    func testLoopFlagPrecedesMusicInput() throws {
        var s = SlideshowSettings()
        s.imageDuration = 4
        var audio = AudioTrackSettings()
        audio.url = URL(fileURLWithPath: "/tmp/song.mp3")
        audio.loop = true
        let args = try FFmpegCommandBuilder.arguments(for: plan(count: 2, settings: s, audio: audio))
        let loopIndex = try XCTUnwrap(args.firstIndex(of: "-stream_loop"))
        XCTAssertEqual(args[loopIndex + 1], "-1")
        XCTAssertEqual(args[loopIndex + 2], "-i")
        XCTAssertEqual(args[loopIndex + 3], "/tmp/song.mp3")
    }
}
