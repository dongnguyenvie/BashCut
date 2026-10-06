<p align="center">
  <img src=".github/assets/logo.png" width="128" height="128" alt="BashCut">
</p>

<h1 align="center">BashCut</h1>

<p align="center">
  Trình dựng video native cho macOS mà coding agent có thể điều khiển.<br>
  Mọi thao tác trên giao diện, Claude Code và Codex đều làm được qua CLI <code>bashcut</code> hoặc MCP.
</p>

<p align="center">
  <a href="https://github.com/dongnguyenvie/BashCut/releases/latest">Tải về</a> ·
  <a href="https://testflight.apple.com/join/XwsNZxre">Beta TestFlight</a> ·
  <a href="docs/README.md">Tài liệu</a> ·
  <a href="docs/guides/automation.md">Tự động hóa</a> ·
  <a href="docs/guides/plugins.md">Plugin</a> ·
  <a href="https://github.com/dongnguyenvie/bashcut-agent-kit">Agent kit</a> ·
  <a href="https://github.com/dongnguyenvie/BashCut/issues">Báo lỗi</a>
</p>

<p align="center">
  <a href="README.md">English</a>
</p>

---

<p align="center">
  <img alt="Demo BashCut: terminal Codex, timeline nhiều layer, phụ đề, chuyển cảnh, màu và plugin" src=".github/assets/app.gif" width="800">
</p>

## Giới thiệu

BashCut là trình dựng video native cho macOS, xây trên AVFoundation, có terminal Claude Code / Codex gắn ngay
cạnh timeline. Preview và export dùng chung một engine dựng hình, nên thứ bạn xem là thứ được xuất ra. Project là
file JSON thuần nằm cạnh footage: agent và script đọc, sửa project qua đúng các thao tác chỉnh sửa nguyên tử, có
undo, mà giao diện đang dùng.

BashCut đang được phát triển tích cực: nền tảng M0 đã được nghiệm thu trên footage thật, phần lớn tính năng dựng
và agent (M1–M3, M5) đã có. Xem [trạng thái triển khai](docs/status/implementation.md) để biết phần nào đã kiểm
chứng và phần nào còn lại.

## Dùng AI bạn đang trả tiền sẵn

Không tốn thêm tiền AI: BashCut chạy được với gói đăng ký và ứng dụng bạn đã có.

