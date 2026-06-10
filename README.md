# H.264/AVC I-frame Decoder — C reference model

一个从零实现的 **H.264 (ISO/IEC 14496-10) I 帧解码器** C 黄金模型，开发过程完整复刻
[jpeg_by_claude_code](https://github.com/healthyjackie-ops/jpeg_by_claude_code)
的方法论：**spec 冻结 → C 模型分阶段实现 → 参考编码器产向量 → 对参考解码器
bit-exact → 全量回归 + 错误路径测试**。

## 当前覆盖（Wave 1 完成）

| 维度 | 支持 |
|---|---|
| 码流 | Annex-B，单 IDR I 帧，EPB 去转义 |
| Profile | Baseline / Main / **High** I 帧（CAVLC + CABAC，Intra_8x8 + 8x8 变换） |
| 宏块 | I_4x4 · **I_8x8（含参考样本滤波）** · I_16x16 · I_PCM |
| 色度 | 4:2:0，8-bit，DC/H/V/Plane 预测 |
| 变换 | 4x4 整数反变换 · Intra16x16 luma DC Hadamard · 2x2 chroma DC |
| 环路滤波 | 完整 deblocking（bS 3/4、强/弱滤波、α/β/tc0、FilterOffsetA/B） |
| 尺寸 | 任意偶数尺寸（SPS frame cropping），16×16 .. 4096 宽 |
| 错误处理 | 失败统一释放输出平面；6 类损坏流全部干净拒绝，0 泄漏 |

**验证：84/84 向量对 ffmpeg (libavcodec 8.1) 逐字节 bit-exact**
（CAVLC/CABAC × baseline/main/high 共 78 个 + 6 个 expect-fail 错误用例
全拒零泄漏；覆盖 deblock on/off、α/β offset、qp 4..51、非对齐尺寸、
8x8 变换占比至 100% 的用例），外加真实照片帧抽查。
`-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror` 零告警。
CABAC 引擎经 JM 参考解码器 TRACE=2 逐 bin 对拍。

## 快速开始

```bash
brew install x264 ffmpeg          # 向量编码器 + golden 解码器
cd c_model
make                              # build/h264_decode + build/golden_compare
make test                         # 单元测试
make regress                      # 全量向量 vs ffmpeg golden（40/40）
make errtest                      # 错误向量全拒 + macOS leaks 检查
./build/h264_decode in.264 out.yuv   # 解码到 yuv420p
```

向量再生成：`python3 tools/gen_phase05.py`（no-deblock）、
`gen_phase06.py`（deblock）、`gen_error_cases.py`。

## 结构

```
c_model/src/
├── bitstream.c   # RBSP bit reader: u(n)/ue(v)/se(v)/more_rbsp_data
├── nal.c         # Annex-B 切分 + 00 00 03 去转义
├── params.c      # SPS / PPS（越界与不支持工具的硬拒绝）
├── slice.c       # I/IDR slice header
├── cavlc.c       # coeff_token/total_zeros/run_before 全表 + 残差解码
├── intra.c       # Intra4x4 ×9 / Intra16x16 ×4 / Chroma ×4
├── transform.c   # 反量化(V表) + 4x4 IDCT + Hadamard DC + chroma QP map
├── deblock.c     # 8.7 环路滤波
└── decoder.c     # MB 层 + nC 推导 + 重建 + crop + h264_decode() API
```

## 开发记录（每 phase 一个 commit）

| Phase | 内容 | 验收 |
|---|---|---|
| 0 | spec 冻结 + 骨架 | docs/spec.md |
| 1 | bitstream + NAL | 单测 |
| 2 | SPS/PPS/slice header | 解析字段 == x264 编码参数 |
| 3 | CAVLC 残差 | （随 4/5 整体验证） |
| 4 | intra + 变换 + MB 重建 | 10 例 ad-hoc 矩阵 bit-exact |
| 5 | 向量语料 + regress | 22/22 no-deblock |
| 6 | deblocking | 18/18 deblock-ON；全量 40/40 |
| 7 | 错误向量 + errtest | 6/6 拒绝，0 泄漏 |

调试一击：平坦 16×16 校准发现 LevelScale = 16×normAdjust 的 ×16 在 AC
路径与 >>4 相消、在 DC 路径不消 —— luma/chroma DC 反量化差 16 倍，修正后
全矩阵一次通过。

## 下一步（docs/roadmap.md Wave 4+）

scaling list（非 flat CQM）→ 多 slice → P 帧 → RTL。
I_PCM 已实现（CAVLC 路径）但 x264 不产 PCM 流，待 JM 编码器补向量；
CABAC+PCM 的引擎重初始化交接同样待 JM 向量后落地。

## 工具链

x264 0.165（向量编码）· ffmpeg 8.1 / libavcodec（golden）· CAVLC/deblock
数值表经 ffmpeg 源码转录自 ITU 标准。Built with Claude Code.
