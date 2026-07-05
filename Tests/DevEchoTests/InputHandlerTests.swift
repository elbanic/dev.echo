import XCTest
@testable import dev_echo

/// Tests for InputHandler multi-line editing and UTF-8 support.
///
/// These tests target EXTRACTABLE LOGIC only -- not terminal I/O (getchar, tcsetattr).
/// They define the expected behavior for:
///   A. CSI escape sequence parsing
///   B. UTF-8 byte sequence detection
///   C. Multi-line text utility methods
///   D. Input buffer state management (clearCurrentInput, bracketed paste helpers)
///   E. CSISequence enum existence and Equatable
///   F. Bracketed paste mode integration
///   G. Double-ESC input clear
///
/// All tests are expected to FAIL because the referenced types and methods
/// do not yet exist on InputHandler.
final class InputHandlerTests: XCTestCase {

    // =========================================================================
    // MARK: - A. CSI Sequence Parsing
    // =========================================================================
    //
    // InputHandler.parseCSISequence should accept the bytes that follow ESC [
    // and return a CSISequence enum value identifying the sequence.
    //
    // CSISequence is a new enum that must be defined:
    //   enum CSISequence: Equatable {
    //       case arrowUp
    //       case arrowDown
    //       case arrowRight
    //       case arrowLeft
    //       case home
    //       case end
    //       case delete
    //       case pasteStart        // ESC[200~
    //       case pasteEnd          // ESC[201~
    //       case shiftEnter        // ESC[13;2u  (kitty keyboard protocol)
    //       case unknown([UInt8])
    //   }

    // MARK: Arrow Keys

    func testParseCSISequenceArrowUp() {
        // ESC [ A (65) -> arrowUp
        let result = InputHandler.parseCSISequence([65])
        XCTAssertEqual(result, CSISequence.arrowUp)
    }

    func testParseCSISequenceArrowDown() {
        // ESC [ B (66) -> arrowDown
        let result = InputHandler.parseCSISequence([66])
        XCTAssertEqual(result, CSISequence.arrowDown)
    }

    func testParseCSISequenceArrowRight() {
        // ESC [ C (67) -> arrowRight
        let result = InputHandler.parseCSISequence([67])
        XCTAssertEqual(result, CSISequence.arrowRight)
    }

    func testParseCSISequenceArrowLeft() {
        // ESC [ D (68) -> arrowLeft
        let result = InputHandler.parseCSISequence([68])
        XCTAssertEqual(result, CSISequence.arrowLeft)
    }

    // MARK: Navigation Keys

    func testParseCSISequenceHome() {
        // ESC [ H -> home (move cursor to start of line)
        let result = InputHandler.parseCSISequence([72])
        XCTAssertEqual(result, CSISequence.home)
    }

    func testParseCSISequenceEnd() {
        // ESC [ F -> end (move cursor to end of line)
        let result = InputHandler.parseCSISequence([70])
        XCTAssertEqual(result, CSISequence.end)
    }

    func testParseCSISequenceDelete() {
        // ESC [ 3 ~ -> delete (forward delete)
        // Byte sequence after ESC[: 51 (ASCII '3'), 126 (ASCII '~')
        let result = InputHandler.parseCSISequence([51, 126])
        XCTAssertEqual(result, CSISequence.delete)
    }

    // MARK: Bracketed Paste Mode

    func testParseCSISequencePasteStart() {
        // ESC [ 200~ -> pasteStart
        // Byte sequence after ESC[: "200~" = [50, 48, 48, 126]
        let result = InputHandler.parseCSISequence([50, 48, 48, 126])
        XCTAssertEqual(result, CSISequence.pasteStart)
    }

    func testParseCSISequencePasteEnd() {
        // ESC [ 201~ -> pasteEnd
        // Byte sequence after ESC[: "201~" = [50, 48, 49, 126]
        let result = InputHandler.parseCSISequence([50, 48, 49, 126])
        XCTAssertEqual(result, CSISequence.pasteEnd)
    }

    // MARK: Shift+Enter (Kitty Keyboard Protocol)

    func testParseCSISequenceShiftEnter() {
        // ESC [ 13;2u -> shiftEnter
        // Byte sequence after ESC[: "13;2u" = [49, 51, 59, 50, 117]
        let result = InputHandler.parseCSISequence([49, 51, 59, 50, 117])
        XCTAssertEqual(result, CSISequence.shiftEnter)
    }

    // MARK: Unknown Sequences

    func testParseCSISequenceUnknownSingleByte() {
        // An unrecognized single byte after ESC[
        let result = InputHandler.parseCSISequence([99])
        XCTAssertEqual(result, CSISequence.unknown([99]))
    }

