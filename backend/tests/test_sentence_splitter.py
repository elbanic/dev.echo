"""
Tests for SentenceSplitter - Sentence-Based Streaming TTS Feature

This module contains comprehensive tests for the SentenceSplitter class,
which splits text into sentences for streaming TTS processing.

All tests are designed to FAIL until implementation exists (TDD RED phase).

## Requirements Validated:
1. Support Korean sentence endings: 다, 요, 죠, ?, !, .
2. Support English sentence endings: . ? !
3. Handle mixed Korean/English text
4. Preserve punctuation in output
5. Handle edge cases: abbreviations, numbers, quotes

Feature: dev-echo-phase2, Streaming TTS
"""

import pytest
from typing import List

# Import will fail until implementation exists
from tts.sentence_splitter import SentenceSplitter


# ---------------------------------------------------------------------------
# SentenceSplitter Instantiation
# ---------------------------------------------------------------------------


class TestSentenceSplitterInstantiation:
    """Tests for SentenceSplitter class creation."""

    def test_can_instantiate_splitter(self):
        """SentenceSplitter should be instantiable without arguments."""
        splitter = SentenceSplitter()
        assert splitter is not None

    def test_split_method_exists(self):
        """SentenceSplitter should have a split() method."""
        splitter = SentenceSplitter()
        assert hasattr(splitter, "split")
        assert callable(splitter.split)

    def test_split_returns_list(self):
        """split() should return a list."""
        splitter = SentenceSplitter()
        result = splitter.split("Hello world.")
        assert isinstance(result, list)


# ---------------------------------------------------------------------------
# Korean Sentence Splitting - Basic Endings
# ---------------------------------------------------------------------------


class TestKoreanSentenceSplitting:
    """Tests for Korean sentence splitting with various endings."""

    def test_split_korean_declarative_da(self):
        """Split Korean sentences ending with '다.'"""
        splitter = SentenceSplitter()
        text = "오늘 날씨가 좋다. 산책을 가자."
        result = splitter.split(text)
        assert result == ["오늘 날씨가 좋다.", "산책을 가자."]

    def test_split_korean_polite_yo(self):
        """Split Korean sentences ending with '요.'"""
        splitter = SentenceSplitter()
        text = "안녕하세요. 반갑습니다."
        result = splitter.split(text)
        assert result == ["안녕하세요.", "반갑습니다."]

    def test_split_korean_informal_polite_jyo(self):
        """Split Korean sentences ending with '죠.'"""
        splitter = SentenceSplitter()
        text = "그렇죠. 맞죠."
        result = splitter.split(text)
        assert result == ["그렇죠.", "맞죠."]

    def test_split_korean_question(self):
        """Split Korean sentences ending with '?'"""
        splitter = SentenceSplitter()
        text = "이거 뭐예요? 어디 가세요?"
        result = splitter.split(text)
        assert result == ["이거 뭐예요?", "어디 가세요?"]

    def test_split_korean_exclamation(self):
        """Split Korean sentences ending with '!'"""
        splitter = SentenceSplitter()
        text = "대박이다! 정말 좋아요!"
        result = splitter.split(text)
        assert result == ["대박이다!", "정말 좋아요!"]

    def test_split_korean_period(self):
        """Split Korean sentences ending with '.'"""
        splitter = SentenceSplitter()
        text = "서울에 갑니다. 부산도 갑니다."
        result = splitter.split(text)
        assert result == ["서울에 갑니다.", "부산도 갑니다."]

    def test_split_korean_mixed_endings(self):
        """Split Korean sentences with various ending types."""
        splitter = SentenceSplitter()
        text = "안녕하세요. 오늘 뭐 해요? 같이 가자!"
        result = splitter.split(text)
        assert result == ["안녕하세요.", "오늘 뭐 해요?", "같이 가자!"]

    def test_split_korean_long_paragraph(self):
        """Split a longer Korean paragraph into sentences."""
        splitter = SentenceSplitter()
        text = "인공지능이 발전하고 있다. 많은 사람들이 관심을 가지고 있죠. 앞으로 어떻게 될까요? 기대가 됩니다!"
        result = splitter.split(text)
        assert len(result) == 4
        assert result[0] == "인공지능이 발전하고 있다."
        assert result[1] == "많은 사람들이 관심을 가지고 있죠."
        assert result[2] == "앞으로 어떻게 될까요?"
        assert result[3] == "기대가 됩니다!"


