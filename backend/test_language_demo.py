#!/usr/bin/env python3
"""
Test Qwen3-TTS multilingual behavior.

Tests:
1. Korean text with Korean voice
2. English text with Korean voice
3. Mixed Korean + English text
"""

import asyncio
from tts import TTSEngine, VoiceConfig, VOICE_PRESETS

async def main():
    engine = TTSEngine()

    print("=" * 60)
    print("Qwen3-TTS 다국어 테스트")
    print("=" * 60)

    # Test cases
    tests = [
        ("Korean text + Korean voice",
         "안녕하세요. 오늘 날씨가 좋네요.",
         VOICE_PRESETS["korean_female"]),

        ("English text + Korean voice",
         "Hello, how are you today?",
         VOICE_PRESETS["korean_female"]),

        ("Mixed text + Korean voice",
         "오늘 meeting에서 API design을 논의했어요.",
         VOICE_PRESETS["korean_female"]),

        ("English text + English voice",
         "Hello, how are you today?",
         VOICE_PRESETS["english_female"]),

        ("Korean text + English voice",
         "안녕하세요. 오늘 날씨가 좋네요.",
         VOICE_PRESETS["english_female"]),
    ]

    print("\n모델 로딩 중...")
    await engine.initialize()
    print("모델 로딩 완료!\n")

    for i, (name, text, voice) in enumerate(tests, 1):
        print(f"\n[Test {i}] {name}")
        print(f"  Voice: {voice.language} / {voice.voice_instruct[:40]}...")
        print(f"  Text: {text}")
        print("  🔊 Playing...")

        engine.set_voice_config(voice)
        await engine.speak(text)

        # Wait for playback to finish
        while engine.state.value != "idle":
            await asyncio.sleep(0.5)

        print("  ✅ Done")
        await asyncio.sleep(1.0)  # Brief pause between tests

    await engine.shutdown()
    print("\n" + "=" * 60)
    print("테스트 완료!")
    print("=" * 60)

if __name__ == "__main__":
    asyncio.run(main())
