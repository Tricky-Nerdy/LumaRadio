"""LumaRadio Pygame walkie-talkie prototype. Offline; debug logging opt-in."""
import math
import os
import struct
import time
from array import array
from pathlib import Path
import pygame
from radio_effects import PROFILES, samples
from lightbar import MODES, draw_lightbar

WIDTH, HEIGHT = 480, 800
RATE = 22050
DEBUG = os.environ.get("LUMARADIO_DEBUG") == "1"
COLORS = {"body": (48, 55, 48), "edge": (19, 23, 21), "screen": (139, 181, 124), "ink": (20, 45, 28), "key": (74, 85, 77)}
BUTTONS = ["SQUAWK", "MORSE SOS", "MORSE CQ", "ROGER", "QSL", "73", "88", "STATIC", "BLASTER", "WALKIE"]
POINTS = ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO"]

def log(event):
    if DEBUG:
        path = Path.home() / ".lumaradio" / "telemetry.log"
        path.parent.mkdir(exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(f"{time.time():.3f} {event}\n")

def tone_sequence(notes):
    pcm = array("h")
    for hz, duration in notes:
        length = int(RATE * duration)
        for n in range(length):
            envelope = min(1.0, n / 150, (length - n) / 150)
            v = int(9500 * envelope * math.sin(2 * math.pi * hz * n / RATE)) if hz else 0
            pcm.append(v)
    return pygame.mixer.Sound(buffer=pcm.tobytes())

def notes_for(label):
    if label == "MORSE SOS":
        return [(660, .09)] * 3 + [(0, .1)] + [(660, .27)] * 3 + [(0, .1)] + [(660, .09)] * 3
    if label == "MORSE CQ":
        return [(660, .27), (660, .09), (660, .27), (660, .09), (0, .1), (660, .27), (660, .27), (660, .09), (660, .27)]
    if label.endswith("CAPTURED"):
        return [(850, .12), (1120, .12), (1500, .16)]
    if label.endswith("LOST"):
        return [(1500, .12), (750, .12), (400, .18)]
    tones = {"SQUAWK": [900, 650, 950], "ROGER": [900, 1100], "QSL": [1050, 750, 1050], "73": [650, 950], "88": [850, 850, 1100], "STATIC": [130, 110, 90], "BLASTER": [1350, 800, 420], "WALKIE": [420, 1200, 500]}
    return [(hz, .12) for hz in tones.get(label, [700])]

def main():
    pygame.mixer.pre_init(RATE, -16, 1, 512)
    pygame.init()
    screen = pygame.display.set_mode((WIDTH, HEIGHT), pygame.RESIZABLE)
    pygame.display.set_caption("LumaRadio • Walkie-Talkie")
    font = pygame.font.SysFont("dejavusans", 18, bold=True)
    small = pygame.font.SysFont("dejavusans", 15, bold=True)
    title = pygame.font.SysFont("dejavusans", 25, bold=True)
    labels = BUTTONS + list(PROFILES) + [f"{p} CAPTURED" for p in POINTS] + [f"{p} LOST" for p in POINTS]
    status = "CH 05  •  READY"
    icon_sheet = None
    sheet_path = Path(__file__).parent / "assets" / "lumaradio_64_tile_sheet.png"
    if sheet_path.exists():
        icon_sheet = pygame.image.load(str(sheet_path)).convert_alpha()
    log("session_start")
    clock = pygame.time.Clock()
    running = True
    held_name = None
    held_channel = None
    light_mode = 0
    brightness = 0.55
    start_ticks = pygame.time.get_ticks()
    while running:
        w, h = screen.get_size()
        scale = min(w / WIDTH, h / HEIGHT)
        offset_x, offset_y = (w - WIDTH * scale) / 2, (h - HEIGHT * scale) / 2
        def rect(x, y, rw, rh):
            return pygame.Rect(round(offset_x + x * scale), round(offset_y + y * scale), round(rw * scale), round(rh * scale))
        def label(text, x, y, f, color):
            surf = f.render(text, True, color)
            surf = pygame.transform.smoothscale(surf, (max(1, round(surf.get_width() * scale)), max(1, round(surf.get_height() * scale))))
            screen.blit(surf, (round(offset_x + x * scale), round(offset_y + y * scale)))
        buttons = []
        for i, name in enumerate(labels):
            x, y, bw = 56 + (i % 4) * 94, 250 + (i // 4) * 67, 84
            buttons.append((name, rect(x, y, bw, 61)))
        mode_button = rect(54, 235, 178, 28)
        brightness_slider = rect(245, 235, 177, 28)
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
                if held_channel is not None:
                    held_channel.stop()
                    held_channel = None
                    held_name = None
            if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                if mode_button.collidepoint(event.pos):
                    light_mode = (light_mode + 1) % len(MODES)
                    log("light_mode " + MODES[light_mode])
                    continue
                if brightness_slider.collidepoint(event.pos):
                    brightness = max(0.0, min(1.0, (event.pos[0] - brightness_slider.x) / brightness_slider.w))
                    log("brightness " + str(round(brightness, 2)))
                    continue
                for name, box in buttons:
                    if box.collidepoint(event.pos):
                        status = name
                        log("sound " + name)
                        if pygame.mixer.get_init():
                            if name in PROFILES:
                                held_channel = pygame.mixer.Sound(buffer=samples(name)).play(loops=-1)
                                held_name = name
                            else:
                                tone_sequence(notes_for(name)).play()
                        break
        if held_name and held_channel is not None and not pygame.mouse.get_pressed()[0]:
            held_channel.stop()
            held_name = None
            held_channel = None
        screen.fill((14, 17, 17))
        pygame.draw.rect(screen, COLORS["body"], rect(26, 36, 428, 738), border_radius=round(34 * scale))
        pygame.draw.rect(screen, COLORS["edge"], rect(26, 36, 428, 738), max(1, round(5 * scale)), border_radius=round(34 * scale))
        pygame.draw.rect(screen, (35, 42, 37), rect(185, 5, 110, 38), border_radius=round(7 * scale))
        pygame.draw.rect(screen, COLORS["screen"], rect(53, 88, 374, 140), border_radius=round(8 * scale))
        label("LUMA RADIO", 144, 104, title, COLORS["ink"])
        label(status[:25], 75, 157, font, COLORS["ink"])
        label("SIGNAL  5 / 9    •    OFFLINE", 75, 193, small, COLORS["ink"])
        draw_lightbar(screen, rect(53, 210, 374, 18), MODES[light_mode], brightness, (pygame.time.get_ticks() - start_ticks) / 1000.0)
        pygame.draw.rect(screen, (61, 73, 65), mode_button, border_radius=5)
        label("LIGHT: " + MODES[light_mode], 60, 238, small, (244, 246, 233))
        pygame.draw.rect(screen, (61, 73, 65), brightness_slider, border_radius=5)
        pygame.draw.rect(screen, (235, 173, 76), rect(248, 242, 170 * brightness, 12), border_radius=3)
        label("HOLD TO PLAY EFFECTS", 135, 732, small, (208, 221, 199))
        for idx, (name, box) in enumerate(buttons):
            pygame.draw.rect(screen, COLORS["key"], box, border_radius=round(7 * scale))
            if icon_sheet is not None:
                icon_id = idx % 64
                src = pygame.Rect(8 + (icon_id % 8) * 72, 8 + (icon_id // 8) * 72, 64, 64)
                icon = pygame.transform.smoothscale(icon_sheet.subsurface(src), (max(1, round(42 * scale)), max(1, round(27 * scale))))
                screen.blit(icon, (box.centerx - icon.get_width() // 2, box.top + round(5 * scale)))
            pygame.draw.rect(screen, (130, 143, 126), box, max(1, round(2 * scale)), border_radius=round(7 * scale))
            caption = name.replace(" CAPTURED", "+").replace(" LOST", "-")
            txt = small.render(caption, True, (244, 246, 233))
            txt = pygame.transform.smoothscale(txt, (max(1, round(txt.get_width() * scale)), max(1, round(txt.get_height() * scale))))
            screen.blit(txt, txt.get_rect(center=(box.centerx, box.bottom - round(14 * scale))))
        label("LUMA ACTUAL  •  GRACIE 01", 98, 762, small, (208, 221, 199))
        pygame.display.flip()
        clock.tick(30)
    log("session_end")
    pygame.quit()

if __name__ == "__main__":
    main()