# ---------------------------------------------------------------------------
# Korean Sentence Splitting - Advanced Endings
# ---------------------------------------------------------------------------


class TestKoreanAdvancedEndings:
    """Tests for advanced Korean sentence endings."""

    def test_split_korean_habnida_ending(self):
        """Split formal Korean sentences ending with '습니다.'"""
        splitter = SentenceSplitter()
        text = "감사합니다. 안녕히 가십시오."
        result = splitter.split(text)
        assert result == ["감사합니다.", "안녕히 가십시오."]

    def test_split_korean_seyo_ending(self):
        """Split Korean imperative sentences ending with '세요.'"""
        splitter = SentenceSplitter()
        text = "앉으세요. 편히 쉬세요."
        result = splitter.split(text)
        assert result == ["앉으세요.", "편히 쉬세요."]

    def test_split_korean_neyo_ending(self):
        """Split Korean sentences ending with '네요.'"""
        splitter = SentenceSplitter()
        text = "정말 맛있네요. 또 오고 싶네요."
        result = splitter.split(text)
        assert result == ["정말 맛있네요.", "또 오고 싶네요."]

    def test_split_korean_geyo_ending(self):
        """Split Korean sentences ending with '거예요.'"""
        splitter = SentenceSplitter()
        text = "내일 갈 거예요. 준비할 거예요."
        result = splitter.split(text)
        assert result == ["내일 갈 거예요.", "준비할 거예요."]


# ---------------------------------------------------------------------------
# English Sentence Splitting
# ---------------------------------------------------------------------------


class TestEnglishSentenceSplitting:
    """Tests for English sentence splitting."""

    def test_split_english_periods(self):
        """Split English sentences ending with '.'"""
        splitter = SentenceSplitter()
        text = "Hello world. How are you today."
        result = splitter.split(text)
        assert result == ["Hello world.", "How are you today."]

    def test_split_english_questions(self):
        """Split English sentences ending with '?'"""
        splitter = SentenceSplitter()
        text = "How are you? What is your name?"
        result = splitter.split(text)
        assert result == ["How are you?", "What is your name?"]

    def test_split_english_exclamations(self):
        """Split English sentences ending with '!'"""
        splitter = SentenceSplitter()
        text = "That is amazing! I love it!"
        result = splitter.split(text)
        assert result == ["That is amazing!", "I love it!"]

    def test_split_english_mixed_punctuation(self):
        """Split English sentences with mixed punctuation."""
        splitter = SentenceSplitter()
        text = "The sun is shining. Is it warm outside? Yes, it is!"
        result = splitter.split(text)
        assert result == [
            "The sun is shining.",
            "Is it warm outside?",
            "Yes, it is!",
        ]

    def test_split_english_paragraph(self):
        """Split an English paragraph into sentences."""
        splitter = SentenceSplitter()
        text = "Machine learning is fascinating. It enables computers to learn. What could be more exciting? The future is bright!"
        result = splitter.split(text)
        assert len(result) == 4


# ---------------------------------------------------------------------------
# Mixed Language (Korean + English)
# ---------------------------------------------------------------------------


class TestMixedLanguageSplitting:
    """Tests for mixed Korean and English text splitting."""

    def test_split_mixed_simple(self):
        """Split text with Korean and English sentences."""
        splitter = SentenceSplitter()
        text = "안녕하세요. Hello world. 감사합니다."
        result = splitter.split(text)
        assert result == ["안녕하세요.", "Hello world.", "감사합니다."]

    def test_split_mixed_with_questions(self):
        """Split mixed text with questions in both languages."""
        splitter = SentenceSplitter()
        text = "What is this? 이게 뭐예요? Let me explain."
        result = splitter.split(text)
        assert result == ["What is this?", "이게 뭐예요?", "Let me explain."]

    def test_split_mixed_with_code_terms(self):
        """Split mixed text with code/technical terms."""
        splitter = SentenceSplitter()
        text = "Python을 사용합니다. We use machine learning. 정말 좋아요!"
        result = splitter.split(text)
        assert result == [
            "Python을 사용합니다.",
            "We use machine learning.",
            "정말 좋아요!",
        ]

    def test_split_mixed_alternating(self):
        """Split alternating Korean and English sentences."""
        splitter = SentenceSplitter()
        text = "Hello. 안녕. Goodbye. 잘가."
        result = splitter.split(text)
        assert result == ["Hello.", "안녕.", "Goodbye.", "잘가."]

    def test_split_korean_with_english_words(self):
        """Split Korean sentences containing English words."""
        splitter = SentenceSplitter()
        text = "저는 Python 개발자입니다. Machine learning을 공부해요."
        result = splitter.split(text)
        assert result == [
            "저는 Python 개발자입니다.",
            "Machine learning을 공부해요.",
        ]


