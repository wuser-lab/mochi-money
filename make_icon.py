from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
ICONSET = ROOT / "build" / "AppIcon.iconset"
ICONSET.mkdir(parents=True, exist_ok=True)


def icon(size: int) -> Image.Image:
    s = size / 1024
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    margin = int(76 * s)
    draw.rounded_rectangle((margin, margin, size - margin, size - margin), radius=int(220 * s), fill=(12, 12, 12, 255))

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((int(180*s), int(180*s), int(844*s), int(844*s)), fill=(255, 255, 255, 30))
    glow = glow.filter(ImageFilter.GaussianBlur(int(90*s)))
    im.alpha_composite(glow)
    draw = ImageDraw.Draw(im)

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((int(230*s), int(315*s), int(795*s), int(730*s)), radius=int(170*s), fill=(0,0,0,170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(35*s)))
    im.alpha_composite(shadow)
    draw = ImageDraw.Draw(im)

    body = (int(205*s), int(280*s), int(770*s), int(695*s))
    draw.rounded_rectangle(body, radius=int(175*s), fill=(250, 250, 250, 255))
    draw.ellipse((int(340*s), int(445*s), int(378*s), int(493*s)), fill=(15,15,15,255))
    draw.ellipse((int(595*s), int(445*s), int(633*s), int(493*s)), fill=(15,15,15,255))
    draw.arc((int(440*s), int(452*s), int(535*s), int(545*s)), start=20, end=160, fill=(15,15,15,255), width=max(2,int(14*s)))
    draw.ellipse((int(285*s), int(518*s), int(365*s), int(548*s)), fill=(190,190,190,170))
    draw.ellipse((int(610*s), int(518*s), int(690*s), int(548*s)), fill=(190,190,190,170))

    coin_center = (int(730*s), int(700*s)); r = int(145*s)
    draw.ellipse((coin_center[0]-r, coin_center[1]-r, coin_center[0]+r, coin_center[1]+r), fill=(245,245,245,255), outline=(15,15,15,255), width=max(2,int(24*s)))
    draw.line((coin_center[0], coin_center[1]-int(70*s), coin_center[0], coin_center[1]+int(70*s)), fill=(15,15,15,255), width=max(2,int(20*s)))
    draw.arc((coin_center[0]-int(55*s), coin_center[1]-int(75*s), coin_center[0]+int(55*s), coin_center[1]), 80, 280, fill=(15,15,15,255), width=max(2,int(18*s)))
    draw.arc((coin_center[0]-int(55*s), coin_center[1], coin_center[0]+int(55*s), coin_center[1]+int(75*s)), 260, 100, fill=(15,15,15,255), width=max(2,int(18*s)))
    return im


base = icon(1024)
for dimension, filename in [
    (16,"icon_16x16.png"),(32,"icon_16x16@2x.png"),(32,"icon_32x32.png"),(64,"icon_32x32@2x.png"),
    (128,"icon_128x128.png"),(256,"icon_128x128@2x.png"),(256,"icon_256x256.png"),(512,"icon_256x256@2x.png"),
    (512,"icon_512x512.png"),(1024,"icon_512x512@2x.png")]:
    base.resize((dimension, dimension), Image.Resampling.LANCZOS).save(ICONSET / filename)
