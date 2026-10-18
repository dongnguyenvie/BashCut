<p align="center">
  <img src=".github/assets/logo.png" width="128" height="128" alt="BashCut">
</p>

<h1 align="center">BashCut</h1>

<p align="center">
  Trình dựng video native cho macOS mà coding agent có thể điều khiển.<br>
  Mọi thao tác trên giao diện, Claude Code và Codex đều làm được qua CLI <code>bashcut</code> hoặc MCP.
</p>

<p align="center">
  <a href="https://bashcut.birchapps.com/vi">Website</a> ·
  <a href="https://bashcut.birchapps.com/vi/quickstart">Bắt đầu nhanh</a> ·
  <a href="https://bashcut.birchapps.com/vi/demo">Video demo</a> ·
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

## Video demo

Mười sáu video thuộc mười bốn thể loại, mỗi video do một agent dựng trong BashCut từ một prompt. Phần lớn có kèm
bản quay màn hình lúc agent làm việc, prompt, timeline, nguồn và giấy phép:
**[bashcut.birchapps.com/vi/demo](https://bashcut.birchapps.com/vi/demo)**.

| Ngang 16:9 | Dọc 9:16 |
|---|---|
| [Quảng cáo BashCut 30 giây](https://bashcut.birchapps.com/vi/demo/promo) | [Bản tin dọc: tin NASA](https://bashcut.birchapps.com/vi/demo/nasa) |
| [Vlog du lịch: biển, sông, phố](https://bashcut.birchapps.com/vi/demo/travel) | [Montage theo nhịp nhạc](https://bashcut.birchapps.com/vi/demo/montage) |
| [Giải thích: vì sao video là 29,97 fps](https://bashcut.birchapps.com/vi/demo/explainer) | [Cắt podcast thành short dọc](https://bashcut.birchapps.com/vi/demo/podcast) |
| [Phim tư liệu: trận Bạch Đằng năm 938](https://bashcut.birchapps.com/vi/demo/bachdang) | [Vlog đời thường: chiều đi dạo](https://bashcut.birchapps.com/vi/demo/daily) |
| [Giới thiệu căn hộ mẫu](https://bashcut.birchapps.com/vi/demo/realestate) | [Vietsub cho clip phim nước ngoài](https://bashcut.birchapps.com/vi/demo/vietsub) |
| [Hướng dẫn: thêm phụ đề trong 1 phút](https://bashcut.birchapps.com/vi/demo/tutorial) | [Xoá logo và watermark — trước / sau](https://bashcut.birchapps.com/vi/demo/logo) |

## Bắt đầu nhanh

Từ con số không đến lần sửa đầu tiên của agent trong khoảng năm phút. Hướng dẫn đầy đủ, có ảnh chụp và prompt để
copy, ở **[bashcut.birchapps.com/vi/quickstart](https://bashcut.birchapps.com/vi/quickstart)**.

1. **Cài đặt** (macOS 14+ và Homebrew): `brew install --cask dongnguyenvie/tap/bashcut`. Các cách khác ở mục
   [Cài đặt](#cài-đặt).
2. **Kết nối agent.** Trong BashCut không cần làm gì: tab Claude và Codex trong agent dock đã có sẵn skill. Để dùng
   Claude Code hoặc Codex trong terminal của bạn, chạy `bashcut agent setup claude` hoặc `bashcut agent setup codex`,
   hoặc thêm kit dưới dạng plugin Claude Code: `/plugin marketplace add dongnguyenvie/bashcut-agent-kit`, rồi
   `/plugin install bc@bashcut-agent-kit`.
3. **Cài các plugin khuyên dùng.** Gõ `/bc:setup` một lần trong tab Claude hoặc Codex: agent cài phụ đề (Whisper),
   giọng tiếng Việt, đánh dấu khoảng lặng và AI Editor, rồi kiểm tra chúng chạy được. Hoặc tự cài trong
   **Plugins › Browse**. API key nhập trong Options của plugin, không bao giờ nhập vào chat.
4. **Tạo project**, nhập clip và mở tab Claude trong agent dock.
5. **Nói điều bạn muốn**, ví dụ *"Dựng các clip này thành vlog dọc 60 giây. Cho tôi xem kế hoạch trước khi cắt."*,
   hoặc bấm **Brief** trong agent dock và chọn một trong 25 mẫu.
6. **Xem lại, hoàn tác, xuất video.** Mọi thay đổi đều nằm trong Lịch sử. Nhờ agent review, hoàn tác chỗ bạn không
   thích, rồi xuất video.

## Giới thiệu

BashCut là trình dựng video native cho macOS, xây trên AVFoundation, có terminal Claude Code / Codex gắn ngay
cạnh timeline. Preview và export dùng chung một engine dựng hình, nên thứ bạn xem là thứ được xuất ra. Project là
file JSON thuần nằm cạnh footage: agent và script đọc, sửa project qua đúng các thao tác chỉnh sửa nguyên tử, có
undo, mà giao diện đang dùng.

BashCut đang được phát triển tích cực. Xem [CHANGELOG](CHANGELOG.md) để biết những gì đã thay đổi và
[trạng thái triển khai](docs/status/implementation.md) để biết phần nào đã kiểm chứng và phần nào còn lại.

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
- **Chuyển cảnh**: 39 kiểu chia theo nhóm (fade, whip, wipe, shape, crash, roll, seamless, glitch…) và preset
  chuyển cảnh đã lưu; phụ đề, tiêu đề, sticker và overlay cũng dùng được chúng làm hiệu ứng vào (In) và ra (Out)
- **Ảnh tĩnh** và sticker (emoji hoặc ảnh) trên timeline
- **Đổi khung hình** của project đang mở (9:16, 16:9, 1:1…) mà không phải dựng lại
- **Reframe và làm sạch hình**: reframe theo chủ thể cho bản dọc, nền blur cho ảnh và clip lệch tỉ lệ, làm mờ, làm
  nhoè mosaic (`pixelate`) và viền mềm (`feather`) trên clip, tách nền ảnh
- **Chọn nhiều**: sửa chung trong Inspector, di chuyển cả khối, copy và paste giữa các project
- Phát bằng J/K/L, xem trước toàn màn hình, clip trên timeline có màu theo loại

### Phụ đề và chữ

- Nhận giọng nói thành phụ đề bằng plugin Whisper chạy trên máy, nhập và xuất SubRip
- **Phụ đề từng chữ**: kiểu highlight, karaoke và reveal
- Preset chữ cho tiêu đề hook, nhãn địa điểm, sticker từ khoá và thẻ chương, giữ nguyên kiểu khi sửa; tiếng Việt và
  tiếng Anh ở mọi nơi; hai font trong một tiêu đề, tiêu đề ảnh bìa đọc rõ trên điện thoại, brand kit
- **Vietsub** qua plugin Translate Captions: dịch mọi dòng phụ đề mà giữ nguyên thời gian và kiểu chữ, che phụ đề
  đã burn sẵn trong footage, làm mờ logo kênh và watermark

### Màu

- Nhập LUT (`.cube`), exposure, contrast và saturation
- **Adjustment layer** và **chuỗi filter** áp lên mọi thứ bên dưới
- **Look** và **style kit**: lưu một tone màu (kèm LUT) và một kiểu phụ đề, áp cho video tiếp theo chỉ một bước

### Âm thanh

- Âm lượng, fade, keyframe âm lượng, chuẩn hoá loudness khi xuất
- **Nhạc nền** giữ một mức cố định, thấp hơn độ to đo được của giọng nói; chỉ ducking khi bạn yêu cầu, và nhạc
  được giữ thấp qua các quãng nghỉ ngắn nên không nhấp nhô giữa các câu
- Thu voiceover, và tạo giọng đọc bằng plugin (VieNeu TTS cho tiếng Việt, giọng clone)
- **Beat grid** từ nhạc để cắt theo nhịp
- Đo loudness, true peak và năng lượng dải giọng nói, **đồng bộ** camera với video quay màn hình bằng âm thanh, không
  cần ffmpeg

### Thư viện

- Một thư viện chung cho nhạc và SFX, kiểu chữ, sticker, công thức hiệu ứng, preset chuyển cảnh và look: mục có sẵn,
  mục của bạn (cho project này hoặc mọi project), và gói do plugin mang theo
- Tìm kiếm, tag, gói, nhập/xuất gói, thống kê sử dụng, và **tìm hoặc tạo** mục mới qua plugin (ảnh, video, nhạc
  và SFX từ nguồn mở; minh hoạ AI giữ một phong cách cố định)
- **Tìm mọi tài nguyên** (⇧⌘F): media của project, selects và toàn bộ thư viện trong một ô tìm, không phân biệt dấu
  và đ

### Kiểm tra và xuất video

- Review: khoảng trống trong hình, khung lặp giữa hai cut, dòng phụ đề quá dài, lỗi nhận dạng lặp, voiceover quá gần
  giọng thật; lịch sử đầy đủ; autosave có khôi phục khi crash; tự tải lại khi file bị sửa bên ngoài, có xử lý xung đột
- Proxy xem trước cho footage nặng; preset xuất cho TikTok, YouTube 1080p và 4K, bản nháp nhanh và ProRes, chạy nền
  theo hàng đợi, có phụ đề burn-in và file `.srt` tuỳ chọn; xuất OTIO. Xuất nhiều bản (ví dụ một bản TikTok và một
  bản YouTube) trong một lần. Agent chỉ xuất bản cuối khi bản nháp đã qua audit, và không xuất khi đồ hoạ vẫn còn là
  bản render nháp
- **Batch pipeline**: chạy cùng các bước trên nhiều file hoặc project (nhập, phụ đề, dịch, ảnh bìa, xuất…), mỗi đầu
  vào một project riêng. Tạo, lưu và chạy trong cửa sổ Batch hoặc bằng `bashcut batch`; kiểm tra key, file và dung
  lượng đĩa trước khi chạy, chạy lại từ bước lỗi và chạy tiếp sau khi thoát app

### AI agent

- **Agent dock**: terminal Claude Code, Codex và Shell thật cạnh timeline, cùng agent chat và agent terminal từ
  plugin (AI Editor bằng API key của bạn, Antigravity…). Thẻ thiết lập hai bước giúp cài skill cho agent và các
  plugin dựng phim nên dùng
- **Giao việc** (⌘K, hoặc thanh giao việc dưới terminal): 25 mẫu yêu cầu với chip và ô điền, các yêu cầu gần đây và
  đã lưu, cùng dòng **Footage** để thêm file và thư mục cho agent nhập vào project. Menu **To** chọn agent nhận việc
  (mặc định là agent dùng gần nhất, hoặc mở agent mới); yêu cầu chỉ được gửi khi agent đã sẵn sàng
- **Tin cậy thư mục ngay trong BashCut**: BashCut hỏi trước khi Claude Code hoặc Codex làm việc trong một thư mục
  mới, và chấp nhận chế độ Bypass Permissions của Claude Code trong cùng hộp thoại, nên menu riêng của các CLI không
  còn hiện ra
- **Gửi cho Agent**: chọn clip rồi gửi kèm yêu cầu; **scope guard** giữ cho agent chỉ sửa những clip đó, hoặc hỏi
  bạn trước
- **Show Changes**: xem agent đã sửa gì, nhảy tới chỗ đó, và hoàn tác cả lượt trong một bước
- **Kiến thức**: agent nhớ bài học, sở thích của bạn và thông tin project giữa các phiên; duyệt trong hộp duyệt của
  cửa sổ Kiến thức, sửa ghi chú và skill của project, và hoàn tác mọi thay đổi từ lịch sử
- **[Agent kit](https://github.com/dongnguyenvie/bashcut-agent-kit)**: các skill dựng video (khảo sát footage, cắt
  theo nhịp, trộn âm, phụ đề, màu, hiệu ứng, lồng tiếng, học style, tự rút kinh nghiệm) nạp sẵn vào mọi tab agent
- **Quyền của agent**: chọn những gì agent được làm mà không cần hỏi (sửa, xuất video, hành động plugin), hoặc cho
  phép tất cả

### Skill

Các skill của agent kit hiện dưới dạng `bc:<tên>` trong Claude Code và Codex:

- `bc:edit-workflow`: cả quy trình dựng từ lúc nhận yêu cầu tới khi xuất, có cổng duyệt, checklist và audit; đọc
  skill này trước
- `bc:footage-survey`: kiểm kê, contact sheet và mô tả từng shot trước khi cắt
- `bc:rough-cut`: chọn đoạn theo câu nói, bỏ take hỏng, chừa đệm và cắt dài thành ngắn
- `bc:beat-cut`: cắt theo beat hoặc theo câu, đo nhịp để kiểm tra, punch-in
- `bc:audio-mix`: đo âm theo vai trò, chỉnh mức, ducking, nhạc, SFX và loudness cho từng bản xuất
- `bc:voiceover`: lời đọc vừa khoảng trống, take giọng đọc AI được kiểm tra và đọc lại tại chỗ, lồng tiếng
- `bc:captions-text`: phụ đề, thời điểm từng chữ, tiêu đề, thẻ chữ và font hiển thị đúng ngôn ngữ
- `bc:color-grade`: chỉnh màu có đo đạc, look và LUT
- `bc:effects`: hiệu ứng nào hợp khoảnh khắc nào, bằng chuyển cảnh, tốc độ và reframe có sẵn
- `bc:visual-plan`: người xem thấy gì trên từng câu của video nói chuyện
- `bc:motion-graphics`: đồ hoạ thiết kế phủ lên footage (thẻ, bộ đếm số, chữ chuyển động)
- `bc:stock-images`: ảnh, video stock và icon làm hình minh hoạ
- `bc:style-study`: đo một phong cách mẫu rồi biến thành ghi chú, look và text preset
- `bc:library`: tạo, giữ lại và dọn các mục thư viện
- `bc:review`: vòng soát lỗi trước khi xuất
- `bc:self-learn`: bài học, sở thích và thông tin trong phần Kiến thức của BashCut
- `bc:setup`: cài các plugin nên dùng (chỉ khi bạn gõ `/bc:setup`)

Các công thức theo chủ đề (`bashcut.vlog:plan`, du lịch, ăn uống, video giải thích, viết hook, đăng bài…) đi kèm
plugin Vlog trong [bashcut-plugins](https://github.com/dongnguyenvie/bashcut-plugins) và được nạp như skill của plugin.

### Tự động hoá

- CLI `bashcut` và MCP server bao trọn mọi thao tác, hộp thoại, phím tắt và chế độ xem: 248 lệnh, có chạy thử, kiểm
  tra revision và mỗi lệnh là một thay đổi hoàn tác được ([danh sách lệnh](docs/reference/commands.md))
- **Cả bản dựng là một danh sách**: `plan check` kiểm tra cả bản cắt (clip, phụ đề, tiêu đề, chuyển cảnh,
  voiceover, đồ hoạ và mix) và `plan apply` dựng nó trong một bước hoàn tác được, giữ các chỉnh sửa bằng tay
- `ui frame` xuất một khung hình bất kỳ ra PNG để agent tự xem kết quả
- Command palette (⇧⌘P), menu bar đầy đủ kiểu Mac và Settings có ô tìm kiếm

### Plugin

- Plugin chạy ngoài tiến trình, viết bằng ngôn ngữ nào cũng được: capability (nhận giọng nói, giọng đọc, beat,
  loudness, đồng bộ, tìm và tạo mục thư viện), action trong menu và menu chuột phải, hook theo sự kiện, tuỳ chọn,
  agent chat và agent terminal, gói thư viện và **skill cho agent** dạy agent cách dùng plugin
- **Giao diện plugin**: plugin có thể có panel riêng ở rail bên trái, tab trong agent dock, sheet và cửa sổ riêng
  (timeline vẫn sửa được khi cửa sổ đang mở), với các view do BashCut vẽ native từ component plugin gửi sang
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
Homebrew, để agent ở bất kỳ terminal nào cũng điều khiển được app. Cập nhật bằng **BashCut › Check for Updates… ›
Cập nhật ngay** (Homebrew tải bản mới, rồi BashCut tự thoát và mở bản mới) hoặc `brew upgrade --cask bashcut`; gỡ
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
`scripts/bench-agents.py` là bench A/B chạy tay: cùng một yêu cầu cho Claude Code và Codex, khởi chạy y như app,
rồi so token, lệnh gọi tool, thời gian và kết quả review cuối; kết quả nằm trong
[trạng thái triển khai](docs/status/implementation.md).

## Các repository liên quan

Hai repository khác cũng thuộc BashCut. Mọi đóng góp đều được hoan nghênh:

| Repository | Chứa gì | Đóng góp gì ở đó |
|---|---|---|
| [bashcut-plugins](https://github.com/dongnguyenvie/bashcut-plugins) | Plugin registry (`registry.json`) và các plugin: Whisper Captions, VieNeu TTS, Translate Captions, Silence Markers, HyperFrames Graphics, Image Generation, Online Resources, công thức Vlog, AI Editor và Antigravity | Plugin mới và sửa plugin hiện có. Xem [Viết plugin](docs/guides/plugins.md) |
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