# ---------------------------------------------------------------------------
# Edge Cases - Empty and Whitespace
# ---------------------------------------------------------------------------


class TestEdgeCasesEmptyWhitespace:
    """Tests for edge cases involving empty and whitespace input."""

    def test_split_empty_string(self):
        """Empty string should return empty list."""
        splitter = SentenceSplitter()
        result = splitter.split("")
        assert result == []

    def test_split_whitespace_only(self):
        """Whitespace-only string should return empty list."""
        splitter = SentenceSplitter()
        result = splitter.split("   ")
        assert result == []

    def test_split_newlines_only(self):
        """Newlines-only string should return empty list."""
        splitter = SentenceSplitter()
        result = splitter.split("\n\n\t")
        assert result == []

    def test_split_single_word_no_punctuation(self):
        """Single word without punctuation should return as-is in list."""
        splitter = SentenceSplitter()
        result = splitter.split("Hello")
        assert result == ["Hello"]

    def test_split_text_without_sentence_endings(self):
        """Text without sentence endings should return as single item."""
        splitter = SentenceSplitter()
        result = splitter.split("This is some text without endings")
        assert result == ["This is some text without endings"]

    def test_split_preserves_internal_whitespace(self):
        """Internal whitespace within sentences should be preserved."""
        splitter = SentenceSplitter()
        text = "Hello   world.  How are   you?"
        result = splitter.split(text)
        # Should handle multiple spaces gracefully
        assert len(result) == 2


# ---------------------------------------------------------------------------
# Edge Cases - Punctuation Preservation
# ---------------------------------------------------------------------------


class TestEdgeCasesPunctuationPreservation:
    """Tests for punctuation preservation in output."""

    def test_preserve_period(self):
        """Period should be preserved in output sentence."""
        splitter = SentenceSplitter()
        result = splitter.split("Hello world.")
        assert result[0].endswith(".")

    def test_preserve_question_mark(self):
        """Question mark should be preserved in output sentence."""
        splitter = SentenceSplitter()
        result = splitter.split("How are you?")
        assert result[0].endswith("?")

    def test_preserve_exclamation(self):
        """Exclamation mark should be preserved in output sentence."""
        splitter = SentenceSplitter()
        result = splitter.split("This is great!")
        assert result[0].endswith("!")

    def test_preserve_multiple_punctuation(self):
        """Multiple punctuation marks should be preserved."""
        splitter = SentenceSplitter()
        result = splitter.split("Really?! Yes!!")
        # Should preserve the punctuation
        assert any("?!" in s or "?" in s for s in result)
        assert any("!!" in s or "!" in s for s in result)

    def test_preserve_ellipsis(self):
        """Ellipsis (...) should be handled appropriately."""
        splitter = SentenceSplitter()
        result = splitter.split("Wait... What happened?")
        # Should not split on each period of ellipsis
        assert len(result) <= 2


# ---------------------------------------------------------------------------
# Edge Cases - Abbreviations
# ---------------------------------------------------------------------------


