"""Level the sound effects in App/Resources/Audio for the way a phone speaker hears them.

Peak-normalising every file (as Tools/make-sfx.swift does) leaves the mix upside down on a phone: hits are low drums
the speaker barely reproduces, while whooshes and footsteps are bright noise, so a whiff can sound louder than a
landed heavy blow. This measures each file's loudness after a 300 Hz high-pass (roughly what an iPhone speaker
passes) and sets its gain to a target for its role, never letting a peak pass -1 dBFS.

usage: level-sfx.py [--dry-run] [name ...]     (needs numpy; writes 16-bit WAVs in place, keeping channels and rate)
Run it again after replacing any sound with a recording.
"""
import glob, os, sys, wave
import numpy as np

AUDIO = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'App/Resources/Audio')

# Target loudness (dB RMS after the high-pass) by role: blows and the announcer on top, then projectiles and
# voices, then movement.
TARGETS = [
    (('vo-round', 'vo-final', 'vo-fight', 'vo-ko', 'vo-time', 'vo-perfect'), -17),
    (('sfx-hit-crushing', 'sfx-ko', 'sfx-super'), -18),
    (('sfx-hit-', 'sfx-counter', 'sfx-armor', 'sfx-block', 'sfx-bodyfall'), -20),
    (('sfx-gong', 'sfx-horn', 'sfx-victory', 'sfx-gallop'), -21),
    (('vo-male', 'vo-female'), -22),
    (('sfx-bow', 'sfx-crossbow', 'sfx-orb', 'sfx-seal', 'sfx-dust', 'sfx-heal', 'sfx-grab'), -23),
    (('sfx-whoosh', 'sfx-swing'), -28),
    (('sfx-jump', 'sfx-land', 'sfx-dash'), -31),
]


def target(name):
    for prefixes, db in TARGETS:
        if name.startswith(prefixes): return db
    return None


def highpass(x, rate, fc=300.0):
    """Second-order Butterworth high-pass (RBJ biquad)."""
    w0 = 2 * np.pi * fc / rate; alpha = np.sin(w0) / np.sqrt(2); c = np.cos(w0)
    b = np.array([(1 + c) / 2, -(1 + c), (1 + c) / 2]); a = np.array([1 + alpha, -2 * c, 1 - alpha])
    b, a = b / a[0], a / a[0]
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x):
        yi = b[0] * xi + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1, y2, y1 = x1, xi, y1, yi; y[i] = yi
    return y


def loudness(x, rate):
    """dB RMS of the loudest 300 ms after the high-pass (short sounds are judged by their body, not their tail)."""
    h = highpass(x, rate); win = max(1, int(rate * 0.3))
    e = np.convolve(h ** 2, np.ones(win) / win, 'valid') if len(h) > win else np.array([np.mean(h ** 2)])
    return 10 * np.log10(e.max() + 1e-12)


def main(args):
    dry = '--dry-run' in args
    names = [a for a in args if not a.startswith('--')]
    paths = sorted(glob.glob(os.path.join(AUDIO, '*.wav')))
    for p in paths:
        name = os.path.basename(p)[:-4]
        if names and name not in names: continue
        goal = target(name)
        if goal is None: continue
        with wave.open(p) as w:
            ch, rate, width, n = w.getnchannels(), w.getframerate(), w.getsampwidth(), w.getnframes()
            raw = w.readframes(n)
        if width != 2: print(f'{name}: skipped ({8 * width}-bit)'); continue
        x = np.frombuffer(raw, np.int16).astype(np.float64).reshape(-1, ch) / 32768
        mono = x.mean(1)
        now = loudness(mono, rate)
        peak = np.abs(x).max() + 1e-12
        gain_db = min(goal - now, -1 - 20 * np.log10(peak))       # never past -1 dBFS
        print(f'{name:24s} {now:6.1f} -> {now + gain_db:6.1f} dB (target {goal}) gain {gain_db:+5.1f}' + (' [peak-limited]' if goal - now > gain_db + 0.05 else ''))
        if dry or abs(gain_db) < 0.2: continue
        y = np.clip(x * 10 ** (gain_db / 20), -1, 1)
        with wave.open(p, 'wb') as w:
            w.setnchannels(ch); w.setsampwidth(2); w.setframerate(rate)
            w.writeframes((y * 32767).astype(np.int16).tobytes())


if __name__ == '__main__':
    main(sys.argv[1:])