    func testParseCSISequenceUnknownMultiByte() {
        // An unrecognized multi-byte sequence
        let result = InputHandler.parseCSISequence([57, 57, 57])
        XCTAssertEqual(result, CSISequence.unknown([57, 57, 57]))
    }

    func testParseCSISequenceEmptyBytes() {
        // Edge case: empty byte array (should not crash)
        let result = InputHandler.parseCSISequence([])
        XCTAssertEqual(result, CSISequence.unknown([]))
    }

    // MARK: Distinguishing Similar Sequences

    func testParseCSISequencePasteStartNotPasteEnd() {
        // Ensure 200~ and 201~ are distinguished
        let start = InputHandler.parseCSISequence([50, 48, 48, 126])
        let end = InputHandler.parseCSISequence([50, 48, 49, 126])
        XCTAssertNotEqual(start, end)
        XCTAssertEqual(start, CSISequence.pasteStart)
        XCTAssertEqual(end, CSISequence.pasteEnd)
    }

    func testParseCSISequenceShiftEnterNotArrow() {
        // Shift+Enter is a different kind of sequence from simple arrows
        let shiftEnter = InputHandler.parseCSISequence([49, 51, 59, 50, 117])
        let arrowUp = InputHandler.parseCSISequence([65])
        XCTAssertNotEqual(shiftEnter, arrowUp)
    }

    // =========================================================================
    // MARK: - B. UTF-8 Byte Sequence Detection
    // =========================================================================
    //
    // InputHandler.utf8ByteLength(startByte:) should return the expected
    // number of bytes in a UTF-8 character given its first (start) byte.
    // Returns nil for invalid start bytes (continuation bytes 0x80-0xBF).

    // MARK: ASCII Range (1-byte)

    func testUTF8ByteLengthASCIINull() {
        // 0x00 is a valid 1-byte UTF-8 character (NUL)
        let length = InputHandler.utf8ByteLength(startByte: 0x00)
        XCTAssertEqual(length, 1)
    }

    func testUTF8ByteLengthASCIISpace() {
        // 0x20 (space) -> 1 byte
        let length = InputHandler.utf8ByteLength(startByte: 0x20)
        XCTAssertEqual(length, 1)
    }

    func testUTF8ByteLengthASCIILetterA() {
        // 0x41 ('A') -> 1 byte
        let length = InputHandler.utf8ByteLength(startByte: 0x41)
        XCTAssertEqual(length, 1)
    }

    func testUTF8ByteLengthASCIITilde() {
        // 0x7E ('~') -> 1 byte
        let length = InputHandler.utf8ByteLength(startByte: 0x7E)
        XCTAssertEqual(length, 1)
    }

    func testUTF8ByteLengthASCIIDEL() {
        // 0x7F (DEL) -> 1 byte (still single-byte range)
        let length = InputHandler.utf8ByteLength(startByte: 0x7F)
        XCTAssertEqual(length, 1)
    }

    // MARK: 2-Byte Range (Latin Extended, etc.)

    func testUTF8ByteLengthTwoByteStart0xC2() {
        // 0xC2 is the lowest valid 2-byte start (0xC0-0xC1 are overlong)
        let length = InputHandler.utf8ByteLength(startByte: 0xC2)
        XCTAssertEqual(length, 2)
    }

    func testUTF8ByteLengthTwoByteStart0xDF() {
        // 0xDF is the highest 2-byte start byte
        let length = InputHandler.utf8ByteLength(startByte: 0xDF)
        XCTAssertEqual(length, 2)
    }

    // MARK: 3-Byte Range (Korean, Japanese, Chinese, etc.)

    func testUTF8ByteLengthThreeByteStart0xE0() {
        // 0xE0 is the lowest 3-byte start byte
        let length = InputHandler.utf8ByteLength(startByte: 0xE0)
        XCTAssertEqual(length, 3)
    }

    func testUTF8ByteLengthThreeByteStart0xEA() {
        // Korean Hangul syllables start at U+AC00, encoded as 0xEA 0xB0 0x80
        // So 0xEA is the start byte for many Korean characters
        let length = InputHandler.utf8ByteLength(startByte: 0xEA)
        XCTAssertEqual(length, 3)
    }

    func testUTF8ByteLengthThreeByteStart0xEF() {
        // 0xEF is the highest 3-byte start byte
        let length = InputHandler.utf8ByteLength(startByte: 0xEF)
        XCTAssertEqual(length, 3)
    }

    // MARK: 4-Byte Range (Emoji, rare CJK, etc.)

    func testUTF8ByteLengthFourByteStart0xF0() {
        // 0xF0 is the lowest 4-byte start byte (emoji range starts here)
        let length = InputHandler.utf8ByteLength(startByte: 0xF0)
        XCTAssertEqual(length, 4)
    }

