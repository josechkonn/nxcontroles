#!/usr/bin/env python3
import sys, os, subprocess, shutil
from PIL import Image

def png_to_icns(png_path, out_icns):
    iconset = out_icns.replace('.icns', '.iconset')
    os.makedirs(iconset, exist_ok=True)
    img = Image.open(png_path).convert('RGBA')
    
    sizes = [
        (16, 'icon_16x16.png'),
        (32, 'icon_16x16@2x.png'),
        (32, 'icon_32x32.png'),
        (64, 'icon_32x32@2x.png'),
        (128, 'icon_128x128.png'),
        (256, 'icon_128x128@2x.png'),
        (256, 'icon_256x256.png'),
        (512, 'icon_256x256@2x.png'),
        (512, 'icon_512x512.png'),
        (1024, 'icon_512x512@2x.png'),
    ]
    
    for sz, name in sizes:
        resized = img.resize((sz, sz), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset, name))
        
    subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', out_icns], check=True)
    shutil.rmtree(iconset)
    print(f"Generated: {out_icns}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: make_icns.py <input.png> <output.icns>")
        sys.exit(1)
    png_to_icns(sys.argv[1], sys.argv[2])
