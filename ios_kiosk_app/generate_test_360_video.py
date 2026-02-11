import numpy as np
from PIL import Image, ImageDraw, ImageFont
import os
import subprocess
import shutil

def generate_frame(frame_num, total_frames, width=2048, height=1024):
    # Longitude offset for movement (360 degrees over total_frames)
    lon_offset = (frame_num / total_frames) * 2 * np.pi
    
    # 1. Create a coordinate grid
    x = np.linspace(-np.pi, np.pi, width)  # Longitude
    y = np.linspace(np.pi/2, -np.pi/2, height) # Latitude
    lon, lat = np.meshgrid(x, y)
    
    # Apply movement offset to longitude
    lon_moved = (lon + lon_offset + np.pi) % (2 * np.pi) - np.pi

    # 2. Define grid parameters (every 30 degrees)
    grid_spacing = np.deg2rad(30)
    
    # Calculate grid lines
    lon_grid = (np.abs(lon_moved % grid_spacing) < 0.015)
    lat_grid = (np.abs(lat % grid_spacing) < 0.015)
    
    # Create checkerboard pattern
    checker = ((lon_moved // grid_spacing) % 2 == (lat // grid_spacing) % 2)
    
    # Initialize image array (RGB)
    img_data = np.zeros((height, width, 3), dtype=np.uint8)
    
    # Fill colors
    # Base color based on coordinates
    img_data[:,:,0] = ((lon_moved + np.pi) / (2*np.pi) * 150 + 50).astype(np.uint8) # R
    img_data[:,:,1] = ((lat + np.pi/2) / np.pi * 150 + 50).astype(np.uint8)      # G
    img_data[:,:,2] = 100 # B
    
    # Apply checkerboard darkening
    img_data[checker] = (img_data[checker] * 0.7).astype(np.uint8)
    
    # Apply white grid lines
    grid_mask = lon_grid | lat_grid
    img_data[grid_mask] = [255, 255, 255]
    
    # Convert to PIL for text overlay
    img = Image.fromarray(img_data)
    draw = ImageDraw.Draw(img)
    
    # Load font
    try:
        font_path = "/System/Library/Fonts/Helvetica.ttc"
        if not os.path.exists(font_path):
            font_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
        font_large = ImageFont.truetype(font_path, size=60)
        font_small = ImageFont.truetype(font_path, size=30)
    except:
        font_large = ImageFont.load_default()
        font_small = ImageFont.load_default()

    # Draw labels
    for lo_deg in range(-180, 180, 45):
        lo_rad = np.deg2rad(lo_deg)
        # Find where this longitude is in the moved frame
        # (lo_rad - lon_offset) mapped to [0, width]
        curr_lo = (lo_rad - lon_offset + np.pi) % (2 * np.pi) - np.pi
        px = int((curr_lo + np.pi) / (2 * np.pi) * width)
        
        for la_deg in range(-60, 90, 30):
            py = int((np.pi/2 - np.deg2rad(la_deg)) / np.pi * height)
            label = f"{la_deg}°N, {lo_deg}°E" if la_deg >= 0 else f"{-la_deg}°S, {lo_deg}°E"
            draw.text((px + 5, py + 5), label, fill=(255, 255, 255, 128), font=font_small)

    # Highlight North/South labels
    draw.text((width//2, 50), "NORTH POLE", fill=(255, 255, 255), font=font_large, anchor="mt")
    draw.text((width//2, height - 100), "SOUTH POLE", fill=(255, 255, 255), font=font_large, anchor="mb")

    # Add frame counter and timestamp
    draw.text((50, height - 50), f"Frame: {frame_num} | Time: {frame_num/30:.2f}s", fill=(255, 255, 0), font=font_small)
    
    # Add a bouncing ball to test motion
    ball_x = int((frame_num * 10) % width)
    ball_y = int(height/2 + np.sin(frame_num * 0.2) * 200)
    draw.ellipse([ball_x - 30, ball_y - 30, ball_x + 30, ball_y + 30], fill=(255, 0, 0), outline=(255, 255, 255))

    return img

def main():
    width, height = 2048, 1024
    total_frames = 150 # 5 seconds at 30 fps
    output_dir = "temp_frames"
    video_name = "bitzone_test_360.mp4"

    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)
    os.makedirs(output_dir)

    print(f"Generating {total_frames} frames...")
    for i in range(total_frames):
        img = generate_frame(i, total_frames, width, height)
        img.save(f"{output_dir}/frame_{i:04d}.png")
        if (i+1) % 30 == 0:
            print(f"  Frame {i+1}/{total_frames} done")

    print("Encoding video with ffmpeg...")
    cmd = [
        "ffmpeg", "-y",
        "-framerate", "30",
        "-i", f"{output_dir}/frame_%04d.png",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-crf", "18",
        video_name
    ]
    
    try:
        subprocess.run(cmd, check=True)
        print(f"Successfully created {video_name}")
    except subprocess.CalledProcessError as e:
        print(f"Error during video encoding: {e}")
    finally:
        # Cleanup
        # shutil.rmtree(output_dir)
        pass

if __name__ == "__main__":
    main()
