"""Quick quality test for Qwen3-TTS Korean/English via mlx-audio."""
import sys
import time
import numpy as np

print("=" * 60)
print("MLX-Audio Qwen3-TTS Quality Test")
print("=" * 60)

# Step 1: Load model
print("\n[1/4] Loading model... (first time downloads ~2.5GB)")
t0 = time.time()

from mlx_audio.tts.utils import load_model
model = load_model("mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16")

print(f"  Model loaded in {time.time() - t0:.1f}s")
print(f"  Sample rate: {model.sample_rate}Hz")

# Step 2: Generate Korean speech
print("\n[2/4] Generating Korean speech...")
korean_text = "안녕하세요! 저는 개발자를 위한 AI 파트너, dev.echo입니다. 오늘도 좋은 하루 되세요."
t0 = time.time()

results_ko = list(model.generate_voice_design(
    text=korean_text,
    language="Korean",
    instruct="A warm, friendly Korean female voice, age 25-30, speaking clearly and naturally"
))

audio_ko = np.concatenate([np.array(r.audio) for r in results_ko])
gen_time_ko = time.time() - t0
duration_ko = len(audio_ko) / model.sample_rate
print(f"  Text: {korean_text}")
print(f"  Generated: {duration_ko:.1f}s audio in {gen_time_ko:.1f}s ({duration_ko/gen_time_ko:.1f}x realtime)")

# Step 3: Generate English speech
print("\n[3/4] Generating English speech...")
english_text = "Hello! I'm dev.echo, your AI partner for developers. Let me help you with real-time audio transcription."
t0 = time.time()

results_en = list(model.generate_voice_design(
    text=english_text,
    language="English",
    instruct="A clear, professional male voice, age 30-35, friendly tone"
))

audio_en = np.concatenate([np.array(r.audio) for r in results_en])
gen_time_en = time.time() - t0
duration_en = len(audio_en) / model.sample_rate
print(f"  Text: {english_text}")
print(f"  Generated: {duration_en:.1f}s audio in {gen_time_en:.1f}s ({duration_en/gen_time_en:.1f}x realtime)")

# Step 4: Save and play
print("\n[4/4] Saving audio files...")
from mlx_audio.audio_io import write as audio_write

ko_path = "/tmp/tts_test_korean.wav"
en_path = "/tmp/tts_test_english.wav"

audio_write(ko_path, audio_ko, model.sample_rate)
audio_write(en_path, audio_en, model.sample_rate)

print(f"  Korean:  {ko_path}")
print(f"  English: {en_path}")

print("\n" + "=" * 60)
print("Playing Korean audio...")
print("=" * 60)

import subprocess
subprocess.run(["afplay", ko_path])

print("\n" + "=" * 60)
print("Playing English audio...")
print("=" * 60)

subprocess.run(["afplay", en_path])

print("\n✅ Test complete! Listen to the audio quality above.")
print("Files saved at /tmp/tts_test_korean.wav and /tmp/tts_test_english.wav")
