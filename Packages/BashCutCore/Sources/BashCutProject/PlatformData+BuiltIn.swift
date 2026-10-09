// swiftlint:disable line_length
import Foundation

extension PlatformData {
    /// The platform table shipped with BashCut (P1-F1): T17's values with their sources, checked 2026-10. TikTok's
    /// bottom band moved from 0.16 to the 0.23–0.25 measured elsewhere; Reels' to 0.25.
    static let builtInJSON = #"""
{
 "version": "2026-10-07",
 "platforms": [
  {
   "id": "tiktok",
   "title": "TikTok",
   "vertical": true,
   "fields": {
    "maxSeconds": {
     "value": 600,
     "kind": "hard",
     "source": "In-app upload up to 10 min (BashCut, openmontage, iart); web upload reported at 60 min (autoclip 2026-09)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "targetLUFS": {
     "value": -14,
     "kind": "recommended",
     "source": "Short-form apps play near −14 LUFS integrated (openmontage, kinocut tables; T11/T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "maxTruePeakDbTP": {
     "value": -1,
     "kind": "recommended",
     "source": "−1 dBTP for TikTok/Instagram (openmontage); YouTube tables also show −1.5 (T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "safeArea.top": {
     "value": 0.07,
     "kind": "recommended",
     "source": "About 130 px of 1920 = 6.8 % (vyral, iart); 0.068 (hotclip)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.bottom": {
     "value": 0.24,
     "kind": "recommended",
     "source": "440–484 px of 1920 = 23–25 % (vyral, iart); 0.252 (hotclip); BashCut had 0.16, the smallest seen",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.sideWidth": {
     "value": 0.13,
     "kind": "recommended",
     "source": "120–140 px of 1080 = 11–13 % (vyral, iart); hotclip 0.11–0.13",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.sideHeight": {
     "value": 0.5,
     "kind": "recommended",
     "source": "Like/comment rail covers about the lower half (BashCut 0.46–0.5, hotclip 0.45–0.5)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.margin": {
     "value": 0.05,
     "kind": "recommended",
     "source": "Generic title-safe margin used for square frames",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "bitrateMbps": {
     "value": 8,
     "kind": "recommended",
     "source": "Recompression line about 8 Mbps (clipforge 2026-07)",
     "checked": "2026-07",
     "confidence": "consensus"
    },
    "shape": {
     "value": "9:16",
     "kind": "hard",
     "source": "1080×1920 is the universal vertical upload (T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "disclosure": {
     "value": "Label realistic AI-generated or altered content with the platform's AI label",
     "kind": "hard",
     "source": "Platform AI-content policies (T17 §3: disclosure rules)",
     "checked": "2026-10",
     "confidence": "consensus"
    }
   }
  },
  {
   "id": "reels",
   "title": "Instagram Reels",
   "vertical": true,
   "fields": {
    "maxSeconds": {
     "value": 180,
     "kind": "hard",
     "source": "Reels format and distribution up to 3 min; longer uploads post as regular video (BashCut; autoclip 2026-09: 20 min upload, ≤3 min recommended)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "targetLUFS": {
     "value": -14,
     "kind": "recommended",
     "source": "Short-form apps play near −14 LUFS integrated (openmontage, kinocut tables; T11/T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "maxTruePeakDbTP": {
     "value": -1,
     "kind": "recommended",
     "source": "−1 dBTP for TikTok/Instagram (openmontage); YouTube tables also show −1.5 (T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "safeArea.top": {
     "value": 0.11,
     "kind": "recommended",
     "source": "0.10–0.11 (BashCut, hotclip); about 14 % (iart, Meta)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.bottom": {
     "value": 0.25,
     "kind": "recommended",
     "source": "0.20 (BashCut, hotclip); about 600 px = 31 % (vyral); 20–35 % (iart, Meta)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.sideWidth": {
     "value": 0.13,
     "kind": "recommended",
     "source": "120–140 px of 1080 = 11–13 % (vyral, iart)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.sideHeight": {
     "value": 0.5,
     "kind": "recommended",
     "source": "Like/comment rail covers about the lower half (BashCut 0.46–0.5, hotclip 0.45–0.5)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.margin": {
     "value": 0.05,
     "kind": "recommended",
     "source": "Generic title-safe margin used for square frames",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "bitrateMbps": {
     "value": 5,
     "kind": "recommended",
     "source": "Recompression line about 5 Mbps (clipforge 2026-07)",
     "checked": "2026-07",
     "confidence": "consensus"
    },
    "shape": {
     "value": "9:16",
     "kind": "hard",
     "source": "1080×1920 is the universal vertical upload (T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "disclosure": {
     "value": "Label realistic AI-generated or altered content with the platform's AI label",
     "kind": "hard",
     "source": "Platform AI-content policies (T17 §3: disclosure rules)",
     "checked": "2026-10",
     "confidence": "consensus"
    }
   }
  },
  {
   "id": "shorts",
   "title": "YouTube Shorts",
   "vertical": true,
   "fields": {
    "maxSeconds": {
     "value": 180,
     "kind": "hard",
     "source": "Shorts up to 3 min since October 2024; 60 s values are stale (T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "targetLUFS": {
     "value": -14,
     "kind": "recommended",
     "source": "Short-form apps play near −14 LUFS integrated (openmontage, kinocut tables; T11/T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "maxTruePeakDbTP": {
     "value": -1,
     "kind": "recommended",
     "source": "−1 dBTP for TikTok/Instagram (openmontage); YouTube tables also show −1.5 (T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "safeArea.top": {
     "value": 0.08,
     "kind": "recommended",
     "source": "0.08 (BashCut); 0.068 (hotclip)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.bottom": {
     "value": 0.2,
     "kind": "recommended",
     "source": "0.18 (BashCut); 0.20 (hotclip); about 30 % (vyral)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.sideWidth": {
     "value": 0.13,
     "kind": "recommended",
     "source": "0.11–0.13 (hotclip)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.sideHeight": {
     "value": 0.5,
     "kind": "recommended",
     "source": "Like/comment rail covers about the lower half (BashCut 0.46–0.5, hotclip 0.45–0.5)",
     "checked": "2026-10",
     "confidence": "measured"
    },
    "safeArea.margin": {
     "value": 0.05,
     "kind": "recommended",
     "source": "Generic title-safe margin used for square frames",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "bitrateMbps": {
     "value": 8,
     "kind": "recommended",
     "source": "Recompression line about 8 Mbps (clipforge 2026-07)",
     "checked": "2026-07",
     "confidence": "consensus"
    },
    "shape": {
     "value": "9:16",
     "kind": "hard",
     "source": "1080×1920 is the universal vertical upload (T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "disclosure": {
     "value": "Label realistic AI-generated or altered content with the platform's AI label",
     "kind": "hard",
     "source": "Platform AI-content policies (T17 §3: disclosure rules)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "title.maxChars": {
     "value": 100,
     "kind": "hard",
     "source": "YouTube title limit 100 characters (Jakeschincariol, digitalsamba, AgriciDaniel)",
     "checked": "2026-10",
     "confidence": "official"
    },
    "title.visibleChars": {
     "value": 60,
     "kind": "recommended",
     "source": "About 60 characters show (BashCut vlog publish; Jakeschincariol 40 mobile / 60 desktop)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "cover.aspect": {
     "value": "16:9",
     "kind": "info",
     "source": "Shorts thumbnail 1280×720 (hotclip 2026-08)",
     "checked": "2026-08",
     "confidence": "consensus"
    }
   }
  },
  {
   "id": "youtube",
   "title": "YouTube",
   "vertical": false,
   "fields": {
    "maxSeconds": {
     "value": null,
     "kind": "info",
     "source": "No practical length limit for verified channels (12 h upload limit)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "targetLUFS": {
     "value": -14,
     "kind": "recommended",
     "source": "Short-form apps play near −14 LUFS integrated (openmontage, kinocut tables; T11/T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "maxTruePeakDbTP": {
     "value": -1,
     "kind": "recommended",
     "source": "−1 dBTP; some tables give −1.5 for YouTube (openmontage, T17)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "safeArea.top": {
     "value": 0,
     "kind": "info",
     "source": "Landscape uses the title-safe margin",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "safeArea.bottom": {
     "value": 0,
     "kind": "info",
     "source": "Landscape uses the title-safe margin",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "safeArea.sideWidth": {
     "value": 0,
     "kind": "info",
     "source": "Landscape uses the title-safe margin",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "safeArea.sideHeight": {
     "value": 0,
     "kind": "info",
     "source": "Landscape uses the title-safe margin",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "safeArea.margin": {
     "value": 0.05,
     "kind": "recommended",
     "source": "Keep text in the central 90 % (BashCut, iart; remotion ≥80 px sides, ≥100 px top/bottom at 1080)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "bitrateMbps": {
     "value": null,
     "kind": "info",
     "source": "YouTube re-encodes every upload; no ceiling recorded",
     "checked": "2026-10",
     "confidence": "unverified"
    },
    "shape": {
     "value": "16:9",
     "kind": "hard",
     "source": "1920×1080 or 3840×2160",
     "checked": "2026-10",
     "confidence": "official"
    },
    "title.maxChars": {
     "value": 100,
     "kind": "hard",
     "source": "YouTube title limit 100 characters",
     "checked": "2026-10",
     "confidence": "official"
    },
    "title.visibleChars": {
     "value": 60,
     "kind": "recommended",
     "source": "About 60 characters on desktop, 40 on mobile (Jakeschincariol)",
     "checked": "2026-10",
     "confidence": "consensus"
    },
    "chapters": {
     "value": {
      "firstAt": 0,
      "minCount": 3,
      "minSeconds": 10
     },
     "kind": "hard",
     "source": "Chapters need 00:00 first, at least 3, each at least 10 s (vibetube, Jakeschincariol)",
     "checked": "2026-10",
     "confidence": "official"
    },
    "cover.aspect": {
     "value": "16:9",
     "kind": "info",
     "source": "Thumbnail 1280×720",
     "checked": "2026-10",
     "confidence": "official"
    },
    "disclosure": {
     "value": "Disclose realistic altered or synthetic content in YouTube Studio",
     "kind": "hard",
     "source": "YouTube altered-content disclosure (T17 §3)",
     "checked": "2026-10",
     "confidence": "consensus"
    }
   }
  }
 ]
}
"""#
}
// swiftlint:enable line_length
