"""Deterministic, distinct offline radio effects. No weapon simulation: audio only."""
import math
import random
from array import array

RATE = 22050
PROFILES = ("ALARM HI-LO", "ALARM TRIPLE", "SQUAWK SHORT", "SQUAWK LONG",
            "STATIC LIGHT", "STATIC HEAVY", "STATIC BURST", "BLASTER BURST", "BLASTER AUTO")

def samples(profile, seconds=0.8, seed=37):
    rng = random.Random(seed)
    length = int(RATE * max(.05, min(5.0, seconds)))
    out = array("h")
    last = 0.0
    for n in range(length):
        t = n / RATE
        noise = rng.uniform(-1, 1)
        if profile == "ALARM HI-LO":
            hz = 880 if int(t * 3) % 2 == 0 else 560
            value = .42 * math.sin(2 * math.pi * hz * t)
        elif profile == "ALARM TRIPLE":
            value = .43 * math.sin(2 * math.pi * 1050 * t) if (t % .55) < .30 and int(t * 10) % 2 == 0 else 0
        elif profile.startswith("SQUAWK"):
            period = .22 if profile.endswith("SHORT") else .55
            hz = 480 + 700 * (t % period) / period
            value = .36 * math.sin(2 * math.pi * hz * t) + .18 * noise
            if (t % period) > period * .8:
                value *= .15
        elif profile.startswith("STATIC"):
            last = last * (.7 if profile == "STATIC LIGHT" else .25) + noise * .5
            gate = 1.0
            if profile == "STATIC BURST":
                gate = 1.0 if (t % .19) < .09 else .04
            value = last * gate * (.2 if profile == "STATIC LIGHT" else .55)
        elif profile.startswith("BLASTER"):
            interval = .14 if profile.endswith("AUTO") else .26
            phase = t % interval
            # Fast attack, short decaying distorted burst, not a simple musical beep.
            env = math.exp(-phase * 34) if phase < .12 else 0
            chirp = math.sin(2 * math.pi * (1150 * phase - 3000 * phase * phase))
            value = env * (.65 * noise + .3 * chirp)
        else:
            value = 0
        out.append(int(max(-1, min(1, value)) * 22000))
    return out.tobytes()
