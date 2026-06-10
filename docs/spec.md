# H.264/AVC I-frame Decoder — Spec v0.1 (frozen)

模仿 jpeg_by_claude_code 的开发流程：**spec 冻结 → C 黄金模型 → 参考编码器产向量 →
对参考解码器 bit-exact → 分阶段推进 + 全量回归**。RTL 在 C 模型验证收敛后启动。

## 1. 范围

### 1.1 v0.1 支持（C model）

| 维度 | 取值 |
|---|---|
| 标准 | ISO/IEC 14496-10 / ITU-T H.264 |
| 码流封装 | Annex-B byte stream（start code 00 00 01 / 00 00 00 01，EPB 去转义） |
| Profile | Baseline (66) / Constrained Baseline |
| 帧类型 | **单 IDR I 帧**（解第一个完整 coded picture 即停） |
| 熵编码 | CAVLC（entropy_coding_mode_flag = 0） |
| 宏块类型 | I_4x4（9 种预测模式）、I_16x16（4 种 × CBP 变体）、I_PCM |
| 色度 | 4:2:0（chroma_format_idc = 1），8-bit |
| 帧结构 | frame_mbs_only = 1（无场/MBAFF），num_slice_groups = 1（无 FMO） |
| Slice | 每帧恰好 1 个 slice（first_mb_in_slice = 0 覆盖全部 MB） |
| 尺寸 | 16×16 .. 4096 宽；非 16 对齐尺寸经 SPS frame cropping（4:2:0 ⇒ 宽高均为偶数） |
| 环路滤波 | Phase 06a：要求 disable_deblocking_filter_idc = 1；Phase 06b：完整 deblocking |
| 输出 | y/cb/cr 平面（yuv420p 布局，crop 后），与 ffmpeg `-pix_fmt yuv420p` 逐字节对齐 |

### 1.2 v0.1 拒绝（出 ERR 码）

CABAC · 非 4:2:0 / 非 8-bit · 场编码 / MBAFF · FMO/ASO · 多 slice ·
scaling list（seq/pic_scaling_matrix_present = 1）· transform_8x8 ·
constrained_intra_pred = 1 · redundant_pic_cnt_present = 1 · P/B slice

### 1.3 后续 wave（不阻塞 v0.1）

CABAC I 帧 → High profile（Intra_8x8 + scaling list）→ 多 slice →
P 帧（帧间预测）→ RTL。

## 2. 参考链路

| 角色 | 工具 | 用法 |
|---|---|---|
| 向量编码器 | x264 0.165 | `x264 --profile baseline --qp N --slices 1 [--no-deblock] -o v.264 raw.yuv` |
| Golden 解码器 | ffmpeg 8.1 (libavcodec) | `ffmpeg -i v.264 -f rawvideo -pix_fmt yuv420p v.yuv`（向量生成时落盘） |
| 比对 | `c_model/golden/golden_compare` | 我方解码 .264 ↔ 同名 .yuv 逐字节，输出 [PASS]/[FAIL] + SUMMARY |

H.264 解码过程完全规格化：任何一致性解码器输出 bit 相同 ⇒ 与 ffmpeg 可做
ΔY=0 ΔC=0 的硬比对（同 JPEG 对 libjpeg-turbo 的关系）。

测试图案直接在 YUV 域合成（gradient / checker / noise / flat），不经 RGB
转换 —— H.264 编码的就是 YUV 平面，规避色彩空间歧义。

## 3. C model 结构（镜像 jpeg c_model）

```
c_model/
├── src/
│   ├── bitstream.c/h    # RBSP bit reader: u(n)/ue(v)/se(v)/more_rbsp_data
│   ├── nal.c/h          # Annex-B 切分 + EPB(00 00 03)去转义 + NAL header
│   ├── params.c/h       # SPS / PPS 解析
│   ├── slice.c/h        # slice header（I/IDR）
│   ├── cavlc.c/h        # coeff_token/total_zeros/run_before 表 + 残差块解码
│   ├── intra.c/h        # Intra4x4(9 模式)/Intra16x16(4)/Chroma(4) 预测
│   ├── transform.c/h    # 反量化(V 表) + 4x4 整数反变换 + Hadamard DC
│   ├── deblock.c/h      # 环路滤波（Phase 06b）
│   ├── decoder.c/h      # MB 层解析 + 重建 + crop + h264_decode() API
│   └── main.c           # CLI: h264_decode <in.264> [out.yuv]
├── tests/               # 单元测试（bitstream / cavlc / transform ...）
├── golden/              # golden_compare.c
└── Makefile             # -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror
                         # targets: all test regress errtest phase%
```

API 镜像 jpeg：`int h264_decode(const uint8_t*, size_t, h264_decoded_t*)`，
失败统一释放输出平面只留 err（汲取 JPEG 错误路径泄漏教训，第一天就做对）。

## 4. 验收基线

1. 每 phase：该 phase 向量 100% bit-exact + `make regress` 全量零退步
2. `make test` 单元测试全过；构建在 `-Werror -Wconversion` 下零告警
3. 错误向量（截断/损坏）全部拒绝且 0 泄漏（`make errtest`，macOS leaks）
4. 文档：spec / roadmap / 每 phase 落地记录
