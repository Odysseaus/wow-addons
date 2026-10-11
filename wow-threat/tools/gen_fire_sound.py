#!/usr/bin/env python3
"""Generate the optional WoWThreat fire-crackle loop (original, procedural).
Port of the previewer's WebAudio sound: brown-noise roar through a low-pass
plus random band-passed crackle bursts. 8 s seamless loop (crossfaded ends),
mono 22.05 kHz, written as Ogg Vorbis via ffmpeg in 3 loudness variants.

Usage: gen_fire_sound.py OUT_DIR
"""
import os, sys, subprocess, wave
import numpy as np

SR, SEC, XF = 22050, 8.0, 0.5

def onepole_lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR); y = np.zeros_like(x); s = 0.0
    for i in range(len(x)):
        s = (1 - a) * x[i] + a * s; y[i] = s
    return y

def bandpass(x, f0, q):
    w0 = 2 * np.pi * f0 / SR; al = np.sin(w0) / (2 * q)
    b0, b2 = al, -al; a0, a1, a2 = 1 + al, -2 * np.cos(w0), 1 - al
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        v = (b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x[i], y1, v; y[i] = v
    return y

def main():
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(1010)
    n = int(SR * (SEC + XF))
    w = rng.uniform(-1, 1, n)
    brown = np.zeros(n); last = 0.0
    for i in range(n):
        last = (last + 0.02 * w[i]) / 1.02; brown[i] = last * 3.5
    roar = onepole_lp(brown, 420) * 0.55
    crack = np.zeros(n)
    t = 0.0
    while t < SEC + XF - 0.1:
        t += rng.exponential(1 / 6.0)
        i0 = int(t * SR); L = int(SR * (0.02 + rng.random() * 0.06))
        if i0 + L >= n: break
        burst = rng.uniform(-1, 1, L) * np.exp(-np.linspace(0, 6, L)) * (0.15 + rng.random() * 0.5)
        crack[i0:i0 + L] += bandpass(burst, 1200 + rng.random() * 4200, 1.2 + rng.random() * 2)
    sig = roar + crack
    m = int(SR * SEC); k = int(SR * XF)
    loop = sig[:m].copy()
    fade = np.linspace(0, 1, k)
    loop[:k] = sig[:k] * fade + sig[m:m + k] * (1 - fade)   # seamless wrap
    loop /= np.max(np.abs(loop)) + 1e-9
    for name, gain in (("low", 0.25), ("med", 0.5), ("high", 0.85)):
        wav = os.path.join(out, "_tmp_%s.wav" % name)
        pcm = (loop * gain * 32767).astype(np.int16)
        with wave.open(wav, "wb") as f:
            f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(pcm.tobytes())
        ogg = os.path.join(out, "fire_%s.ogg" % name)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "2", ogg], check=True)
        os.remove(wav)
        print(ogg, os.path.getsize(ogg))

if __name__ == "__main__":
    main()