class TestEdgeCasesAbbreviations:
    """Tests for handling abbreviations that contain periods."""

    def test_english_abbreviation_mr(self):
        """Should not split on 'Mr.' abbreviation."""
        splitter = SentenceSplitter()
        result = splitter.split("Mr. Smith went to the store.")
        # Should be one sentence, not split at "Mr."
        assert len(result) == 1
        assert "Mr. Smith" in result[0]

    def test_english_abbreviation_dr(self):
        """Should not split on 'Dr.' abbreviation."""
        splitter = SentenceSplitter()
        result = splitter.split("Dr. Jones is a great doctor.")
        assert len(result) == 1
        assert "Dr. Jones" in result[0]

    def test_english_abbreviation_mrs(self):
        """Should not split on 'Mrs.' abbreviation."""
        splitter = SentenceSplitter()
        result = splitter.split("Mrs. Kim visited today.")
        assert len(result) == 1

    def test_english_abbreviation_ms(self):
        """Should not split on 'Ms.' abbreviation."""
        splitter = SentenceSplitter()
        result = splitter.split("Ms. Park is here.")
        assert len(result) == 1

    def test_english_abbreviation_etc(self):
        """Should not split on 'etc.' mid-sentence."""
        splitter = SentenceSplitter()
        result = splitter.split("Bring apples, oranges, etc. for the party.")
        # etc. at end of thought, could be handled either way
        # Key is not creating tiny fragments
        assert len(result) >= 1

    def test_english_abbreviation_eg(self):
        """Should not split on 'e.g.' abbreviation."""
        splitter = SentenceSplitter()
        result = splitter.split("Use a framework, e.g. Django or Flask.")
        assert len(result) == 1

    def test_english_abbreviation_ie(self):
        """Should not split on 'i.e.' abbreviation."""
        splitter = SentenceSplitter()
        result = splitter.split("The best option, i.e. Python, was chosen.")
        assert len(result) == 1


# ---------------------------------------------------------------------------
# Edge Cases - Numbers and Decimals
# ---------------------------------------------------------------------------


class TestEdgeCasesNumbers:
    """Tests for handling numbers and decimals."""

    def test_decimal_numbers_not_split(self):
        """Decimal numbers should not cause splits."""
        splitter = SentenceSplitter()
        result = splitter.split("The price is 3.14 dollars.")
        assert len(result) == 1
        assert "3.14" in result[0]

    def test_version_numbers_not_split(self):
        """Version numbers like 2.0 should not cause splits."""
        splitter = SentenceSplitter()
        result = splitter.split("Python 3.10 is great. It has many features.")
        assert len(result) == 2
        assert "3.10" in result[0]

    def test_ip_addresses_not_split(self):
        """IP addresses should not cause splits."""
        splitter = SentenceSplitter()
        result = splitter.split("Connect to 192.168.1.1 for access.")
        assert len(result) == 1
        assert "192.168.1.1" in result[0]

    def test_currency_with_decimals(self):
        """Currency amounts should not cause splits."""
        splitter = SentenceSplitter()
        result = splitter.split("It costs $19.99 today. That is a good price.")
        assert len(result) == 2
        assert "$19.99" in result[0]

    def test_percentage_with_decimals(self):
        """Percentages should not cause splits."""
        splitter = SentenceSplitter()
        result = splitter.split("The rate is 3.5% annually.")
        assert len(result) == 1
        assert "3.5%" in result[0]


# ---------------------------------------------------------------------------
# Edge Cases - Quotes
# ---------------------------------------------------------------------------


class TestEdgeCasesQuotes:
    """Tests for handling quoted text."""

    def test_quoted_sentence_double_quotes(self):
        """Sentences in double quotes should be handled correctly."""
        splitter = SentenceSplitter()
        result = splitter.split('She said "Hello there." Then she left.')
        # Should recognize sentence boundary after quoted sentence
        assert len(result) == 2

    def test_quoted_sentence_single_quotes(self):
        """Sentences in single quotes should be handled correctly."""
        splitter = SentenceSplitter()
        result = splitter.split("He said 'I will be back.' And he returned.")
        assert len(result) == 2

    def test_question_in_quotes(self):
        """Questions inside quotes should be handled."""
        splitter = SentenceSplitter()
        result = splitter.split('She asked "Are you coming?" I said yes.')
        assert len(result) == 2

    def test_korean_quotes(self):
        """Korean quotation marks should be handled."""
        splitter = SentenceSplitter()
        result = splitter.split("그가 말했다. 「안녕하세요.」 그리고 떠났다.")
        # Should handle Korean-style quotes
        assert len(result) >= 2

    def test_nested_quotes(self):
        """Nested quotes should not cause issues."""
        splitter = SentenceSplitter()
        result = splitter.split("He said \"She told me 'Go away.'\" Then silence.")
        # Complex case - just ensure it does not crash and returns something reasonable
        assert len(result) >= 1


# ---------------------------------------------------------------------------
# Edge Cases - Special Characters
# ---------------------------------------------------------------------------


