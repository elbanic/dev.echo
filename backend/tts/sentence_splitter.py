"""
Sentence Splitter Module

The SentenceSplitter class splits text into sentences for streaming TTS processing.

Supports:
1. Korean sentence endings: 다, 요, 죠, 습니다, 세요, 네요, 거예요 + . ? !
2. English sentence endings: . ? !
3. Mixed Korean/English text
4. Punctuation preservation in output
5. Edge cases: abbreviations, numbers, quotes, URLs
"""

import re
from typing import Iterator, List


class SentenceSplitter:
    """Splits text into sentences for streaming TTS processing.

    Handles both Korean and English text with proper sentence boundary detection.
    Preserves punctuation and handles common edge cases like abbreviations,
    decimal numbers, and URLs.
    """

    # Common English abbreviations that should not cause sentence splits
    ABBREVIATIONS = frozenset([
        "Mr", "Mrs", "Ms", "Dr", "Prof", "Sr", "Jr",
        "etc", "e.g", "i.e", "vs", "viz",
        "Inc", "Ltd", "Corp", "Co",
        "Jan", "Feb", "Mar", "Apr", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
        "St", "Ave", "Blvd", "Rd",
    ])

    def __init__(self) -> None:
        """Initialize the SentenceSplitter with pre-compiled patterns."""
        # Placeholder token for protected sequences
        self._placeholder_prefix = "\x00PROTECTED_"

        # Pattern to match URLs (protect from splitting)
        self._url_pattern = re.compile(
            r'https?://[^\s]+|www\.[^\s]+',
            re.IGNORECASE
        )

        # Pattern to match decimal/version numbers (e.g., 3.14, 192.168.1.1)
        self._number_pattern = re.compile(
            r'\d+\.\d+(?:\.\d+)*'
        )

        # Pattern to match abbreviations followed by period
        abbrev_pattern = '|'.join(re.escape(abbr) for abbr in self.ABBREVIATIONS)
        self._abbrev_pattern = re.compile(
            rf'\b({abbrev_pattern})\.',
            re.IGNORECASE
        )

        # Pattern to match ellipsis (...)
        self._ellipsis_pattern = re.compile(r'\.{2,}')

    def split(self, text: str) -> List[str]:
        """Split text into sentences.

        Args:
            text: Input text to split into sentences.

        Returns:
            List of sentences with punctuation preserved.
            Empty list for empty or whitespace-only input.
        """
        # Handle empty or whitespace-only input
        if not text or not text.strip():
            return []

        # Step 1: Protect sequences that should not be split
        protected_text, placeholders = self._protect_sequences(text)

        # Step 2: Split on sentence boundaries
        sentences = self._split_sentences(protected_text)

        # Step 3: Restore protected sequences
        sentences = [self._restore_sequences(s, placeholders) for s in sentences]

        # Step 4: Clean up - trim whitespace and filter empty strings
        sentences = [s.strip() for s in sentences]
        sentences = [s for s in sentences if s]

        return sentences

    def split_iter(self, text: str) -> Iterator[str]:
        """Split text into sentences lazily.

        Args:
            text: Input text to split into sentences.

        Yields:
            Sentences one at a time.
        """
        for sentence in self.split(text):
            yield sentence

    def __call__(self, text: str) -> Iterator[str]:
        """Make the splitter callable, returning an iterator.

        Args:
            text: Input text to split into sentences.

        Returns:
            Iterator of sentences.
        """
        return self.split_iter(text)

    def _protect_sequences(self, text: str) -> tuple[str, dict[str, str]]:
        """Protect sequences that should not cause sentence splits.

        Args:
            text: Input text.

        Returns:
            Tuple of (text with placeholders, dict mapping placeholders to original).
        """
        placeholders: dict[str, str] = {}
        counter = 0

        def make_placeholder(match: re.Match) -> str:
            nonlocal counter
            original = match.group(0)
            placeholder = f"{self._placeholder_prefix}{counter}\x00"
            placeholders[placeholder] = original
            counter += 1
            return placeholder

        # Protect URLs first (most complex pattern)
        text = self._url_pattern.sub(make_placeholder, text)

        # Protect decimal/version/IP numbers
        text = self._number_pattern.sub(make_placeholder, text)

        # Protect abbreviations (e.g., Mr. Mrs. Dr. etc. e.g. i.e.)
        text = self._abbrev_pattern.sub(make_placeholder, text)

        # Protect ellipsis
        text = self._ellipsis_pattern.sub(make_placeholder, text)

        return text, placeholders

    def _restore_sequences(self, text: str, placeholders: dict[str, str]) -> str:
        """Restore protected sequences from placeholders.

        Args:
            text: Text with placeholders.
            placeholders: Dict mapping placeholders to original strings.

        Returns:
            Text with original sequences restored.
        """
        for placeholder, original in placeholders.items():
            text = text.replace(placeholder, original)
        return text

    def _split_sentences(self, text: str) -> List[str]:
        """Split text on sentence boundaries.

        Handles both English and Korean sentence endings.

        Args:
            text: Text with protected sequences replaced by placeholders.

        Returns:
            List of sentence fragments.
        """
        # Sentence ending pattern:
        # - Period, question mark, or exclamation (possibly multiple like ?! or !!)
        # - Optionally followed by closing quote marks
        # - Followed by whitespace or end of string
        #
        # This pattern captures the sentence-ending punctuation as part of the match
        # so we can preserve it in the output.

        # Split pattern: sentence-ending punctuation followed by space or end
        # We use a positive lookbehind to keep the punctuation with the sentence
        pattern = re.compile(
            r'([.!?]+["\'\u201d\u300d\u300f\u3011]*)'  # Punctuation + optional closing quotes
            r'(?=\s+|$)',  # Followed by whitespace or end (lookahead)
            re.UNICODE
        )

        # Split and reconstruct sentences
        sentences = []
        last_end = 0

        for match in pattern.finditer(text):
            # Include everything from last_end to end of match (including punctuation)
            sentence = text[last_end:match.end()]
            sentences.append(sentence)
            last_end = match.end()

        # Add any remaining text after the last sentence boundary
        if last_end < len(text):
            remaining = text[last_end:]
            if remaining.strip():
                sentences.append(remaining)

        # If no splits occurred, return the original text as a single sentence
        if not sentences:
            sentences = [text]

        return sentences
