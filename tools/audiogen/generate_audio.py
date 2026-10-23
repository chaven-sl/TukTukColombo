#!/usr/bin/env python3
"""TukTuk Colombo — first-pass ORIGINAL procedural audio (v0.03B).

No recordings, no downloads: every sound is synthesised here from noise,
oscillators and envelopes, so the project owns it outright. Placeholders for
the production audio sprint (real Sri Lankan recordings / VO later).

    python3 tools/audiogen/generate_audio.py      # writes assets/audio/sfx/*.wav

Deterministic (fixed seed). 22.05 kHz mono 16-bit to keep the APK small.
Loops are made seamless with an equal-power wrap crossfade.
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")
rng = np.random.default_rng(20261023)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def norm(x, peak=0.85):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def lowpass(x, cutoff):
    # One-pole low-pass (cheap, smooth).
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def bandpass(x, lo, hi):
    return lowpass(x, hi) - lowpass(x, lo)


def env(n, attack, release, sustain=1.0):
    e = np.ones(n) * sustain
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e[:a] = np.linspace(0, sustain, a)
    e[-r:] = np.linspace(sustain, 0, r) * e[-r:] / max(sustain, 1e-6) if sustain else 0
    return e


def loopify(x, fade=0.25):
    n = int(fade * SR)
    head, tail = x[:n], x[-n:]
    w = np.sin(np.linspace(0, np.pi / 2, n))
    mixed = tail * np.cos(np.linspace(0, np.pi / 2, n)) + head * w
    return np.concatenate([mixed, x[n:-n]])


def write(name, x, loop=False):
    x = loopify(x) if loop else x
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name:22s} {len(data) / SR:5.2f} s {'loop' if loop else ''}")


def engine(base_hz, sec, rough, harmonics):
    """Single-cylinder engine: firing pulses at base_hz + harmonic body + roughness."""
    tt = t(sec)
    phase = 2 * np.pi * base_hz * tt + rough * np.cumsum(rng.normal(0, 1, len(tt))) / SR * 40
    x = np.zeros(len(tt))
    for k, amp in enumerate(harmonics, start=1):
        x += amp * np.sin(k * phase)
    pulse = (np.sin(phase) > 0.85).astype(float)
    x += 0.5 * lowpass(pulse, 900)
    x += rough * 0.25 * bandpass(rng.normal(0, 1, len(tt)), 200, 2500)
    return norm(lowpass(x, 3500), 0.8)


def horn(freqs, sec, square=0.5, vibrato=0.0):
    tt = t(sec)
    x = np.zeros(len(tt))
    for f in freqs:
        ph = 2 * np.pi * f * tt + vibrato * np.sin(2 * np.pi * 6 * tt)
        x += (1 - square) * np.sin(ph) + square * np.sign(np.sin(ph)) * 0.6
    x = lowpass(x, 4000)
    return norm(x * env(len(tt), 0.01, 0.06), 0.8)


def voice(f0, formants, sec, wobble=0.15, rate=5.0):
    """Formant-ish vocal placeholder (no words): glottal buzz through resonances."""
    tt = t(sec)
    f = f0 * (1 + wobble * np.sin(2 * np.pi * rate * tt + rng.uniform(0, 6)))
    buzz = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR))
    x = np.zeros(len(tt))
    for fc, bw in formants:
        x += bandpass(buzz, fc - bw, fc + bw)
    syll = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * rate * 0.5 * tt))
    return norm(x * syll * env(len(tt), 0.03, 0.12), 0.75)


def main():
    os.makedirs(OUT, exist_ok=True)
    # --- player tuk engine (pitch-shifted by TukAudioController) ---
    write("tuk_engine_idle", engine(27, 2.0, 0.6, [1.0, 0.6, 0.35, 0.2, 0.12]), loop=True)
    write("tuk_engine_load", engine(44, 2.0, 1.0, [1.0, 0.8, 0.6, 0.45, 0.3, 0.2]), loop=True)
    write("tyre_road", norm(bandpass(rng.normal(0, 1, int(SR * 2.0)), 150, 1200), 0.5), loop=True)
    # --- horns ---
    write("horn_tuk", np.concatenate([horn([470, 590], 0.28, 0.7), np.zeros(int(0.06 * SR)), horn([470, 590], 0.34, 0.7)]))
    write("horn_bus", horn([196, 247, 294], 1.1, 0.4, 0.002))
    write("horn_car", horn([392, 494], 0.45, 0.35))
    write("horn_bike", horn([640], 0.3, 0.6))
    write("horn_repeated", np.concatenate([horn([392, 494], 0.22, 0.4), np.zeros(int(0.08 * SR))] * 3 + [horn([392, 494], 0.6, 0.4)]))
    # --- traffic ---
    write("bus_rumble", engine(19, 2.0, 0.8, [1.0, 0.9, 0.5, 0.3]) * 0.9, loop=True)
    tt = t(1.4)
    f = 70 + 40 * np.exp(-((tt - 0.7) / 0.25) ** 2)  # doppler-ish swell
    bike = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    write("bike_pass", norm(lowpass(bike, 2500) * np.exp(-((tt - 0.7) / 0.35) ** 2), 0.7))
    # --- impacts ---
    n = int(0.6 * SR)
    thud = lowpass(rng.normal(0, 1, n), 300) * np.exp(-np.linspace(0, 9, n))
    write("collision_thud", norm(thud, 0.9))
    n = int(1.2 * SR)
    clang = sum(np.sin(2 * np.pi * f * t(1.2)) * np.exp(-np.linspace(0, d, n)) for f, d in [(310, 7), (523, 9), (811, 11), (1240, 14)])
    debris = bandpass(rng.normal(0, 1, n), 800, 6000) * np.exp(-np.linspace(0, 5, n))
    write("collision_crash", norm(0.6 * clang + 0.8 * debris + lowpass(rng.normal(0, 1, n), 250) * np.exp(-np.linspace(0, 6, n)), 0.95))
    write("scrape", norm(bandpass(rng.normal(0, 1, int(0.7 * SR)), 1500, 5000) * env(int(0.7 * SR), 0.02, 0.3), 0.6))
    write("prop_knock", norm(lowpass(rng.normal(0, 1, int(0.35 * SR)), 1200) * np.exp(-np.linspace(0, 8, int(0.35 * SR))), 0.7))
    # --- ambience beds (8 s loops) ---
    sec = 8.0
    n = int(SR * sec)
    city = lowpass(rng.normal(0, 1, n), 400) * 0.8 + bandpass(rng.normal(0, 1, n), 300, 1800) * 0.15
    for k in range(5):  # distant horns sprinkled through the bed
        start = rng.integers(0, n - SR)
        h = horn([rng.choice([392, 470, 523, 294]), rng.choice([494, 590, 659])], 0.3, 0.5) * 0.12
        city[start:start + len(h)] += h
    write("amb_city", norm(city, 0.6), loop=True)
    crowd = np.zeros(n)
    for v in range(14):  # many quiet overlapping "voices" = murmur
        f0 = rng.uniform(110, 240)
        crowd += voice(f0, [(rng.uniform(500, 800), 120), (rng.uniform(1100, 1700), 200)], sec, 0.2, rng.uniform(3, 6)) * rng.uniform(0.3, 1.0)
    write("amb_crowd", norm(lowpass(crowd, 2500), 0.55), loop=True)
    market = crowd * 1.0 + bandpass(rng.normal(0, 1, n), 2000, 6000) * 0.05
    for k in range(30):  # clatter: crates, scales, carts
        start = rng.integers(0, n - 2000)
        market[start:start + 2000] += bandpass(rng.normal(0, 1, 2000), 1500, 5000) * np.exp(-np.linspace(0, 10, 2000)) * 0.6
    write("amb_market", norm(market, 0.6), loop=True)
    clack = np.zeros(n)
    for beat in np.arange(0, sec, 0.42):
        i = int(beat * SR)
        for off in (0, int(0.11 * SR)):
            j = i + off
            if j + 1500 < n:
                clack[j:j + 1500] += lowpass(rng.normal(0, 1, 1500), 1200) * np.exp(-np.linspace(0, 12, 1500))
    write("rail_clatter", norm(clack + lowpass(rng.normal(0, 1, n), 150) * 0.4, 0.6), loop=True)
    train = np.concatenate([horn([233, 294, 349], 1.2, 0.3, 0.003), np.zeros(int(0.15 * SR)), horn([220, 277, 330], 1.6, 0.3, 0.003)])
    write("train_horn", train)
    # --- voice placeholders (hooks for the audio sprint; no words) ---
    write("vendor_call", voice(190, [(700, 140), (1200, 220), (2600, 300)], 1.3, 0.35, 3.0))
    write("driver_shout", voice(210, [(760, 160), (1300, 250), (2700, 350)], 0.9, 0.45, 7.0))
    write("passenger_react", voice(230, [(600, 120), (1100, 200)], 0.45, 0.25, 6.0))
    write("ui_click", norm(np.sin(2 * np.pi * 1800 * t(0.04)) * np.exp(-np.linspace(0, 10, int(0.04 * SR))), 0.5))


if __name__ == "__main__":
    main()
