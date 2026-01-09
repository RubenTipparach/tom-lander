#!/usr/bin/env python3
"""
Generate the palette shadow lookup texture for LÖVE2D game
32x8 pixels where:
- X axis (0-31) = palette color index
- Y axis (0-7) = shadow level (0=brightest, 7=darkest)
"""

from PIL import Image

# Picotron 32-color palette
palette_colors = [
    (0x00, 0x00, 0x00),  # 0
    (0x1d, 0x2b, 0x53),  # 1
    (0x7e, 0x25, 0x53),  # 2
    (0x00, 0x87, 0x51),  # 3
    (0xab, 0x52, 0x36),  # 4
    (0x5f, 0x57, 0x4f),  # 5
    (0xc2, 0xc3, 0xc7),  # 6
    (0xff, 0xf1, 0xe8),  # 7
    (0xff, 0x00, 0x4d),  # 8
    (0xff, 0xa3, 0x00),  # 9
    (0xff, 0xec, 0x27),  # 10
    (0x00, 0xe4, 0x36),  # 11
    (0x29, 0xad, 0xff),  # 12
    (0x83, 0x76, 0x9c),  # 13
    (0xff, 0x77, 0xa8),  # 14
    (0xff, 0xcc, 0xaa),  # 15
    (0x1c, 0x5e, 0xac),  # 16
    (0x00, 0xa5, 0xa1),  # 17
    (0x75, 0x4e, 0x97),  # 18
    (0x12, 0x53, 0x59),  # 19
    (0x74, 0x2f, 0x29),  # 20
    (0x49, 0x2d, 0x38),  # 21
    (0xa2, 0x88, 0x79),  # 22
    (0xff, 0xac, 0xc5),  # 23
    (0xc3, 0x00, 0x4c),  # 24
    (0xeb, 0x6b, 0x00),  # 25
    (0x90, 0xec, 0x42),  # 26
    (0x00, 0xb2, 0x51),  # 27
    (0x64, 0xdf, 0xf6),  # 28
    (0xbd, 0x9a, 0xdf),  # 29
    (0xe4, 0x0d, 0xab),  # 30
    (0xff, 0x85, 0x6d),  # 31
]

# Shadow level mappings (8 levels per color)
shadow_levels = {
    0: [0, 0, 0, 0, 0, 0, 0, 0],
    1: [1, 1, 1, 0, 0, 0, 0, 0],
    2: [2, 2, 21, 21, 1, 0, 0, 0],
    3: [3, 3, 19, 19, 1, 1, 0, 0],
    4: [4, 4, 20, 20, 21, 1, 0, 0],
    5: [5, 5, 21, 21, 1, 0, 0, 0],
    6: [6, 13, 13, 5, 5, 21, 1, 0],
    7: [7, 6, 6, 13, 5, 5, 1, 0],
    8: [8, 8, 24, 24, 2, 21, 1, 0],
    9: [9, 9, 25, 25, 4, 20, 21, 0],
    10: [10, 10, 9, 25, 4, 20, 1, 0],
    11: [11, 11, 27, 27, 3, 19, 1, 0],
    12: [12, 12, 16, 16, 1, 1, 0, 0],
    13: [13, 13, 5, 5, 21, 1, 0, 0],
    14: [14, 14, 8, 8, 24, 2, 1, 0],
    15: [15, 15, 4, 4, 20, 21, 1, 0],
    16: [16, 16, 1, 1, 0, 0, 0, 0],
    17: [17, 17, 19, 19, 1, 1, 0, 0],
    18: [18, 18, 2, 2, 21, 1, 0, 0],
    19: [19, 19, 1, 1, 0, 0, 0, 0],
    20: [20, 20, 21, 21, 1, 0, 0, 0],
    21: [21, 21, 1, 0, 0, 0, 0, 0],
    22: [22, 22, 5, 5, 21, 1, 0, 0],
    23: [23, 23, 14, 14, 8, 24, 2, 0],
    24: [24, 24, 2, 2, 21, 1, 0, 0],
    25: [25, 25, 4, 4, 20, 21, 1, 0],
    26: [26, 26, 11, 11, 27, 3, 19, 0],
    27: [27, 27, 3, 3, 19, 1, 0, 0],
    28: [28, 28, 12, 12, 16, 1, 0, 0],
    29: [29, 29, 13, 13, 5, 21, 1, 0],
    30: [30, 30, 24, 24, 2, 21, 1, 0],
    31: [31, 31, 8, 8, 24, 2, 1, 0],
}

# Create 32x8 image
width = 32
height = 8
img = Image.new('RGB', (width, height))

# Fill pixels
for palette_idx in range(32):
    for shadow_level in range(8):
        # Get the shadow palette index for this color at this level
        shadow_idx = shadow_levels[palette_idx][shadow_level]
        # Get the RGB color for that shadow index
        rgb = palette_colors[shadow_idx]
        # Set the pixel
        img.putpixel((palette_idx, shadow_level), rgb)

# Save the image
output_path = 'assets/palette_shadow_lookup.png'
img.save(output_path)
print(f"Created palette shadow lookup texture: {output_path}")
print(f"Size: {width}x{height} pixels")
print("Each column represents a palette color (0-31)")
print("Each row represents a shadow level (0=brightest, 7=darkest)")
