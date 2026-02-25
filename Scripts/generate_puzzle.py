#!/usr/bin/env python3
"""
Wrapper script that calls piecemaker to generate jigsaw puzzle pieces.
Called by the Swift app as a subprocess.

Usage:
    python3 generate_puzzle.py <image_path> <output_dir> <num_pieces>

Output:
    Generates pieces in <output_dir> and prints JSON metadata to stdout.
"""

import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import traceback
from pathlib import Path


def error_exit(message):
    """Print a JSON error to stdout and exit."""
    print(json.dumps({"error": message}))
    sys.exit(1)


# Minimum pixels on the longest side of the source image.
# Small images are upscaled so bezier curves rasterise smoothly.
MIN_LONG_SIDE = 2000


def ensure_minimum_resolution(image_path):
    """Upscale the image if it's too small for smooth piece edges.
    Returns (path_to_use, needs_cleanup)."""
    try:
        from PIL import Image
    except ImportError:
        error_exit("Pillow (PIL) is not installed. Install with: pip3 install Pillow")

    try:
        img = Image.open(image_path)
    except Exception as e:
        error_exit(f"Could not open image: {e}")

    longest = max(img.size)
    if longest >= MIN_LONG_SIDE:
        return image_path, False

    scale = MIN_LONG_SIDE / longest
    new_w = int(img.size[0] * scale)
    new_h = int(img.size[1] * scale)
    img = img.resize((new_w, new_h), Image.LANCZOS)

    upscaled = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    img.save(upscaled.name, "PNG")
    upscaled.close()
    return upscaled.name, True