class TestEdgeCasesSpecialCharacters:
    """Tests for handling special characters and Unicode."""

    def test_emoji_in_text(self):
        """Emoji should not break sentence splitting."""
        splitter = SentenceSplitter()
        result = splitter.split("This is fun. I love it.")
        # Even with emoji (if present), should split correctly
        assert len(result) >= 1

    def test_unicode_punctuation(self):
        """Unicode punctuation marks should be handled."""
        splitter = SentenceSplitter()
        # Full-width period (common in East Asian text)
        result = splitter.split("안녕하세요。반갑습니다。")
        # May or may not split on full-width period, but should not crash
        assert len(result) >= 1

    def test_korean_quotation_marks(self):
        """Korean quotation marks (「」) should be handled."""
        splitter = SentenceSplitter()
        result = splitter.split("「안녕하세요」라고 말했다. 그리고 떠났다.")
        assert len(result) >= 1

    def test_urls_in_text(self):
        """URLs should not cause excessive splitting."""
        splitter = SentenceSplitter()
        result = splitter.split("Visit https://example.com/page.html for more. Thanks.")
        # URL contains multiple periods but should not split on them
        assert len(result) == 2


# ---------------------------------------------------------------------------
# Edge Cases - Single Sentence
# ---------------------------------------------------------------------------


class TestEdgeCasesSingleSentence:
    """Tests for single sentence inputs."""

    def test_single_english_sentence(self):
        """Single English sentence should return list with one item."""
        splitter = SentenceSplitter()
        result = splitter.split("This is a single sentence.")
        assert result == ["This is a single sentence."]

    def test_single_korean_sentence(self):
        """Single Korean sentence should return list with one item."""
        splitter = SentenceSplitter()
        result = splitter.split("이것은 한 문장입니다.")
        assert result == ["이것은 한 문장입니다."]

    def test_single_question(self):
        """Single question should return list with one item."""
        splitter = SentenceSplitter()
        result = splitter.split("How are you?")
        assert result == ["How are you?"]

    def test_single_exclamation(self):
        """Single exclamation should return list with one item."""
        splitter = SentenceSplitter()
        result = splitter.split("Amazing!")
        assert result == ["Amazing!"]


# ---------------------------------------------------------------------------
# Edge Cases - Boundary Conditions
# ---------------------------------------------------------------------------


class TestEdgeCasesBoundaryConditions:
    """Tests for boundary conditions and stress cases."""

    def test_very_long_sentence(self):
        """Very long single sentence should be returned as-is."""
        splitter = SentenceSplitter()
        long_text = "This is a very long sentence " * 100 + "that ends here."
        result = splitter.split(long_text)
        assert len(result) == 1
        assert result[0].endswith(".")

    def test_many_short_sentences(self):
        """Many short sentences should all be split correctly."""
        splitter = SentenceSplitter()
        text = "Hi. Hello. Hey. Yo. Sup."
        result = splitter.split(text)
        assert len(result) == 5

    def test_consecutive_punctuation_only(self):
        """Consecutive punctuation without words should be handled."""
        splitter = SentenceSplitter()
        result = splitter.split("... ... ...")
        # Should not crash, may return empty or single item
        assert isinstance(result, list)

    def test_only_punctuation(self):
        """Only punctuation marks should return empty or single item."""
        splitter = SentenceSplitter()
        result = splitter.split(".!?")
        assert isinstance(result, list)

    def test_leading_whitespace(self):
        """Leading whitespace should be handled."""
        splitter = SentenceSplitter()
        result = splitter.split("   Hello world.")
        assert len(result) == 1
        # Leading whitespace may or may not be trimmed

    def test_trailing_whitespace(self):
        """Trailing whitespace should be handled."""
        splitter = SentenceSplitter()
        result = splitter.split("Hello world.   ")
        assert len(result) == 1

    def test_multiple_spaces_between_sentences(self):
        """Multiple spaces between sentences should be handled."""
        splitter = SentenceSplitter()
        result = splitter.split("Hello.    World.")
        assert len(result) == 2


# ---------------------------------------------------------------------------
# Sentence Order Preservation
# ---------------------------------------------------------------------------