    func testUTF8ByteLengthFourByteStart0xF4() {
        // 0xF4 is the highest valid 4-byte start byte (U+10FFFF max)
        let length = InputHandler.utf8ByteLength(startByte: 0xF4)
        XCTAssertEqual(length, 4)
    }

    // MARK: Invalid Start Bytes (Continuation Bytes)

    func testUTF8ByteLengthContinuationByte0x80() {
        // 0x80 is a continuation byte, not a valid start byte
        let length = InputHandler.utf8ByteLength(startByte: 0x80)
        XCTAssertNil(length)
    }

    func testUTF8ByteLengthContinuationByte0xBF() {
        // 0xBF is the highest continuation byte
        let length = InputHandler.utf8ByteLength(startByte: 0xBF)
        XCTAssertNil(length)
    }

    func testUTF8ByteLengthContinuationByte0xA0() {
        // 0xA0 is in the middle of the continuation range
        let length = InputHandler.utf8ByteLength(startByte: 0xA0)
        XCTAssertNil(length)
    }

    // MARK: Overlong Encoding Start Bytes

    func testUTF8ByteLengthOverlong0xC0() {
        // 0xC0 is an overlong 2-byte encoding (would encode U+0000-U+003F)
        // Strictly, these should be rejected. Return nil.
        let length = InputHandler.utf8ByteLength(startByte: 0xC0)
        XCTAssertNil(length)
    }

    func testUTF8ByteLengthOverlong0xC1() {
        // 0xC1 is an overlong 2-byte encoding (would encode U+0040-U+007F)
        let length = InputHandler.utf8ByteLength(startByte: 0xC1)
        XCTAssertNil(length)
    }

    // MARK: Invalid High Bytes

    func testUTF8ByteLengthInvalid0xF5() {
        // 0xF5 and above are invalid in UTF-8 (would encode > U+10FFFF)
        let length = InputHandler.utf8ByteLength(startByte: 0xF5)
        XCTAssertNil(length)
    }

    func testUTF8ByteLengthInvalid0xFE() {
        // 0xFE is never valid in UTF-8
        let length = InputHandler.utf8ByteLength(startByte: 0xFE)
        XCTAssertNil(length)
    }

    func testUTF8ByteLengthInvalid0xFF() {
        // 0xFF is never valid in UTF-8
        let length = InputHandler.utf8ByteLength(startByte: 0xFF)
        XCTAssertNil(length)
    }

    // MARK: Specific Character Start Bytes

    func testUTF8ByteLengthKoreanGa() {
        // Korean character "ga" (U+AC00) encodes as 0xEA 0xB0 0x80
        // Start byte 0xEA -> 3 bytes
        let length = InputHandler.utf8ByteLength(startByte: 0xEA)
        XCTAssertEqual(length, 3)
    }

    func testUTF8ByteLengthKoreanHan() {
        // Korean character "han" (U+D55C) encodes as 0xED 0x95 0x9C
        // Start byte 0xED -> 3 bytes
        let length = InputHandler.utf8ByteLength(startByte: 0xED)
        XCTAssertEqual(length, 3)
    }

    func testUTF8ByteLengthSmileyEmoji() {
        // Smiley face (U+1F600) encodes as 0xF0 0x9F 0x98 0x80
        // Start byte 0xF0 -> 4 bytes
        let length = InputHandler.utf8ByteLength(startByte: 0xF0)
        XCTAssertEqual(length, 4)
    }

    // =========================================================================
    // MARK: - C. Multi-line Text Utilities
    // =========================================================================
    //
    // These static/instance methods on InputHandler provide multi-line text
    // analysis for correct cursor positioning and display in multi-line mode.

    // MARK: lineCount(of:)

    func testLineCountEmptyString() {
        // Empty string has 1 line (the current empty line)
        let count = InputHandler.lineCount(of: "")
        XCTAssertEqual(count, 1)
    }

    func testLineCountSingleLine() {
        // "hello" has 1 line
        let count = InputHandler.lineCount(of: "hello")
        XCTAssertEqual(count, 1)
    }

    func testLineCountTwoLines() {
        // "hello\nworld" has 2 lines
        let count = InputHandler.lineCount(of: "hello\nworld")
        XCTAssertEqual(count, 2)
    }

    func testLineCountThreeLines() {
        // Two newlines = 3 lines
        let count = InputHandler.lineCount(of: "line1\nline2\nline3")
        XCTAssertEqual(count, 3)
    }

    func testLineCountTrailingNewline() {
        // "hello\n" has 2 lines (second line is empty but exists)
        let count = InputHandler.lineCount(of: "hello\n")
        XCTAssertEqual(count, 2)
    }

    func testLineCountOnlyNewlines() {
        // "\n\n" has 3 lines (all empty)
        let count = InputHandler.lineCount(of: "\n\n")
        XCTAssertEqual(count, 3)
    }