def main():
    if len(sys.argv) != 4:
        error_exit("Usage: generate_puzzle.py <image_path> <output_dir> <num_pieces>")

    image_path = sys.argv[1]
    output_dir = sys.argv[2]

    try:
        num_pieces = int(sys.argv[3])
    except ValueError:
        error_exit(f"Invalid piece count: '{sys.argv[3]}' is not an integer.")

    if num_pieces < 2:
        error_exit(f"Need at least 2 pieces, got {num_pieces}.")

    if not os.path.exists(image_path):
        error_exit(f"Image not found: {image_path}")

    # Upscale small images so piece edges are smooth
    actual_image, cleanup_upscaled = ensure_minimum_resolution(image_path)

    # piecemaker needs an empty directory
    temp_dir = output_dir + "_temp"
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir, exist_ok=True)

    # Run piecemaker at full image resolution for smooth piece edges
    try:
        result = subprocess.run(
            [
                "piecemaker",
                "--dir", temp_dir,
                "--number-of-pieces", str(num_pieces),
                "--scaled-sizes", "100",
                "--use-max-size",
                "--trust-image-file",
                actual_image,
            ],
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout for large puzzles
        )
        if result.returncode != 0:
            error_exit(f"piecemaker failed: {result.stderr}")
    except FileNotFoundError:
        error_exit("piecemaker not found. Install with: pip3 install piecemaker")
    except subprocess.TimeoutExpired:
        error_exit("piecemaker timed out (>5 minutes)")

    # Find the output size directory (piecemaker creates size-XX directories)
    size_dirs = [d for d in os.listdir(temp_dir) if d.startswith("size-") and os.path.isdir(os.path.join(temp_dir, d))]
    if not size_dirs:
        error_exit("No output directory found from piecemaker")

    # Use the largest size directory for best quality
    def parse_size_dir(d):
        """Extract the numeric suffix from a size-XX directory name."""
        parts = d.split("-", 1)
        if len(parts) < 2:
            return 0
        try:
            return int(parts[1])
        except ValueError:
            return 0

    size_dirs.sort(key=parse_size_dir, reverse=True)
    size_dir = os.path.join(temp_dir, size_dirs[0])

    # Read piecemaker metadata
    index_path = os.path.join(temp_dir, "index.json")
    adjacent_path = os.path.join(temp_dir, "adjacent.json")
    pieces_path = os.path.join(size_dir, "pieces.json")

    try:
        with open(index_path) as f:
            index_data = json.load(f)
    except FileNotFoundError:
        error_exit(f"piecemaker did not produce expected metadata file: {index_path}")
    except json.JSONDecodeError as e:
        error_exit(f"Corrupt piecemaker metadata (index.json): {e}")

    try:
        with open(adjacent_path) as f:
            adjacent_data = json.load(f)
    except FileNotFoundError:
        error_exit(f"piecemaker did not produce expected metadata file: {adjacent_path}")
    except json.JSONDecodeError as e:
        error_exit(f"Corrupt piecemaker metadata (adjacent.json): {e}")

    try:
        with open(pieces_path) as f:
            pieces_data = json.load(f)
    except FileNotFoundError:
        error_exit(f"piecemaker did not produce expected metadata file: {pieces_path}")
    except json.JSONDecodeError as e:
        error_exit(f"Corrupt piecemaker metadata (pieces.json): {e}")

    # Prepare the output directory
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)
    os.makedirs(output_dir, exist_ok=True)
    pieces_out_dir = os.path.join(output_dir, "pieces")
    os.makedirs(pieces_out_dir, exist_ok=True)

    # Copy piece images to output directory
    raster_dir = os.path.join(size_dir, "raster", "image-0")
    piece_ids = sorted(pieces_data.keys(), key=lambda x: int(x))

    pieces_metadata = []
    missing_pieces = []
    for pid in piece_ids:
        src_png = os.path.join(raster_dir, f"{pid}.png")
        if not os.path.exists(src_png):
            missing_pieces.append(pid)
            continue

        dst_png = os.path.join(pieces_out_dir, f"piece_{pid}.png")
        shutil.copy2(src_png, dst_png)

        # pieces.json format: [x1, y1, x2, y2, ..., width, height]
        pdata = pieces_data[pid]
        x1, y1, x2, y2 = pdata[0], pdata[1], pdata[2], pdata[3]
        width, height = pdata[-2], pdata[-1]

        neighbours = adjacent_data.get(pid, [])

        # Determine piece type based on position
        img_w = index_data.get("image_width", 0)
        img_h = index_data.get("image_height", 0)
        is_left = x1 <= 2
        is_right = x2 >= img_w - 2
        is_top = y1 <= 2
        is_bottom = y2 >= img_h - 2
        border_count = sum([is_left, is_right, is_top, is_bottom])

        if border_count >= 2:
            piece_type = "corner"
        elif border_count == 1:
            piece_type = "edge"
        else:
            piece_type = "interior"

        pieces_metadata.append({
            "id": int(pid),
            "filename": f"piece_{pid}.png",
            "x1": x1, "y1": y1, "x2": x2, "y2": y2,
            "width": width, "height": height,
            "type": piece_type,
            "neighbours": [int(n) for n in neighbours]
        })

    if not pieces_metadata:
        error_exit("No piece image files were found in the piecemaker output.")

    # Copy the lines overlay image
    lines_png = os.path.join(temp_dir, "lines-resized.png")
    lines_svg = os.path.join(temp_dir, "lines-resized.svg")
    if os.path.exists(lines_png):
        shutil.copy2(lines_png, os.path.join(output_dir, "lines.png"))
    if os.path.exists(lines_svg):
        shutil.copy2(lines_svg, os.path.join(output_dir, "lines.svg"))

    # Build final metadata
    metadata = {
        "piece_count": len(pieces_metadata),
        "image_width": index_data.get("image_width", 0),
        "image_height": index_data.get("image_height", 0),
        "requested_pieces": num_pieces,
        "pieces": pieces_metadata
    }

    if missing_pieces:
        metadata["warning"] = f"{len(missing_pieces)} piece image(s) were missing: {', '.join(missing_pieces)}"

    # Write metadata file
    metadata_path = os.path.join(output_dir, "metadata.json")
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)

    # Clean up temp files
    shutil.rmtree(temp_dir, ignore_errors=True)
    if cleanup_upscaled:
        try:
            os.unlink(actual_image)
        except OSError:
            pass  # Best-effort cleanup

    # Print metadata to stdout for the Swift app
    print(json.dumps(metadata))


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        # Catch-all: emit a clean JSON error instead of a raw traceback
        error_exit(f"Unexpected error: {traceback.format_exc()}")
