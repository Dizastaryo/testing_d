"""Generate WAV ringtone assets for C-3.1.

CC0-by-construction: pure sine-wave tones, programmatically synthesized.
Output: ringtone.wav (incoming, 4s loopable), ringback.wav (outgoing, 4s),
endtone.wav (hangup chirp, 0.5s).

Re-run if you ever need to tweak tones. Files committed to repo so build
doesn't depend on Python in CI.

Usage: python generate_tones.py
"""
import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 16000  # 16kHz mono — компактно (~32KB per file)


def write_wav(path: Path, samples: list[float]):
    """Записать float-samples [-1..1] как 16-bit PCM WAV."""
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        data = b"".join(
            struct.pack("<h", max(-32768, min(32767, int(s * 32767)))) for s in samples
        )
        w.writeframes(data)


def sine(freq: float, duration_s: float, amplitude: float = 0.3) -> list[float]:
    n = int(SAMPLE_RATE * duration_s)
    return [amplitude * math.sin(2 * math.pi * freq * i / SAMPLE_RATE) for i in range(n)]


def silence(duration_s: float) -> list[float]:
    return [0.0] * int(SAMPLE_RATE * duration_s)


def envelope(samples: list[float], fade_s: float = 0.02) -> list[float]:
    """Fade-in/out по краям чтобы избежать «щелчков» на старте/конце."""
    fade_n = int(SAMPLE_RATE * fade_s)
    n = len(samples)
    out = list(samples)
    for i in range(min(fade_n, n)):
        k = i / fade_n
        out[i] *= k
        out[n - 1 - i] *= k
    return out


def ringtone() -> list[float]:
    """Incoming ring (telephone-style): 800Hz tone 1s + 0.5s silence ×2, loopable."""
    seg = envelope(sine(800, 1.0)) + silence(0.5)
    return seg + seg + silence(1.0)


def ringback() -> list[float]:
    """Outgoing ringback (Russian standard ~425Hz): 1s tone + 4s silence — но
    короткий вариант 1s + 3s × 1 чтобы файл лёгкий. Loop'аем в коде."""
    seg = envelope(sine(425, 1.0)) + silence(3.0)
    return seg


def endtone() -> list[float]:
    """Hangup chirp: descending sweep 800→200Hz over 0.5s."""
    n = int(SAMPLE_RATE * 0.5)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 800 - (600 * (t / 0.5))
        out.append(0.3 * math.sin(2 * math.pi * freq * t))
    return envelope(out, fade_s=0.05)


def main() -> None:
    out_dir = Path(__file__).parent
    write_wav(out_dir / "ringtone.wav", ringtone())
    write_wav(out_dir / "ringback.wav", ringback())
    write_wav(out_dir / "endtone.wav", endtone())
    print("Wrote:", [p.name for p in out_dir.glob("*.wav")])


if __name__ == "__main__":
    main()