    func testLineCountSingleNewline() {
        // "\n" has 2 lines
        let count = InputHandler.lineCount(of: "\n")
        XCTAssertEqual(count, 2)
    }

    func testLineCountKoreanMultiLine() {
        // Korean text with newline
        let count = InputHandler.lineCount(of: "\u{D55C}\u{AE00}\n\u{D14C}\u{C2A4}\u{D2B8}")
        XCTAssertEqual(count, 2)
    }

    // MARK: currentLineText(in:at:)

    func testCurrentLineTextAtStartOfSingleLine() {
        // Cursor at position 0 in "hello" -> "hello"
        let line = InputHandler.currentLineText(in: "hello", at: 0)
        XCTAssertEqual(line, "hello")
    }

    func testCurrentLineTextAtEndOfSingleLine() {
        // Cursor at position 5 in "hello" -> "hello"
        let line = InputHandler.currentLineText(in: "hello", at: 5)
        XCTAssertEqual(line, "hello")
    }

    func testCurrentLineTextFirstLineOfTwo() {
        // Cursor at position 2 in "hello\nworld" -> "hello"
        // Position 2 is within "hello" (before the newline at position 5)
        let line = InputHandler.currentLineText(in: "hello\nworld", at: 2)
        XCTAssertEqual(line, "hello")
    }

    func testCurrentLineTextSecondLineOfTwo() {
        // Cursor at position 7 in "hello\nworld" -> "world"
        // Position 6 is 'w' (start of second line)
        let line = InputHandler.currentLineText(in: "hello\nworld", at: 7)
        XCTAssertEqual(line, "world")
    }

    func testCurrentLineTextAtNewlineCharacter() {
        // Cursor at position 5 in "hello\nworld" (at the \n itself)
        // Should return the first line "hello" since the cursor is at the
        // end of the first line
        let line = InputHandler.currentLineText(in: "hello\nworld", at: 5)
        XCTAssertEqual(line, "hello")
    }

    func testCurrentLineTextEmptyString() {
        // Cursor at 0 in empty string -> ""
        let line = InputHandler.currentLineText(in: "", at: 0)
        XCTAssertEqual(line, "")
    }

    func testCurrentLineTextMiddleLine() {
        // Cursor in the middle line of three lines
        // "aaa\nbbb\nccc" -> positions: aaa=0-2, \n=3, bbb=4-6, \n=7, ccc=8-10
        let line = InputHandler.currentLineText(in: "aaa\nbbb\nccc", at: 5)
        XCTAssertEqual(line, "bbb")
    }

    func testCurrentLineTextEmptyMiddleLine() {
        // "aaa\n\nccc" has an empty middle line
        // positions: aaa=0-2, \n=3, \n=4, ccc=5-7
        // Cursor at position 4 (the second \n) -> empty line ""
        let line = InputHandler.currentLineText(in: "aaa\n\nccc", at: 4)
        XCTAssertEqual(line, "")
    }

    // MARK: isAtNewlineBoundary(in:at:)

    func testIsAtNewlineBoundaryAtNewline() {
        // Position 5 in "hello\nworld" is the \n character -> true
        let result = InputHandler.isAtNewlineBoundary(in: "hello\nworld", at: 5)
        XCTAssertTrue(result)
    }

    func testIsAtNewlineBoundaryJustAfterNewline() {
        // Position 6 in "hello\nworld" is 'w', just after \n -> true
        let result = InputHandler.isAtNewlineBoundary(in: "hello\nworld", at: 6)
        XCTAssertTrue(result)
    }

    func testIsAtNewlineBoundaryMiddleOfLine() {
        // Position 2 in "hello\nworld" is 'l', not near newline -> false
        let result = InputHandler.isAtNewlineBoundary(in: "hello\nworld", at: 2)
        XCTAssertFalse(result)
    }

    func testIsAtNewlineBoundaryStartOfString() {
        // Position 0 is the start, not a newline boundary -> false
        let result = InputHandler.isAtNewlineBoundary(in: "hello", at: 0)
        XCTAssertFalse(result)
    }

    func testIsAtNewlineBoundaryEndOfString() {
        // Position at end of string without trailing newline -> false
        let result = InputHandler.isAtNewlineBoundary(in: "hello", at: 5)
        XCTAssertFalse(result)
    }

    func testIsAtNewlineBoundaryEmptyString() {
        // Empty string, position 0 -> false
        let result = InputHandler.isAtNewlineBoundary(in: "", at: 0)
        XCTAssertFalse(result)
    }

    func testIsAtNewlineBoundaryConsecutiveNewlines() {
        // "\n\n" at position 0 -> at newline -> true
        let result = InputHandler.isAtNewlineBoundary(in: "\n\n", at: 0)
        XCTAssertTrue(result)
    }