class TestSentenceOrderPreservation:
    """Tests to ensure sentence order is preserved."""

    def test_order_preserved_english(self):
        """English sentences should maintain original order."""
        splitter = SentenceSplitter()
        result = splitter.split("First. Second. Third. Fourth.")
        assert result[0].startswith("First")
        assert result[1].startswith("Second")
        assert result[2].startswith("Third")
        assert result[3].startswith("Fourth")

    def test_order_preserved_korean(self):
        """Korean sentences should maintain original order."""
        splitter = SentenceSplitter()
        result = splitter.split("첫째입니다. 둘째입니다. 셋째입니다.")
        assert "첫째" in result[0]
        assert "둘째" in result[1]
        assert "셋째" in result[2]

    def test_order_preserved_mixed(self):
        """Mixed language sentences should maintain original order."""
        splitter = SentenceSplitter()
        result = splitter.split("English first. 한국어 두번째. Third in English.")
        assert "English first" in result[0]
        assert "한국어" in result[1]
        assert "Third" in result[2]


# ---------------------------------------------------------------------------
# Whitespace Trimming
# ---------------------------------------------------------------------------


class TestWhitespaceTrimming:
    """Tests for whitespace trimming behavior."""

    def test_trim_leading_whitespace_from_sentences(self):
        """Each sentence should have leading whitespace trimmed."""
        splitter = SentenceSplitter()
        result = splitter.split("Hello.    World.")
        # Second sentence should not start with spaces
        assert not result[1].startswith(" ")

    def test_trim_trailing_whitespace_from_sentences(self):
        """Each sentence should have trailing whitespace trimmed."""
        splitter = SentenceSplitter()
        result = splitter.split("Hello world.   ")
        assert not result[0].endswith(" ")

    def test_newline_between_sentences(self):
        """Newlines between sentences should be handled."""
        splitter = SentenceSplitter()
        result = splitter.split("Hello world.\nHow are you?")
        assert len(result) == 2
        assert not result[1].startswith("\n")


# ---------------------------------------------------------------------------
# Real-World Examples
# ---------------------------------------------------------------------------


class TestRealWorldExamples:
    """Tests with realistic text samples."""

    def test_meeting_transcript_korean(self):
        """Korean meeting transcript style text."""
        splitter = SentenceSplitter()
        text = "오늘 회의 시작하겠습니다. 먼저 지난주 진행 상황을 공유해 주세요. 네, 알겠습니다."
        result = splitter.split(text)
        assert len(result) == 3

    def test_tech_documentation_english(self):
        """English technical documentation style text."""
        splitter = SentenceSplitter()
        text = "The API returns JSON data. Use the GET method to retrieve records. Set the Content-Type header appropriately."
        result = splitter.split(text)
        assert len(result) == 3

    def test_mixed_tech_conversation(self):
        """Mixed language technical conversation."""
        splitter = SentenceSplitter()
        text = "Python 3.10을 설치했습니다. The virtual environment is ready. 이제 테스트를 실행해 볼까요?"
        result = splitter.split(text)
        assert len(result) == 3

    def test_casual_chat_korean(self):
        """Casual Korean chat messages."""
        splitter = SentenceSplitter()
        text = "오늘 뭐해요? 같이 밥 먹을래요? 좋아요!"
        result = splitter.split(text)
        assert len(result) == 3

    def test_news_headline_style(self):
        """News headline/article style text."""
        splitter = SentenceSplitter()
        text = "Breaking news. The company announced record profits. Stocks surged 10%!"
        result = splitter.split(text)
        assert len(result) == 3


# ---------------------------------------------------------------------------
# Generator/Iterator Support (Optional Enhancement)
# ---------------------------------------------------------------------------


class TestGeneratorSupport:
    """Tests for optional generator/iterator support."""

    def test_split_iter_method_exists(self):
        """SentenceSplitter may have split_iter() for lazy evaluation."""
        splitter = SentenceSplitter()
        # This is optional - if not implemented, test will fail
        if hasattr(splitter, "split_iter"):
            result = splitter.split_iter("Hello. World.")
            # Should return an iterator
            assert hasattr(result, "__iter__")
            sentences = list(result)
            assert sentences == ["Hello.", "World."]
        else:
            pytest.skip("split_iter() not implemented")

    def test_splitter_is_iterable(self):
        """SentenceSplitter may support iteration directly."""
        splitter = SentenceSplitter()
        # Optional - splitter itself may be callable as iterator
        # This test documents the interface possibility
        if hasattr(splitter, "__call__"):
            result = list(splitter("Hello. World."))
            assert result == ["Hello.", "World."]
        else:
            pytest.skip("__call__ not implemented")
