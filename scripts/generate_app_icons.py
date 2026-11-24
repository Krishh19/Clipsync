import math
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

def create_clipsync_master_icon(size=1024):
    # Supersampling factor for ultra-crisp anti-aliasing
    SCALE = 2
    W = size * SCALE
    H = size * SCALE
    
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # 1. Base Squircle geometry
    # Padding from edges
    pad = int(64 * SCALE)
    x0, y0 = pad, pad
    x1, y1 = W - pad, H - pad
    corner_radius = int(210 * SCALE)
    
    # Draw subtle background glow behind the squircle
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.rounded_rectangle([x0 + 10, y0 + 20, x1 - 10, y1 + 30], radius=corner_radius, fill=(127, 0, 255, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=35 * SCALE))
    img.paste(glow, (0, 0), glow)
    
    # Draw background squircle with vertical dark cyber gradient
    # Gradient: #0D0F22 (13, 15, 34) -> #181A38 (24, 26, 56) -> #0A0C18 (10, 12, 24)
    base_sq = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sq_draw = ImageDraw.Draw(base_sq)
    sq_draw.rounded_rectangle([x0, y0, x1, y1], radius=corner_radius, fill=(255, 255, 255, 255))
    
    # Create gradient fill
    grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for y in range(y0, y1):
        t = (y - y0) / max(1, (y1 - y0))
        # Top-left radial sheen blended with deep dark violet-slate
        r = int(16 + 20 * (1 - t) + 12 * math.sin(t * math.pi))
        g = int(18 + 15 * (1 - t) + 18 * math.sin(t * math.pi))
        b = int(40 + 45 * (1 - t) + 35 * math.sin(t * math.pi))
        for x in range(x0, x1):
            # Radial highlight near top center
            dx = (x - (W / 2)) / (W / 2)
            dy = (y - y0) / (H * 0.6)
            dist = math.sqrt(dx * dx + dy * dy)
            sheen = max(0.0, 1.0 - dist) * 0.28
            
            fr = min(255, int(r * (1 + sheen) + sheen * 90))
            fg = min(255, int(g * (1 + sheen) + sheen * 110))
            fb = min(255, int(b * (1 + sheen) + sheen * 190))
            grad.putpixel((x, y), (fr, fg, fb, 255))
            
    # Mask gradient to squircle
    base_sq_final = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    base_sq_final.paste(grad, (0, 0), base_sq)
    img.paste(base_sq_final, (0, 0), base_sq_final)
    
    # Squircle border: 1.5px subtle glass highlight
    border_draw = ImageDraw.Draw(img)
    border_draw.rounded_rectangle([x0, y0, x1, y1], radius=corner_radius, outline=(255, 255, 255, 45), width=int(3 * SCALE))
    
    # 2. Draw the Central Emblem: Futuristic Intertwined Clip & Sync Loops
    # Center coordinates
    cx = W / 2
    cy = H / 2
    
    emblem = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    emblem_draw = ImageDraw.Draw(emblem)
    
    # We will draw two overlapping fluid organic stadium loops (paperclip meets sync chevrons)
    # Loop 1: Left-to-Center Cyan / Teal Loop (#00F2FE -> #4FACFE -> #00E676)
    # Loop 2: Right-to-Center Violet / Purple Loop (#7F00FF -> #E100FF -> #9D00FF)
    
    # Parameters for the sync loops
    loop_w = int(190 * SCALE)
    loop_h = int(320 * SCALE)
    offset_x = int(95 * SCALE)
    stroke_w = int(58 * SCALE)
    
    # Left Clip Loop
    # Points defining curved clip path
    def draw_thick_capsule(draw_ctx, center_x, center_y, width, height, angle_deg, color_func):
        # Sample points around a rounded capsule
        rad = angle_deg * math.pi / 180.0
        cos_a = math.cos(rad)
        sin_a = math.sin(rad)
        
        steps = 360
        r_inner = height / 2
        for i in range(steps):
            theta = (i / steps) * 2 * math.pi
            # parametric stadium
            # ...
            pass

    # Clean, beautiful geometric drawing for the emblem:
    # Outer glowing shadow of emblem
    emblem_glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    eg_draw = ImageDraw.Draw(emblem_glow)
    
    # Left loop (Sync Clip A)
    left_rect = [cx - offset_x - loop_w/2, cy - loop_h/2, cx - offset_x + loop_w/2, cy + loop_h/2]
    right_rect = [cx + offset_x - loop_w/2, cy - loop_h/2, cx + offset_x + loop_w/2, cy + loop_h/2]
    
    # Draw glow
    eg_draw.rounded_rectangle(left_rect, radius=int(loop_w/2), outline=(0, 242, 254, 180), width=stroke_w)
    eg_draw.rounded_rectangle(right_rect, radius=int(loop_w/2), outline=(225, 0, 255, 180), width=stroke_w)
    emblem_glow = emblem_glow.filter(ImageFilter.GaussianBlur(radius=24 * SCALE))
    img.paste(emblem_glow, (0, 0), emblem_glow)
    
    # Draw actual loops with vivid gradients
    # We create a layer for the left loop
    left_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ll_draw = ImageDraw.Draw(left_layer)
    ll_draw.rounded_rectangle(left_rect, radius=int(loop_w/2), outline=(255, 255, 255, 255), width=stroke_w)
    
    # Color left loop with Cyan/Electric Teal gradient
    left_colored = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for y in range(int(cy - loop_h/2 - stroke_w), int(cy + loop_h/2 + stroke_w)):
        if 0 <= y < H:
            t = (y - (cy - loop_h/2)) / max(1, loop_h)
            t = max(0.0, min(1.0, t))
            # 0% #00F2FE (0, 242, 254) -> 100% #10B981 (16, 185, 129)
            cr = int(0 * (1 - t) + 16 * t)
            cg = int(242 * (1 - t) + 215 * t)
            cb = int(254 * (1 - t) + 160 * t)
            for x in range(int(cx - offset_x - loop_w/2 - stroke_w), int(cx - offset_x + loop_w/2 + stroke_w)):
                if 0 <= x < W:
                    left_colored.putpixel((x, y), (cr, cg, cb, 255))
    
    left_masked = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    left_masked.paste(left_colored, (0, 0), left_layer)
    
    # Right loop (Violet / Cyber Magenta)
    right_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rl_draw = ImageDraw.Draw(right_layer)
    rl_draw.rounded_rectangle(right_rect, radius=int(loop_w/2), outline=(255, 255, 255, 255), width=stroke_w)
    
    right_colored = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for y in range(int(cy - loop_h/2 - stroke_w), int(cy + loop_h/2 + stroke_w)):
        if 0 <= y < H:
            t = (y - (cy - loop_h/2)) / max(1, loop_h)
            t = max(0.0, min(1.0, t))
            # 0% #E100FF (225, 0, 255) -> 100% #6366F1 (99, 102, 241)
            cr = int(225 * (1 - t) + 99 * t)
            cg = int(0 * (1 - t) + 102 * t)
            cb = int(255 * (1 - t) + 241 * t)
            for x in range(int(cx + offset_x - loop_w/2 - stroke_w), int(cx + offset_x + loop_w/2 + stroke_w)):
                if 0 <= x < W:
                    right_colored.putpixel((x, y), (cr, cg, cb, 255))
                    
    right_masked = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    right_masked.paste(right_colored, (0, 0), right_layer)
    
    # Composite the intertwined loops
    # Left loop on bottom, Right loop overlaps at top, Left loop overlaps at bottom
    # To create true 3D interlock:
    img.paste(left_masked, (0, 0), left_masked)
    img.paste(right_masked, (0, 0), right_masked)
    
    # Mask half of the bottom overlap so left loop comes forward
    bottom_interlock = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bi_draw = ImageDraw.Draw(bottom_interlock)
    bi_draw.rectangle([cx - offset_x, cy, cx + offset_x, cy + loop_h/2 + stroke_w], fill=(255, 255, 255, 255))
    
    left_overlap = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    left_overlap.paste(left_masked, (0, 0), bottom_interlock)
    img.paste(left_overlap, (0, 0), left_overlap)
    
    # 3. Central Sync Energy Spark / Glowing Node
    spark = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(spark)
    spark_radius = int(28 * SCALE)
    s_draw.ellipse([cx - spark_radius, cy - spark_radius, cx + spark_radius, cy + spark_radius], fill=(255, 255, 255, 255))
    
    spark_glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sg_draw = ImageDraw.Draw(spark_glow)
    sg_draw.ellipse([cx - spark_radius * 2, cy - spark_radius * 2, cx + spark_radius * 2, cy + spark_radius * 2], fill=(0, 242, 254, 200))
    spark_glow = spark_glow.filter(ImageFilter.GaussianBlur(radius=12 * SCALE))
    
    img.paste(spark_glow, (0, 0), spark_glow)
    img.paste(spark, (0, 0), spark)
    
    # Downsample from 2x supersampling to final target size with Lanczos anti-aliasing
    final_img = img.resize((size, size), Image.Resampling.LANCZOS)
    return final_img

if __name__ == "__main__":
    os.makedirs("assets", exist_ok=True)
    icon = create_clipsync_master_icon(1024)
    icon.save("assets/app-icon.png", "PNG")
    print("Master app icon generated at assets/app-icon.png")