    func testIsAtNewlineBoundaryConsecutiveNewlinesMiddle() {
        // "\n\n" at position 1 -> at newline -> true
        let result = InputHandler.isAtNewlineBoundary(in: "\n\n", at: 1)
        XCTAssertTrue(result)
    }

    // MARK: lastLineOfInput(_:)

    func testLastLineOfInputSingleLine() {
        // "hello" -> "hello"
        let line = InputHandler.lastLineOfInput("hello")
        XCTAssertEqual(line, "hello")
    }

    func testLastLineOfInputMultiLine() {
        // "hello\nworld" -> "world"
        let line = InputHandler.lastLineOfInput("hello\nworld")
        XCTAssertEqual(line, "world")
    }

    func testLastLineOfInputTrailingNewline() {
        // "hello\n" -> "" (empty last line)
        let line = InputHandler.lastLineOfInput("hello\n")
        XCTAssertEqual(line, "")
    }

    func testLastLineOfInputEmptyString() {
        // "" -> ""
        let line = InputHandler.lastLineOfInput("")
        XCTAssertEqual(line, "")
    }

    func testLastLineOfInputMultipleLines() {
        // "a\nb\nc" -> "c"
        let line = InputHandler.lastLineOfInput("a\nb\nc")
        XCTAssertEqual(line, "c")
    }

    func testLastLineOfInputOnlyNewlines() {
        // "\n\n" -> "" (last line after final newline)
        let line = InputHandler.lastLineOfInput("\n\n")
        XCTAssertEqual(line, "")
    }

    func testLastLineOfInputKoreanLastLine() {
        // Korean text on last line
        let line = InputHandler.lastLineOfInput("hello\n\u{D55C}\u{AE00}")
        XCTAssertEqual(line, "\u{D55C}\u{AE00}")
    }

    // =========================================================================
    // MARK: - D. Input Buffer State Management
    // =========================================================================
    //
    // These tests verify state transitions for clearCurrentInput (Ctrl+U)
    // and multi-line input buffer properties exposed for testing.

    // MARK: clearCurrentInput (Ctrl+U)

    func testClearCurrentInputResetsToEmpty() {
        // After setting up some input, clearCurrentInput should empty the buffer
        let handler = InputHandler()
        // Simulate some internal state by using testable properties
        handler.setInputForTesting("hello world")
        handler.clearCurrentInput()
        XCTAssertEqual(handler.currentInput, "")
    }

    func testClearCurrentInputResetsCursorToZero() {
        let handler = InputHandler()
        handler.setInputForTesting("hello world")
        handler.clearCurrentInput()
        XCTAssertEqual(handler.getCursorPosition(), 0)
    }

    func testClearCurrentInputOnEmptyInput() {
        // Clearing an already empty input should be a no-op, not crash
        let handler = InputHandler()
        handler.setInputForTesting("")
        handler.clearCurrentInput()
        XCTAssertEqual(handler.currentInput, "")
        XCTAssertEqual(handler.getCursorPosition(), 0)
    }

    func testClearCurrentInputWithMultiLineInput() {
        // Multi-line input should be fully cleared
        let handler = InputHandler()
        handler.setInputForTesting("line1\nline2\nline3")
        handler.clearCurrentInput()
        XCTAssertEqual(handler.currentInput, "")
        XCTAssertEqual(handler.getCursorPosition(), 0)
    }

    func testClearCurrentInputWithKoreanText() {
        // UTF-8 multi-byte text should be fully cleared
        let handler = InputHandler()
        handler.setInputForTesting("\u{D55C}\u{AE00} \u{D14C}\u{C2A4}\u{D2B8}")
        handler.clearCurrentInput()
        XCTAssertEqual(handler.currentInput, "")
        XCTAssertEqual(handler.getCursorPosition(), 0)
    }

    // MARK: setInputForTesting (test helper)

    func testSetInputForTestingSetsInputAndCursor() {
        // setInputForTesting should set currentInput and move cursor to end
        let handler = InputHandler()
        handler.setInputForTesting("test")
        XCTAssertEqual(handler.currentInput, "test")
        XCTAssertEqual(handler.getCursorPosition(), 4)
    }

    func testSetInputForTestingWithEmptyString() {
        let handler = InputHandler()
        handler.setInputForTesting("")
        XCTAssertEqual(handler.currentInput, "")
        XCTAssertEqual(handler.getCursorPosition(), 0)
    }

    func testSetInputForTestingWithKoreanText() {
        // Korean characters: each is 1 Swift Character, cursor should be at character count
        let handler = InputHandler()
        handler.setInputForTesting("\u{D55C}\u{AE00}")  // 2 characters
        XCTAssertEqual(handler.currentInput, "\u{D55C}\u{AE00}")
        XCTAssertEqual(handler.getCursorPosition(), 2)
    }

