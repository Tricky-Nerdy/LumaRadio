"""Compact radio lightbar: contained banner, never whole-screen flashing."""
import pygame

MODES = ("OFF", "POLICE", "AMBER", "WHITE")
def draw_lightbar(surface, rect, mode, brightness, elapsed):
    pygame.draw.rect(surface, (20, 25, 24), rect, border_radius=7)
    if mode == "OFF":
        return
    brightness = max(0.0, min(1.0, brightness))
    # Maximum 2 flashes/second; no fullscreen effects.
    phase = int(elapsed * 4) % 4
    count = 12
    for i in range(count):
        cell = pygame.Rect(rect.x + 5 + i * (rect.w - 10) // count,
                           rect.y + 4, max(2, (rect.w - 10) // count - 3), rect.h - 8)
        if mode == "POLICE":
            rgb = (215, 45, 42) if i < count // 2 else (45, 90, 225)
            active = (phase in (0, 1)) == (i < count // 2)
        elif mode == "AMBER":
            rgb = (255, 145, 35)
            active = (i + phase * 3) % count < 5
        else:
            rgb = (255, 240, 210)
            active = phase < 2
        power = brightness if active else .045
        pygame.draw.rect(surface, tuple(int(c * power) for c in rgb), cell, border_radius=3)
