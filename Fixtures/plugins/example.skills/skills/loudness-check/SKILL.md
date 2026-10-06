---
name: loudness-check
description: Check how loud the media in an edit is and say what to change. Use when the user asks whether the sound is too loud or too quiet, or before an export for a platform. Triggers: "kiểm tra âm lượng", "to quá", "nhỏ quá", "loudness check".
---

# Loudness check

1. Find the media to check with `bashcut media list`, then measure each one: `bashcut audio measure --media <id>`
   (a background job; read the values with `bashcut jobs status`).
2. Compare the integrated loudness with the target: about -14 LUFS for YouTube and social video, -16 LUFS for
   podcasts. Report true peaks above -1 dBTP.
3. Tell the user the numbers and one change to make (clip gain, music ducking, or normalising at export). Do not
   change the edit unless they ask.

Limits: this skill only reads. The bc:audio-mix skill covers fixing the mix.