    func testSetInputForTestingWithEmoji() {
        // Emoji: each is 1 Swift Character
        let handler = InputHandler()
        handler.setInputForTesting("\u{1F600}\u{1F601}")  // 2 emoji characters
        XCTAssertEqual(handler.currentInput, "\u{1F600}\u{1F601}")
        XCTAssertEqual(handler.getCursorPosition(), 2)
    }

    func testSetInputForTestingWithMultiLineText() {
        // Multi-line text: newlines count as characters
        let handler = InputHandler()
        handler.setInputForTesting("a\nb")  // 3 characters: 'a', '\n', 'b'
        XCTAssertEqual(handler.currentInput, "a\nb")
        XCTAssertEqual(handler.getCursorPosition(), 3)
    }

    // MARK: isPasteMode property

    func testIsPasteModeDefaultFalse() {
        // InputHandler should start with isPasteMode == false
        let handler = InputHandler()
        XCTAssertFalse(handler.isPasteMode)
    }

    // MARK: isMultiLine computed property

    func testIsMultiLineWithSingleLine() {
        // Single-line input should not be multi-line
        let handler = InputHandler()
        handler.setInputForTesting("hello")
        XCTAssertFalse(handler.isMultiLine)
    }

    func testIsMultiLineWithNewlines() {
        // Input containing newlines is multi-line
        let handler = InputHandler()
        handler.setInputForTesting("hello\nworld")
        XCTAssertTrue(handler.isMultiLine)
    }

    func testIsMultiLineWithEmptyInput() {
        // Empty input is not multi-line
        let handler = InputHandler()
        handler.setInputForTesting("")
        XCTAssertFalse(handler.isMultiLine)
    }

    func testIsMultiLineWithTrailingNewline() {
        // Trailing newline means there is a second (empty) line
        let handler = InputHandler()
        handler.setInputForTesting("hello\n")
        XCTAssertTrue(handler.isMultiLine)
    }

    // =========================================================================
    // MARK: - E. CSISequence Enum Existence and Equatable
    // =========================================================================
    //
    // Verify that the CSISequence enum exists, has the expected cases,
    // and conforms to Equatable.

    func testCSISequenceArrowUpEquality() {
        XCTAssertEqual(CSISequence.arrowUp, CSISequence.arrowUp)
        XCTAssertNotEqual(CSISequence.arrowUp, CSISequence.arrowDown)
    }

    func testCSISequencePasteStartEquality() {
        XCTAssertEqual(CSISequence.pasteStart, CSISequence.pasteStart)
        XCTAssertNotEqual(CSISequence.pasteStart, CSISequence.pasteEnd)
    }

    func testCSISequenceShiftEnterEquality() {
        XCTAssertEqual(CSISequence.shiftEnter, CSISequence.shiftEnter)
        XCTAssertNotEqual(CSISequence.shiftEnter, CSISequence.arrowUp)
    }

    func testCSISequenceUnknownEquality() {
        XCTAssertEqual(CSISequence.unknown([1, 2, 3]), CSISequence.unknown([1, 2, 3]))
        XCTAssertNotEqual(CSISequence.unknown([1, 2, 3]), CSISequence.unknown([4, 5, 6]))
    }

    func testCSISequenceAllCasesDistinct() {
        // Every named case should be distinct from every other named case
        let cases: [CSISequence] = [
            .arrowUp, .arrowDown, .arrowRight, .arrowLeft,
            .optionArrowLeft, .optionArrowRight, .cmdArrowLeft, .cmdArrowRight,
            .home, .end, .delete,
            .pasteStart, .pasteEnd,
            .shiftEnter
        ]
        for i in 0..<cases.count {
            for j in (i + 1)..<cases.count {
                XCTAssertNotEqual(
                    cases[i], cases[j],
                    "\(cases[i]) should not equal \(cases[j])"
                )
            }
        }
    }

    // MARK: Option+Arrow and Cmd+Arrow Sequences

    func testParseCSISequenceOptionArrowLeft() {
        // ESC [ 1;3D -> optionArrowLeft
        // Byte sequence after ESC[: "1;3D" = [49, 59, 51, 68]
        let result = InputHandler.parseCSISequence([49, 59, 51, 68])
        XCTAssertEqual(result, CSISequence.optionArrowLeft)
    }

    func testParseCSISequenceOptionArrowRight() {
        // ESC [ 1;3C -> optionArrowRight
        // Byte sequence after ESC[: "1;3C" = [49, 59, 51, 67]
        let result = InputHandler.parseCSISequence([49, 59, 51, 67])
        XCTAssertEqual(result, CSISequence.optionArrowRight)
    }

    func testParseCSISequenceCmdArrowLeft() {
        // ESC [ 1;9D -> cmdArrowLeft
        // Byte sequence after ESC[: "1;9D" = [49, 59, 57, 68]
        let result = InputHandler.parseCSISequence([49, 59, 57, 68])
        XCTAssertEqual(result, CSISequence.cmdArrowLeft)
    }