| Bạn đang có | BashCut dùng nó thế nào |
|---|---|
| **Gói Claude** (Pro / Max) | Tab **Claude** trong agent dock chạy Claude Code CLI thật bằng tài khoản đã đăng nhập. BashCut không truyền `ANTHROPIC_API_KEY`, nên dùng gói đăng ký chứ không trừ credit API |
| **Gói ChatGPT** (Plus / Pro) | Tab **Codex** chạy Codex CLI thật bằng tài khoản ChatGPT của bạn |
| **Claude Desktop / Codex app** | Kết nối với BashCut: `bashcut agent setup claude` hoặc `bashcut agent setup codex` cài skill dựng video và MCP server `bashcut`, để chúng sửa project đang mở từ bên ngoài app |
| **Model khác** (Gemini, GPT, Grok, Mistral, Groq, OpenRouter, server local hoặc tương thích OpenAI) | Cài plugin **[AI Editor](https://github.com/dongnguyenvie/bashcut-plugins/tree/main/plugins/director)**: agent chat ngay trong BashCut bằng API key của bạn, có mức thinking (`off` / `low` / `medium` / `high`) cho model suy luận |

Dù chọn cách nào, agent cũng sửa qua đúng các lệnh có undo mà giao diện dùng: mọi thay đổi vào Lịch sử, hiện trong
Show Changes và hoàn tác được. Xem [Tự động hóa](docs/guides/automation.md).

## Có gì bên trong

### Dựng phim

- **Timeline nhiều layer**: bao nhiêu layer video, overlay, chữ, sticker, adjustment, voiceover, nhạc và SFX cũng
  được, có audio liên kết, section, snap, chọn nhiều clip, khoảng trống, cắt, trim, di chuyển, lift và ripple delete
- **Viewer và source viewer**: In/Out, Insert/Overwrite, phóng to viewer, vùng an toàn và so sánh trước/sau
- **Tốc độ**: đổi tốc độ cố định, tua ngược, freeze frame và speed ramp kiểu CapCut (montage, hero, bullet,
  jump-cut, flash in/out, hoặc đường cong tự vẽ)
- **Chuyển động**: keyframe cho vị trí, tỉ lệ, xoay, độ mờ và âm lượng, hiện ngay trên timeline, cùng preset hoạt
  ảnh (zoom, pan, Ken Burns, pop-in, slide-up, zoom-punch); crop và bo góc
- **Chuyển cảnh**: dissolve, whip, blink, zoom, spin, shutter, wipe và preset chuyển cảnh đã lưu
- **Ảnh tĩnh** và sticker (emoji hoặc ảnh) trên timeline
- **Đổi khung hình** của project đang mở (9:16, 16:9, 1:1…) mà không phải dựng lại

### Phụ đề và chữ

- Nhận giọng nói thành phụ đề bằng plugin Whisper chạy trên máy, nhập và xuất SubRip
- **Phụ đề từng chữ**: kiểu highlight, karaoke và reveal
- Preset chữ cho tiêu đề hook, nhãn địa điểm, sticker từ khoá và thẻ chương, giữ nguyên kiểu khi sửa; tiếng Việt và
  tiếng Anh ở mọi nơi

### Màu

- Nhập LUT (`.cube`), exposure, contrast và saturation
- **Adjustment layer** và **chuỗi filter** áp lên mọi thứ bên dưới
- **Look** và **style kit**: lưu một tone màu (kèm LUT) và một kiểu phụ đề, áp cho video tiếp theo chỉ một bước

### Âm thanh

- Âm lượng, fade, keyframe âm lượng, ducking nhạc dưới giọng nói, chuẩn hoá loudness khi xuất
- Thu voiceover, và tạo giọng đọc bằng plugin (VieNeu TTS cho tiếng Việt, giọng clone)
- **Beat grid** từ nhạc để cắt theo nhịp
- Đo loudness, true peak và năng lượng dải giọng nói, **đồng bộ** camera với video quay màn hình bằng âm thanh, không
  cần ffmpeg

### Thư viện

- Một thư viện chung cho nhạc và SFX, kiểu chữ, sticker, công thức hiệu ứng, preset chuyển cảnh và look: mục có sẵn,
  mục của bạn (cho project này hoặc mọi project), và gói do plugin mang theo
- Tìm kiếm, tag, gói, nhập/xuất gói, thống kê sử dụng, và **tìm hoặc tạo** mục mới qua plugin

### Kiểm tra và xuất video

- Review: khoảng trống trong hình, khung lặp giữa hai cut, dòng phụ đề quá dài, lỗi nhận dạng lặp, voiceover quá gần
  giọng thật; lịch sử đầy đủ; autosave có khôi phục khi crash; tự tải lại khi file bị sửa bên ngoài, có xử lý xung đột
- Proxy xem trước cho footage nặng; preset xuất cho TikTok, YouTube 1080p và 4K, bản nháp nhanh và ProRes, chạy nền
  theo hàng đợi, có phụ đề burn-in và file `.srt` tuỳ chọn; xuất OTIO

### AI agent

- **Agent dock**: terminal Claude Code, Codex và Shell thật cạnh timeline, cùng agent chat và agent terminal từ
  plugin (AI Editor bằng API key của bạn, Antigravity…)
- **Gửi cho Agent**: chọn clip rồi gửi kèm yêu cầu; **scope guard** giữ cho agent chỉ sửa những clip đó, hoặc hỏi
  bạn trước
- **Show Changes**: xem agent đã sửa gì, nhảy tới chỗ đó, và hoàn tác cả lượt trong một bước
- **Kiến thức**: agent nhớ bài học, sở thích của bạn và thông tin project giữa các phiên; duyệt trong hộp duyệt của
  cửa sổ Kiến thức, sửa ghi chú và skill của project, và hoàn tác mọi thay đổi từ lịch sử
- **[Agent kit](https://github.com/dongnguyenvie/bashcut-agent-kit)**: các skill dựng video (khảo sát footage, cắt
  theo nhịp, trộn âm, phụ đề, màu, hiệu ứng, lồng tiếng, học style, tự rút kinh nghiệm) nạp sẵn vào mọi tab agent
- **Quyền của agent**: chọn những gì agent được làm mà không cần hỏi (sửa, xuất video, hành động plugin), hoặc cho
  phép tất cả

### Tự động hoá

- CLI `bashcut` và MCP server bao trọn mọi thao tác, hộp thoại, phím tắt và chế độ xem: 140 lệnh, có chạy thử, kiểm
  tra revision và mỗi lệnh là một thay đổi hoàn tác được ([danh sách lệnh](docs/reference/commands.md))
- `ui frame` xuất một khung hình bất kỳ ra PNG để agent tự xem kết quả
- Command palette (⇧⌘P), menu bar đầy đủ kiểu Mac và Settings có ô tìm kiếm

### Plugin

- Plugin chạy ngoài tiến trình, viết bằng ngôn ngữ nào cũng được: capability (nhận giọng nói, giọng đọc, beat,
  loudness, đồng bộ, tìm và tạo mục thư viện), action trong menu và menu chuột phải, hook theo sự kiện, tuỳ chọn,
  agent chat và agent terminal, gói thư viện và **skill cho agent** dạy agent cách dùng plugin
- [Plugin registry](https://github.com/dongnguyenvie/bashcut-plugins) có chữ ký, với Duyệt, cài một chạm, kiểm tra
  cập nhật hằng ngày, Trust từng plugin và cài dependency không cần mở Terminal; cũng cài được từ link hoặc thư mục.
  Xem [Viết plugin](docs/guides/plugins.md)

## Cài đặt

Cần macOS 14 trở lên.

### Homebrew

```sh
brew install --cask dongnguyenvie/tap/bashcut
```

Lệnh này cài `BashCut.app` vào `/Applications` và link CLI `bashcut` cùng server `bashcut-mcp` vào `bin` của
Homebrew, để agent ở bất kỳ terminal nào cũng điều khiển được app. Cập nhật bằng `brew upgrade --cask bashcut`; gỡ
bằng `brew uninstall --cask bashcut` (thêm `--zap` để xóa luôn cài đặt và cache).

### Tải bản release

Tải `BashCut-<version>.dmg` (hoặc `.zip`) ở [bản release mới nhất](https://github.com/dongnguyenvie/BashCut/releases/latest),
mở ra rồi kéo BashCut vào Applications. Các bản build được ký Developer ID và Apple notarize; kiểm tra file tải về
với `SHA256SUMS` của release bằng `shasum -a 256 -c --ignore-missing SHA256SUMS`. Muốn dùng CLI từ terminal thì tự tạo link:

```sh
sudo ln -s /Applications/BashCut.app/Contents/MacOS/bashcut /usr/local/bin/bashcut
sudo ln -s /Applications/BashCut.app/Contents/MacOS/bashcut-mcp /usr/local/bin/bashcut-mcp
```

### TestFlight

Tham gia bản beta công khai qua [TestFlight](https://testflight.apple.com/join/XwsNZxre) (cần app TestFlight). Bản
TestFlight là bản Mac App Store có sandbox: chỉ chạy plugin đi kèm app, và CLI đi kèm không chạy được từ terminal
thông thường.

Hoặc build BashCut từ mã nguồn, xem bên dưới.

## Build

Cần macOS 14 trở lên, Xcode có Swift 6, và kết nối mạng cho lần tải package đầu tiên.

```sh
scripts/run.sh
```

Script này build bằng SwiftPM, đóng gói `build/BashCut.app`, ký bằng Apple Development identity đầu tiên trong
keychain (hoặc `BASHCUT_SIGN_IDENTITY`) để macOS giữ quyền truy cập thư mục qua các lần build, rồi mở app. File
thực thi của app là `BashCutApp` và CLI đi kèm là `bashcut`, để tránh trùng tên trên ổ đĩa không phân biệt hoa
thường.

Để thử một thay đổi với mọi trường hợp trên timeline, tạo [project mẫu](docs/guides/sample-project.md) như trong
ảnh trên (cần `ffmpeg`):

```sh
scripts/sample-project.py
```

Với Xcode, cài XcodeGen >= 2.46, chạy `scripts/generate-project.sh` rồi mở `BashCut.xcodeproj` (sinh từ
`project.yml`). Xcode build string catalog; launcher SwiftPM chép các file `.strings` tương ứng. Giao diện theo
ngôn ngữ hệ thống.

## Kiểm tra

```sh
scripts/verify.sh build
scripts/verify.sh test
scripts/verify.sh perf       # 20 clip tổng hợp, ~30 giây, 1080×1920
scripts/verify.sh lint       # cần SwiftLint
scripts/verify.sh xcode test # sinh lại và test project Xcode (cần XcodeGen)
```

Test model thuần cũng chạy riêng được bằng `cd Packages/BashCutCore && swift test`. Test không bao giờ dùng
workspace video thật hay agent CLI, và việc tải package chỉ xảy ra khi resolve dependency, không phải trong test.

## Các repository liên quan

Hai repository khác cũng thuộc BashCut. Mọi đóng góp đều được hoan nghênh:

| Repository | Chứa gì | Đóng góp gì ở đó |
|---|---|---|
| [bashcut-plugins](https://github.com/dongnguyenvie/bashcut-plugins) | Plugin registry (`registry.json`) và các plugin: Whisper Captions, VieNeu TTS, Silence Markers, AI Editor và Antigravity | Plugin mới và sửa plugin hiện có. Xem [Viết plugin](docs/guides/plugins.md) |
| [bashcut-agent-kit](https://github.com/dongnguyenvie/bashcut-agent-kit) | Skill dựng video cho Claude Code và Codex (khảo sát footage, cắt theo beat, mix âm thanh, phụ đề, màu, hiệu ứng, voiceover…). BashCut đóng gói sẵn và nạp chúng trong các tab agent | Kinh nghiệm dựng mà agent nên làm theo. Xem README › Writing skills của repo đó |

Thay đổi cho chính trình dựng, các lệnh và plugin API thuộc về repository này.

## Tài liệu

Tài liệu chi tiết hiện chỉ có bằng tiếng Anh.

- [Mục lục tài liệu](docs/README.md): hướng dẫn, tham chiếu và đặc tả thiết kế
- [Tự động hóa: CLI và MCP](docs/guides/automation.md) cùng [danh sách lệnh](docs/reference/commands.md) (sinh tự động)
- [Định dạng project](docs/reference/project-format.md)
- [Trạng thái triển khai](docs/status/implementation.md)
- [CONTRIBUTING.md](CONTRIBUTING.md): cấu trúc build và các mẫu một file (agent provider, model adapter, lệnh,
  capability, định dạng timeline)
- [CHANGELOG.md](CHANGELOG.md)

## Giấy phép

MIT. Xem [LICENSE](LICENSE).
