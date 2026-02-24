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
import os
import shutil
import subprocess
import sys
from pathlib import Path


def main():
    if len(sys.argv) != 4:
        print(json.dumps({"error": "Usage: generate_puzzle.py <image_path> <output_dir> <num_pieces>"}))
        sys.exit(1)

    image_path = sys.argv[1]
    output_dir = sys.argv[2]
    num_pieces = int(sys.argv[3])

    if not os.path.exists(image_path):
        print(json.dumps({"error": f"Image not found: {image_path}"}))
        sys.exit(1)

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
                image_path,
            ],
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout for large puzzles
        )
        if result.returncode != 0:
            print(json.dumps({"error": f"piecemaker failed: {result.stderr}"}))
            sys.exit(1)
    except FileNotFoundError:
        print(json.dumps({"error": "piecemaker not found. Install with: pip3 install piecemaker"}))
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print(json.dumps({"error": "piecemaker timed out (>5 minutes)"}))
        sys.exit(1)

    # Find the output size directory (piecemaker creates size-XX directories)
    size_dirs = [d for d in os.listdir(temp_dir) if d.startswith("size-") and os.path.isdir(os.path.join(temp_dir, d))]
    if not size_dirs:
        print(json.dumps({"error": "No output directory found from piecemaker"}))
        sys.exit(1)

    # Use the largest size directory for best quality
    size_dirs.sort(key=lambda d: int(d.split("-")[1]), reverse=True)
    size_dir = os.path.join(temp_dir, size_dirs[0])

    # Read piecemaker metadata
    index_path = os.path.join(temp_dir, "index.json")
    adjacent_path = os.path.join(temp_dir, "adjacent.json")
    pieces_path = os.path.join(size_dir, "pieces.json")

    with open(index_path) as f:
        index_data = json.load(f)
    with open(adjacent_path) as f:
        adjacent_data = json.load(f)
    with open(pieces_path) as f:
        pieces_data = json.load(f)

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
    for pid in piece_ids:
        src_png = os.path.join(raster_dir, f"{pid}.png")
        if os.path.exists(src_png):
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

    # Write metadata file
    metadata_path = os.path.join(output_dir, "metadata.json")
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)

    # Clean up temp directory
    shutil.rmtree(temp_dir, ignore_errors=True)

    # Print metadata to stdout for the Swift app
    print(json.dumps(metadata))


if __name__ == "__main__":
    main()