    func testParseCSISequenceCmdArrowRight() {
        // ESC [ 1;9C -> cmdArrowRight
        // Byte sequence after ESC[: "1;9C" = [49, 59, 57, 67]
        let result = InputHandler.parseCSISequence([49, 59, 57, 67])
        XCTAssertEqual(result, CSISequence.cmdArrowRight)
    }

    func testParseCSISequenceOptionArrowDistinctFromRegular() {
        // Option+Arrow sequences should be different from regular arrow sequences
        let optionLeft = InputHandler.parseCSISequence([49, 59, 51, 68])
        let regularLeft = InputHandler.parseCSISequence([68])
        XCTAssertNotEqual(optionLeft, regularLeft)
        XCTAssertEqual(optionLeft, CSISequence.optionArrowLeft)
        XCTAssertEqual(regularLeft, CSISequence.arrowLeft)
    }

    func testParseCSISequenceCmdArrowDistinctFromHome() {
        // Cmd+Arrow sequences should be different from home/end sequences
        let cmdLeft = InputHandler.parseCSISequence([49, 59, 57, 68])
        let home = InputHandler.parseCSISequence([72])
        XCTAssertNotEqual(cmdLeft, home)
        XCTAssertEqual(cmdLeft, CSISequence.cmdArrowLeft)
        XCTAssertEqual(home, CSISequence.home)
    }

    // =========================================================================
    // MARK: - F. Bracketed Paste Mode Integration
    // =========================================================================
    //
    // These tests verify the bracketed paste mode enable/disable escape
    // sequence strings that InputHandler should expose.

    func testBracketedPasteEnableSequence() {
        // The ANSI escape sequence to enable bracketed paste mode
        XCTAssertEqual(InputHandler.bracketedPasteEnable, "\u{001B}[?2004h")
    }

    func testBracketedPasteDisableSequence() {
        // The ANSI escape sequence to disable bracketed paste mode
        XCTAssertEqual(InputHandler.bracketedPasteDisable, "\u{001B}[?2004l")
    }

    // =========================================================================
    // MARK: - G. Double-ESC Input Clear
    // =========================================================================
    //
    // Feature: Pressing ESC twice quickly clears the current input line.
    //
    // When the user presses ESC (byte 27) and readInput() reads a second ESC
    // as the next byte, InputHandler should determine whether this is a genuine
    // double-ESC gesture (user wants to clear input) vs. the second ESC being
    // the start of a CSI sequence (e.g., ESC followed by an arrow key which
    // sends ESC [ A).
    //
    // Three new methods are required on InputHandler:
    //
    //   static func isDoubleEscape(followingByte: UInt8?) -> Bool
    //     - Pure logic to classify the byte after the second ESC
    //     - Returns true if followingByte is nil (no pending data = genuine double-ESC)
    //     - Returns true if followingByte != 91 ('[') (not a CSI start = genuine)
    //     - Returns false if followingByte == 91 (CSI sequence start = not double-ESC)
    //
    //   static func hasPendingInput(timeoutMs: Int32) -> Bool
    //     - Thin wrapper around POSIX poll() to check if stdin has pending bytes
    //     - IO-dependent; we only verify it compiles and is callable
    //
    //   func performDoubleEscapeClear()
    //     - Clears currentInput to "" and resets cursorPosition to 0
    //     - The terminal ANSI output (clearing display) cannot be verified in
    //       unit tests, so we only test the state changes
    //
    // These tests will FAIL because the methods do not yet exist.

    // MARK: isDoubleEscape - Pure Logic

    func testIsDoubleEscapeWithNoFollowingByte() {
        // When followingByte is nil, there are no more bytes in the buffer.
        // This means the user genuinely pressed ESC twice with nothing after,
        // so it should be recognized as a double-ESC gesture.
        let result = InputHandler.isDoubleEscape(followingByte: nil)
        XCTAssertTrue(result, "nil followingByte means no pending data; should be double-ESC")
    }

    func testIsDoubleEscapeWithCSIBracket() {
        // When followingByte is 91 ('['), the second ESC starts a CSI sequence.
        // For example: user presses ESC then arrow-up sends ESC [ A.
        // The first ESC was consumed, the second ESC + '[' + 'A' is a CSI.
        // This is NOT a double-ESC gesture.
        let result = InputHandler.isDoubleEscape(followingByte: 91)
        XCTAssertFalse(result, "followingByte 91 ('[') means CSI start; should NOT be double-ESC")
    }

