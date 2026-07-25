#!/usr/bin/env bash
#
# video-upscale.sh — upscale a video with an open-source super-resolution
# model, using FFmpeg for demux/remux and Real-ESRGAN (ncnn-vulkan build)
# for the actual frame upscaling.
#
# Pipeline: ffmpeg (extract frames as PNG) -> realesrgan-ncnn-vulkan
#           (upscale each frame) -> ffmpeg (reassemble video + remux
#           original audio).
#
# Requires on PATH:
#   - ffmpeg / ffprobe
#   - realesrgan-ncnn-vulkan
#     https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan
#     (prebuilt binaries for Linux/macOS/Windows, no PyTorch/CUDA needed;
#     runs on any Vulkan-capable GPU including integrated ones)
#
# Usage:
#   ./scripts/video-upscale.sh -i input.mp4 -o output.mp4 [options]
#
# Options:
#   -i, --input FILE       Source video (required)
#   -o, --output FILE      Destination video (required)
#   -s, --scale N          Upscale factor: 2, 3, or 4 (default: 4)
#   -m, --model NAME       realesrgan-ncnn-vulkan model name
#                           (default: realesrgan-x4plus, or
#                            realesrgan-x4plus-anime for --anime)
#       --anime             Use the anime-optimized model
#       --crf N             x264 quality, 0-51, lower = better (default: 18)
#       --preset NAME       x264 preset (default: slow)
#       --keep-frames       Don't delete the extracted/upscaled frame dirs
#   -j, --jobs SPEC         realesrgan-ncnn-vulkan -j load:proc:save
#                           (default: 1:2:2)
#   -h, --help              Show this help
#
# Example:
#   ./scripts/video-upscale.sh -i clip.mp4 -o clip_4k.mp4 -s 4 --crf 16

set -euo pipefail

usage() {
  sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

input=""
output=""
scale=4
model=""
anime=0
crf=18
preset="slow"
keep_frames=0
jobs="1:2:2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input) input="$2"; shift 2 ;;
    -o|--output) output="$2"; shift 2 ;;
    -s|--scale) scale="$2"; shift 2 ;;
    -m|--model) model="$2"; shift 2 ;;
    --anime) anime=1; shift ;;
    --crf) crf="$2"; shift 2 ;;
    --preset) preset="$2"; shift 2 ;;
    --keep-frames) keep_frames=1; shift ;;
    -j|--jobs) jobs="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -z "$input" || -z "$output" ]] && { echo "Error: -i/--input and -o/--output are required." >&2; usage 1; }
[[ -f "$input" ]] || { echo "Error: input file not found: $input" >&2; exit 1; }

case "$scale" in
  2|3|4) ;;
  *) echo "Error: --scale must be 2, 3, or 4." >&2; exit 1 ;;
esac

if [[ -z "$model" ]]; then
  if [[ "$anime" -eq 1 ]]; then
    model="realesrgan-x4plus-anime"
  else
    model="realesrgan-x${scale}plus"
    # Only the x4 general model ships by default; x2/x3 fall back to x4
    # and let realesrgan-ncnn-vulkan's -s flag downscale via the output.
    [[ "$scale" != "4" ]] && model="realesrgan-x4plus"
  fi
fi

for bin in ffmpeg ffprobe realesrgan-ncnn-vulkan; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "Error: '$bin' not found on PATH." >&2
    [[ "$bin" == "realesrgan-ncnn-vulkan" ]] && \
      echo "  Get it from: https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/releases" >&2
    exit 1
  }
done

workdir="$(mktemp -d "${TMPDIR:-/tmp}/video-upscale.XXXXXX")"
frames_in="$workdir/frames_in"
frames_out="$workdir/frames_out"
mkdir -p "$frames_in" "$frames_out"

cleanup() {
  if [[ "$keep_frames" -eq 0 ]]; then
    rm -rf "$workdir"
  else
    echo "Frames kept in: $workdir"
  fi
}
trap cleanup EXIT

echo "==> Reading source fps"
fps="$(ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 \
  -show_entries stream=r_frame_rate "$input")"

echo "==> Extracting frames (fps=${fps})"
ffmpeg -v error -stats -i "$input" -vsync 0 "$frames_in/frame_%08d.png"

echo "==> Upscaling frames with $model (x${scale}, jobs=${jobs})"
realesrgan-ncnn-vulkan -i "$frames_in" -o "$frames_out" -n "$model" -s "$scale" -j "$jobs" -f png

echo "==> Checking for an audio stream"
has_audio="$(ffprobe -v error -select_streams a -of csv=p=0 -show_entries stream=codec_type "$input" || true)"

echo "==> Reassembling video (crf=${crf}, preset=${preset})"
if [[ -n "$has_audio" ]]; then
  ffmpeg -v error -stats -y -r "$fps" -i "$frames_out/frame_%08d.png" -i "$input" \
    -map 0:v:0 -map 1:a:0? \
    -c:v libx264 -crf "$crf" -preset "$preset" -pix_fmt yuv420p \
    -c:a copy \
    -shortest \
    "$output"
else
  ffmpeg -v error -stats -y -r "$fps" -i "$frames_out/frame_%08d.png" \
    -c:v libx264 -crf "$crf" -preset "$preset" -pix_fmt yuv420p \
    "$output"
fi

echo "==> Done: $output"
