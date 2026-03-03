import numpy as np
from PIL import Image, ImageDraw, ImageFont
import os

def generate_true_equirectangular(width=2048, height=1024):
    # Create the base image using numpy for speed
    # We'll calculate the grid mathematically
    
    # 1. Create a coordinate grid
    x = np.linspace(-np.pi, np.pi, width)  # Longitude
    y = np.linspace(np.pi/2, -np.pi/2, height) # Latitude
    lon, lat = np.meshgrid(x, y)

    # 2. Define grid parameters (e.g., every 15 degrees)
    grid_spacing = np.deg2rad(15)
    
    # Calculate grid lines
    # Longitude lines (meridians)
    lon_grid = (np.abs(lon % grid_spacing) < 0.02) | (np.abs((lon + grid_spacing/2) % grid_spacing - grid_spacing/2) < 0.02)
    # Latitude lines (parallels)
    lat_grid = (np.abs(lat % grid_spacing) < 0.02) | (np.abs((lat + grid_spacing/2) % grid_spacing - grid_spacing/2) < 0.02)
    
    # Create checkerboard pattern
    checker = ((lon // grid_spacing) % 2 == (lat // grid_spacing) % 2)
    
    # Initialize image array (RGB)
    img_data = np.zeros((height, width, 3), dtype=np.uint8)
    
    # Fill colors
    # Base color based on coordinates for a nice gradient
    img_data[:,:,0] = ((lon + np.pi) / (2*np.pi) * 255).astype(np.uint8) # R
    img_data[:,:,1] = ((lat + np.pi/2) / np.pi * 255).astype(np.uint8) # G
    img_data[:,:,2] = 150 # B
    
    # Apply checkerboard darkening
    img_data[checker] = (img_data[checker] * 0.8).astype(np.uint8)
    
    # Apply white grid lines
    grid_mask = lon_grid | lat_grid
    img_data[grid_mask] = [255, 255, 255]
    
    # Convert to PIL for text overlay
    img = Image.fromarray(img_data)
    draw = ImageDraw.Draw(img)
    
    # Add labels
    try:
        font_path = "/System/Library/Fonts/Helvetica.ttc"
        if not os.path.exists(font_path):
            font_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
        font = ImageFont.truetype(font_path, size=30)
    except:
        font = ImageFont.load_default()

    # Draw labels at intersections
    for lo in np.arange(-180, 180, 30):
        for la in np.arange(-60, 90, 30):
            # Map sphere to image
            px = int((lo + 180) / 360 * width)
            py = int((90 - la) / 180 * height)
            
            label = f"{la:+}°,{lo:+ laboratory}°"
            # Simple label
            label = f"{int(la)}N {int(lo)}E" if la >= 0 else f"{int(-la)}S {int(lo)}E"
            
            # Since the image is stretched at poles, the text technically should be too
            # but usually labels are kept readable.
            draw.text((px, py), label, fill=(255, 255, 255), font=font)

    # Highlight poles
    draw.line([(0, 0), (width, 0)], fill=(255, 0, 0), width=5) # North Pole
    draw.line([(0, height-1), (width, height-1)], fill=(0, 0, 255), width=5) # South Pole
    
    img.save('true_equirect_uv.png')

if __name__ == "__main__":
    # Check if numpy is available
    try:
        import numpy
        generate_true_equirectangular()
        print("true_equirect_uv.png created with spherical mapping distortion")
    except ImportError:
        print("Numpy required for better distortion generation. Installing...")
        os.system("pip3 install numpy")
        import numpy
        generate_true_equirectangular()