    func testIsDoubleEscapeWithAnotherEsc() {
        // When followingByte is 27 (another ESC), it is still not a '['.
        // This could happen with rapid triple-ESC presses. Since 27 != 91,
        // the second ESC pair is still recognized as double-ESC.
        let result = InputHandler.isDoubleEscape(followingByte: 27)
        XCTAssertTrue(result, "followingByte 27 (ESC) is not '['; should be double-ESC")
    }

    func testIsDoubleEscapeWithPrintableByte() {
        // When followingByte is 65 ('A'), it is a printable character but NOT '['.
        // Since this is not the start of a CSI sequence, the double-ESC gesture
        // should still be recognized.
        let result = InputHandler.isDoubleEscape(followingByte: 65)
        XCTAssertTrue(result, "followingByte 65 ('A') is not '['; should be double-ESC")
    }

    func testIsDoubleEscapeWithZeroByte() {
        // When followingByte is 0 (NUL), it is not '['.
        // Edge case: zero byte should still be treated as non-CSI.
        let result = InputHandler.isDoubleEscape(followingByte: 0)
        XCTAssertTrue(result, "followingByte 0 (NUL) is not '['; should be double-ESC")
    }

    // MARK: performDoubleEscapeClear - State Changes

    func testPerformDoubleEscapeClearResetsInput() {
        // Arrange: set up a handler with some input text
        let handler = InputHandler()
        handler.setInputForTesting("hello world")
        XCTAssertEqual(handler.currentInput, "hello world", "precondition: input should be set")

        // Act: perform the double-ESC clear
        handler.performDoubleEscapeClear()

        // Assert: currentInput should be empty
        XCTAssertEqual(handler.currentInput, "", "currentInput should be cleared after double-ESC")
    }

    func testPerformDoubleEscapeClearResetsCursor() {
        // Arrange: set up input so cursor is at the end (position 5)
        let handler = InputHandler()
        handler.setInputForTesting("hello")
        XCTAssertEqual(handler.getCursorPosition(), 5, "precondition: cursor at end of 'hello'")

        // Act
        handler.performDoubleEscapeClear()

        // Assert: cursor should be reset to 0
        XCTAssertEqual(handler.getCursorPosition(), 0, "cursorPosition should be 0 after clear")
    }

    func testPerformDoubleEscapeClearOnEmptyInput() {
        // Edge case: clearing when input is already empty should not crash
        // and should remain in a valid empty state.
        let handler = InputHandler()
        handler.setInputForTesting("")
        XCTAssertEqual(handler.currentInput, "", "precondition: input is empty")
        XCTAssertEqual(handler.getCursorPosition(), 0, "precondition: cursor at 0")

        // Act: should be a safe no-op
        handler.performDoubleEscapeClear()

        // Assert: still empty, still at position 0
        XCTAssertEqual(handler.currentInput, "", "input should remain empty")
        XCTAssertEqual(handler.getCursorPosition(), 0, "cursor should remain at 0")
    }

    func testPerformDoubleEscapeClearWithKoreanInput() {
        // Clearing Korean (multi-byte UTF-8) input should fully reset the buffer.
        // Each Korean character is 1 Swift Character but 3 UTF-8 bytes.
        let handler = InputHandler()
        handler.setInputForTesting("\u{D55C}\u{AE00} \u{D14C}\u{C2A4}\u{D2B8}")  // "han-geul test" in Korean
        XCTAssertFalse(handler.currentInput.isEmpty, "precondition: input is non-empty Korean text")

        // Act
        handler.performDoubleEscapeClear()

        // Assert
        XCTAssertEqual(handler.currentInput, "", "Korean input should be fully cleared")
        XCTAssertEqual(handler.getCursorPosition(), 0, "cursor should be 0 after clearing Korean text")
    }

    func testPerformDoubleEscapeClearWithMultiLineInput() {
        // Multi-line input (containing newlines) should be fully cleared.
        let handler = InputHandler()
        handler.setInputForTesting("line1\nline2")
        XCTAssertTrue(handler.isMultiLine, "precondition: input should be multi-line")

        // Act
        handler.performDoubleEscapeClear()

        // Assert
        XCTAssertEqual(handler.currentInput, "", "multi-line input should be fully cleared")
        XCTAssertEqual(handler.getCursorPosition(), 0, "cursor should be 0 after clearing multi-line")
    }

    func testPerformDoubleEscapeClearLeavesIsMultiLineFalse() {
        // After clearing multi-line input, isMultiLine should be false because
        // the currentInput is now empty (no newlines).
        let handler = InputHandler()
        handler.setInputForTesting("first\nsecond\nthird")
        XCTAssertTrue(handler.isMultiLine, "precondition: multi-line")

        // Act
        handler.performDoubleEscapeClear()

        // Assert: empty string contains no newlines, so isMultiLine must be false
        XCTAssertFalse(handler.isMultiLine, "isMultiLine should be false after clearing input")
    }
}
